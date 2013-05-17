#-----------------------------------------------------------------
# Proc::Async
# Author: Martin Senger <martin.senger@gmail.com>
# For copyright and disclaimer se below.
#
# ABSTRACT: Running and monitoring processes asynchronously
# PODNAME: Proc::Async
#-----------------------------------------------------------------

use warnings;
use strict;
package Proc::Async;

use Carp;
use File::Temp qw{ tempdir };
use File::Path qw{ remove_tree };
use File::Spec;
use File::Find;
use File::Slurp;
use Proc::Async::Config;
use Proc::Daemon;
use Config;

# VERSION

use constant STDOUT_FILE => '___proc_async_stdout___';
use constant STDERR_FILE => '___proc_async_stderr___';
use constant CONFIG_FILE => '___proc_async_status.cfg';

use constant {
    STATUS_UNKNOWN     => 'unknown',
    STATUS_CREATED     => 'created',
    STATUS_RUNNING     => 'running',
    STATUS_COMPLETED   => 'completed',
    STATUS_TERM_BY_REQ => 'terminated by request',
    STATUS_TERM_BY_ERR => 'terminated by error',
    STATUS_REMOVED     => 'removed',
};

my $KNOWN_OPTIONS = {
    # DIR     => 1,
    TIMEOUT => 1,
};

#-----------------------------------------------------------------
# Start an external program and return its ID.
#    starts ($args, [$options])
#    starts (@args, [$options])
#  $args    ... an arrayref with the full command-line (including the
#               external program name)
#  @args    ... an array with the full command-line (including the
#               external program name)
#  $options ... a hashref with additional options:
####               DIR => a directory where to create JOB directories
#               TIMEOUT => number of second to spend
#-----------------------------------------------------------------
sub start {
    my $class = shift;
    croak ("START: Undefined external process.")
	unless @_ > 0;
    my ($args, $options) = _process_start_args (@_);
    _check_options ($options);

    # create a job ID and a job directory
    my $jobid = _generate_job_id ($options);
    my $dir = _id2dir ($jobid);

    # create configuration file
    my ($cfg, $cfgfile) = _start_config ($jobid, $args, $options);

    # demonize itself
    my $daemon = Proc::Daemon->new(
	work_dir     => $dir,
	child_STDOUT => File::Spec->catfile ($dir, STDOUT_FILE),
	child_STDERR => File::Spec->catfile ($dir, STDERR_FILE),
	);
    my $daemon_pid = $daemon->Init();
    if ($daemon_pid) {
	# this is a parent of the already detached daemon
	return $jobid;
    }

    #
    # --- this is the daemon (child) branch
    #

    # fork and start an external process
    my $pid = fork();

    if ($pid) {
	#
	# --- this branch is executed in the parent (wrapper) process;
	#

	# update the configuration file
	$cfg->param ("job.pid", $pid);
	update_status ($cfg,
		       STATUS_RUNNING,
		       "started at " . scalar localtime());
	$cfg->param ("job.started", time());
	$cfg->save();

	# wait for the child process to finish
	# TBD: if TIMEOUT then use alarm and non-blocking waitpid
	my $reaped_pid = waitpid ($pid, 0);
	my $reaped_status = $?;

	if ($reaped_status == -1) {
	    update_status ($cfg,
			   STATUS_UNKNOWN,
			   "No such child process"); # can happen?

	} elsif ($reaped_status & 127) {
	    update_status ($cfg,
			   STATUS_TERM_BY_REQ,
			   "terminated by signal " . ($reaped_status & 127),
			   (($reaped_status & 128) ? "with" : "without") . " coredump",
			   "terminated at " . scalar localtime(),
			   _elapsed_time ($cfg));

	} else {
	    my $exit_code = $reaped_status >> 8;
	    if ($exit_code == 0) {
		update_status ($cfg,
			       STATUS_COMPLETED,
			       "exit code $exit_code",
			       "completed at " . scalar localtime(),
			       _elapsed_time ($cfg));
	    } else {
		update_status ($cfg,
			       STATUS_TERM_BY_ERR,
			       "exit code $exit_code",
			       "completed at " . scalar localtime(),
			       _elapsed_time ($cfg));
	    }
	}
	$cfg->save();

	# the wrapper of the daemon finishes; do not return anything
	exit (0);

    } elsif ($pid == 0) {
	#
	# --- this branch is executed in the just started child process
	#

	# replace itself by an external process
	exec (@$args) or
	    croak "Cannot execute the external process: " . _join_args ($args) . "\n";

    } else {
	#
	# --- this branch is executed only when there is an error in the forking
	#
	croak "Cannot start an external process: " . _join_args ($args) . " - $!\n";
    }
}

