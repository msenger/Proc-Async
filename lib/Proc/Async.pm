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
use File::Temp qw/ tempdir /;
use File::Spec;
use Proc::Async::Config;
use Proc::Daemon;
use Config;

# VERSION

use constant STDOUT_FILE => 'proc_async_stdout';
use constant STDERR_FILE => 'proc_async_stderr';
use constant PID_FILE    => 'proc_async_pid';
use constant CONFIG_FILE => 'proc_async_status.cfg';

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
    DIR     => 1,
    # NOSTART => 1,
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
#               DIR => a directory where to create JOB directories
#               NOSTART => 1 no external process will be started
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
	$cfg->param ("job.status", STATUS_RUNNING);
	$cfg->save();

	# wait for the child process to finish
	# TBD: if TIMEOUT then use alasrm and non-blocking waitpid
	my $reaped_pid = waitpid ($pid, 0);
	my $reaped_status = $?;

	if ($reaped_status == -1) {
	    update_status ($cfg,
			   STATUS_UNKNOWN,
			   "No such child process"); # can happen?

	} elsif ($reaped_status & 127) {
	    update_status ($cfg,
			   STATUS_TERM_BY_REQ,
			   "Terminated by signal " . ($reaped_status & 127),
			   (($reaped_status & 128) ? "With" : "Without") . " coredump");

	} else {
	    my $exit_code = $reaped_status >> 8;
	    if ($exit_code == 0) {
		update_status ($cfg,
			       STATUS_COMPLETED,
			       "Exit code: $exit_code");
	    } else {
		update_status ($cfg,
			       STATUS_TERM_BY_ERR,
			       "Exit code: $exit_code");
	    }
	}
	$cfg->save();

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

# pretty print of the list of arguments (given as an arrayref)
sub _join_args {
    my $args = shift;
    return join (" ", map {"'$_'"} @$args);
}

# update status and its details (just in memory - in the given $cfg)
sub update_status {
    my ($cfg, $status, @details) = @_;

    # remove the existing status and its details

    # put updated values
    $cfg->param ("job.status", $status);
    foreach my $detail (@details) {
	$cfg->param ("job.status.detail", $detail);
    }
}

# -----------------------------------------------------------------
# Return status of the given job (given by $jobid).
# -----------------------------------------------------------------
sub status {
    my ($class, $jobid) = @_;
    _check_jobid ($jobid);   # may croak
    my $dir = _id2dir ($jobid);
    my ($cfg, $cfgfile) = $class->get_configuration ($dir);
    my $status = $cfg->param ('job.status');
    return ($status or STATUS_UNKNOWN);
}

#-----------------------------------------------------------------
# Remove files belonging to the given job, including its directory.
# -----------------------------------------------------------------
sub clean {
    my ($class, $jobid) = @_;
    _check_jobid ($jobid);   # may croak
    my $dir = _id2dir ($jobid);
    unlink (STDOUT_FILE, STDERR_FILE, PID_FILE, CONFIG_FILE);
    rmdir $dir
	or croak "Cannot rmdir '$dir': $!";
}

#-----------------------------------------------------------------
# Check the presence of a $jobid; croak if it is missing.
# -----------------------------------------------------------------
sub _check_jobid {
    my $jobid = shift;
    croak ("Undefined Job ID ($jobid).\n")
	unless $jobid;
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
    my ($self, $str) = @_;
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
# Return the given value unchanged if it does not contain any
# comma. Otherwise, escape all double-quotes and return double-quoted
# $value.
# -----------------------------------------------------------------
sub _cfg_escape {
    my $value = shift;
    return $value unless $value =~ m{\,};
    $value =~ s{"}{\\"}g;
    return "\"$value\"";
}

#-----------------------------------------------------------------
# Create and return a unique ID
# (the ID may be influenced by some of the $options).
#-----------------------------------------------------------------
sub _generate_job_id {
    my $options = shift;  # an optional hashref
    if ($options and exists $options->{DIR}) {
	return tempdir ( CLEANUP => 0, DIR => $options->{DIR} );
    } else {
	return tempdir ( CLEANUP => 0 );
    }
}

# return a name of a directory asociated with the given job ID;
# in this implementation, it returns the same value as the job ID
sub _id2dir {
    return shift;
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