#-----------------------------------------------------------------
# Pretty print of the list of arguments (given as an arrayref).
#-----------------------------------------------------------------
sub _join_args {
    my $args = shift;
    return join (" ", map {"'$_'"} @$args);
}

#-----------------------------------------------------------------
# Return a pretty-formatted elapsed time of the just finished job.
#-----------------------------------------------------------------
sub _elapsed_time {
    my $cfg = shift;
    my $started = $cfg->param ("job.started");
    return "elapsed time unknown" unless $started;
    my $elapsed = time() - $started;
    return "elapsed time $elapsed seconds";
}

#-----------------------------------------------------------------
# Extract arguments for the start() method and return:
#  ( [args], {options} )
# -----------------------------------------------------------------
sub _process_start_args {
    my @args;
    my $options;
    if (ref $_[0] and ref $_[0] eq 'ARRAY') {
	# arguments for external process are given as an arrayref...
	@args = @{ shift() };
	$options = (ref $_[0] and ref $_[0] eq 'HASH') ? shift @_ : {};
    } else {
	# arguments for external process are given as an array...
	$options = (ref $_[-1] and ref $_[-1] eq 'HASH') ? pop @_ : {};
	@args = @_;
    }
    return (\@args, $options);
}

#-----------------------------------------------------------------
# Update status and its details (just in memory - in the given $cfg).
#-----------------------------------------------------------------
sub update_status {
    my ($cfg, $status, @details) = @_;

    # remove the existing status and its details
    $cfg->remove ("job.status");
    $cfg->remove ("job.status.detail");

    # put updated values
    $cfg->param ("job.status", $status);
    foreach my $detail (@details) {
	$cfg->param ("job.status.detail", $detail);
    }

    # note the finished time if the new status indicates the termination
    if ($status eq STATUS_COMPLETED or
	$status eq STATUS_TERM_BY_REQ or
	$status eq STATUS_TERM_BY_ERR) {
	$cfg->param ("job.ended", time());
    }
}

# -----------------------------------------------------------------
# Return status of the given job (given by $jobid). In array context,
# it also returns (optional) details of the status.
# -----------------------------------------------------------------
sub status {
    my ($class, $jobid) = @_;
    return unless defined wantarray; # don't bother doing more
    my $dir = _id2dir ($jobid);
    my ($cfg, $cfgfile) = $class->get_configuration ($dir);
    my $status = $cfg->param ('job.status') || STATUS_UNKNOWN;
    my @details = ($cfg->param ('job.status.detail') ? $cfg->param ('job.status.detail') : ());
    return wantarray ? ($status, @details) : $status;
}

#-----------------------------------------------------------------
# Return the name of the working directory for the given $jobid.
# Or undef if such working directory does not exist.
# -----------------------------------------------------------------
sub working_dir {
    my ($class, $jobid) = @_;
    my $dir = _id2dir ($jobid);
    return -e $dir && -d $dir ? $dir : undef;
}

#-----------------------------------------------------------------
# Return a list of (some) filenames in a job directory that is
# specified by the given $jobid. The filenames are relative to this
# job directory, and they may include subdirectories if there are
# subdirectories within this job directory. The files with the special
# names (see the constants STDOUT_FILE, STDERR_FILE, CONFIG_FILE) are
# ignored. If there is an empty directory, it is also ignored.
#
# For example, if the contents of a job directory is:
#    ___proc_async_stdout___
#    ___proc_async_stderr___
#    ___proc_async_status.cfg
#    a.file
#    a.dir/
#       file1
#       file2
#       b.dir/
#          file3
#    empty.dir/
#
# then the returned list will look like this:
#    ('a.file',
#     'a.dir/file1',
#     'a.dir/file2',
#     'b.dir/file3')
#
# It can croak if the $jobid is empty. If it does not represent an
# existing (and readable) directory, it returns an empty list (without
# croaking).
# -----------------------------------------------------------------
sub result_list {
    my ($class, $jobid) = @_;
    my $dir = _id2dir ($jobid);
    return () unless -e $dir;

    my @files = ();
    find (
	sub {
	    my $regex = quotemeta ($dir);
	    unless (m{^\.\.?$} || -d) {
		my $file = $File::Find::name;
		$file =~ s{^$regex[/\\]?}{};
		push (@files, $file)
		    unless
		    $file eq STDOUT_FILE or
		    $file eq STDERR_FILE or
		    $file eq CONFIG_FILE;
	    }
	  },
	$dir);
    return @files;
}

#-----------------------------------------------------------------
# Return the content of the given $file from the job given by
# $jobid. The $file is a relative filename; must be one of those
# returned by method result_list().
#
# Return undef if the $file does not exist (or if it does not exist in
# the list returned by result_list().
# -----------------------------------------------------------------
sub result {
    my ($class, $jobid, $file) = @_;
    my @allowed_files = $class->result_list ($jobid);
    my $dir = _id2dir ($jobid);
    my $is_allowed = exists { map {$_ => 1} @allowed_files }->{$file};
    return undef unless $is_allowed;
    return read_file (File::Spec->catfile ($dir, $file));
}

#-----------------------------------------------------------------
# Return the content of the STDOUT from the job given by $jobid. It
# may be an empty string if the job did not produce any STDOUT, or if
# the job does not exist anymore.
# -----------------------------------------------------------------
sub stdout {
    my ($class, $jobid) = @_;
    my $dir = _id2dir ($jobid);
    my $file = File::Spec->catfile ($dir, STDOUT_FILE);
    my $content = "";
    eval {
	$content = read_file ($file);
    };
    return $content;
}

#-----------------------------------------------------------------
# Return the content of the STDERR from the job given by $jobid. It
# may be an empty string if the job did not produce any STDERR, or if
# the job does not exist anymore.
# -----------------------------------------------------------------
sub stderr {
    my ($class, $jobid) = @_;
    my $dir = _id2dir ($jobid);
    my $file = File::Spec->catfile ($dir, STDERR_FILE);
    my $content = "";
    eval {
	$content = read_file ($file);
    };
    return $content;
}

#-----------------------------------------------------------------
# Remove files belonging to the given job, including its directory.
# -----------------------------------------------------------------
sub clean {
    my ($class, $jobid) = @_;
    my $dir = _id2dir ($jobid);
    my $file_count = remove_tree ($dir);  #, {verbose => 1});
    return $file_count;
}

# -----------------------------------------------------------------
# Send a signal to the given job. $signal is a positive integer
# between 1 and 64. Default is 9 which means the KILL signal. Return
# true on success, zero on failure (no such job, no such process). It
# may also croak if the $jobid is invalid or missing, at all, or if
# the $signal is invalid.
# -----------------------------------------------------------------
sub signal {
    my ($class, $jobid, $signal) = @_;
    my $dir = _id2dir ($jobid);
    $signal = 9 unless $signal;    # Note that $signal zero is also changed to 9
    croak "Bad signal: $signal.\n"
	unless $signal =~ m{^[+]?\d+$};
    my ($cfg, $cfgfile) = $class->get_configuration ($dir);
    my $pid = $cfg->param ('job.pid');
    return 0 unless $pid;
    return kill $signal, $pid;
}

#-----------------------------------------------------------------
# Check given $options (a hashref), some may be removed.
# -----------------------------------------------------------------
sub _check_options {
    my $options = shift;

    # TIMEOUT may not be used on some architectures; must be a
    # positive integer
    if (exists $options->{TIMEOUT}) {
	my $timeout = $options->{TIMEOUT};
	if (_is_int ($timeout)) {
	    if ($timeout == 0) {
		delete $options->{TIMEOUT};
	    } elsif ($timeout < 0) {
		delete $options->{TIMEOUT};
		carp "Warning: Option TIMEOUT is negative. Ignored.\n";
	    }
	} else {
	    delete $options->{TIMEOUT};
	    carp "Warning: Option TIMEOUT is not a number (found '$options->{TIMEOUT}'). Ignored.\n";
	}
	if (exists $options->{TIMEOUT}) {
	    my $has_nonblocking = $Config{d_waitpid} eq "define" || $Config{d_wait4} eq "define";
	    unless ($has_nonblocking) {
		delete $options->{TIMEOUT};
		carp "Warning: Option TIMEOUT cannot be used on this system. Ignored.\n";
	    }
	}
    }

    # check for unknown options
    foreach my $key (sort keys %$options) {
	carp "Warning: Unknown option '$key'. Ignored.\n"
	    unless exists $KNOWN_OPTIONS->{$key};
    }

}

sub _is_int {
    my ($str) = @_;
    return unless defined $str;
    return $str =~ /^[+-]?\d+$/ ? 1 : undef;
}

#-----------------------------------------------------------------
# Create a configuration instance and load it from the configuration
# file (if exists) for the given job. Return ($cfg, $cfgfile).
# -----------------------------------------------------------------
sub get_configuration {
    my ($class, $jobid) = @_;
    my $dir = _id2dir ($jobid);
    my $cfgfile = File::Spec->catfile ($dir, CONFIG_FILE);
    my $cfg = Proc::Async::Config->new ($cfgfile);
    return ($cfg, $cfgfile);
}

#-----------------------------------------------------------------
# Create and fill the configuration file. Return the filename and a
# configuration instance.
# -----------------------------------------------------------------
sub _start_config {
    my ($jobid, $args, $options) = @_;

    # create configuration file
    my ($cfg, $cfgfile) = Proc::Async->get_configuration ($jobid);

    # ...and fill it
    $cfg->param ("job.id", $jobid);
    foreach my $arg (@$args) {
	$cfg->param ("job.arg", $arg);
    }
    foreach my $key (sort keys %$options) {
	$cfg->param ("option.$key", $options->{$key});
    }
    $cfg->param ("job.status", STATUS_CREATED);

    $cfg->save();
    return ($cfg, $cfgfile);
}

#-----------------------------------------------------------------
# Create and return a unique ID.
#### (the ID may be influenced by some of the $options).
#-----------------------------------------------------------------
sub _generate_job_id {
    # my $options = shift;  # an optional hashref
    # if ($options and exists $options->{DIR}) {
    # 	return tempdir ( CLEANUP => 0, DIR => $options->{DIR} );
    # } else {
	# return tempdir ( CLEANUP => 0 );
    # }
    return tempdir (CLEANUP => 0, DIR => File::Spec->tmpdir);
}

#-----------------------------------------------------------------
# Return a name of a directory asociated with the given job ID; in
# this implementation, it returns the same value as the job ID; it
# croaks if called without a parameter OR if $jobid points to a
# strange (not expected) place.
#-----------------------------------------------------------------
sub _id2dir {
    my $jobid = shift;
    croak ("Missing job ID.\n")
	unless $jobid;

    # does the $jobid start in the temporary directory?
    my $tmpdir = File::Spec->tmpdir;  # this must be the same as used in _generate_job_id
    croak ("Invalid job ID '$jobid'.\n")
	unless $jobid =~ m{^\Q$tmpdir\E[/\\]};

    return $jobid;
}

1;

__END__
START - start an external program and return its ID
  Input: - (mandatory) the full command-line of the external program
         - ... (wait for it...)
  Return: a (time and location) unique job ID of the external program (not a PID)

STATUS - give me status of a previously started external program
  Input: - (mandatory) job ID (as returned from the START request)
  Return: a (numeric?) code: UNKNOWN, CREATED, RUNNING, COMPLETED,
                             TERMINATED_BY_REQUEST, TERMINATED_BY_ERROR,
                             REMOVED ?

PROGRESS - give me status AND progress report (which may be the full result)
  Input: - (mandatory) job ID (as returned from the START request)
         - where to take progress from (STDERR, STDOUT, FILE, WRAPPER)
         - full progress report or only partial (tail what was not yet asked for)
         - return progress report or a file name with the progress report?
  Return: status (see above)
          progress report

RESULT - the same as progress; which type name should I use?

KILL - kill the external program; wait until it is killed
  Input: - (mandatory) job ID (as returned from the START request)
  Return: status (see above)

CLEAN - remove files from the job
  Input: - (mandatory) job ID (as returned from the START request)
