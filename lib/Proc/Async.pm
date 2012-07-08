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
use Proc::Async::Config;

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

#-----------------------------------------------------------------
# Start an external program and return its ID.
#    starts ($args, [$options])
#    starts (@args, [$options])
#  $args    ... an arrayref with the full command-line (including the
#               external program name)
#  @args    ... an array with the full command-line (including the
#               external program name)
#  $options ... a hashref with additional options:
#               DIR => where to create JOB directories
#               NOSTART => 1 no external process will be started
#-----------------------------------------------------------------
sub start {
    my $class = shift;
    croak ("START: Undefined external process.")
	unless @_ > 0;
    my ($args, $options) = _process_start_args (@_);

    # create a job ID and a job directory
    my $jobid = _generate_job_id();
    my $dir = _id2dir ($jobid);

    # create configuration file
    my $cfgfile = _start_config ($jobid, $args, $options);

    # print "READ: " . $cfg->param ("job.id") . "\n";

    print `cat $cfgfile`;
    return $jobid;
}

# -----------------------------------------------------------------
# Return status of the given job (given by $jobid).
# -----------------------------------------------------------------
sub status {
    my ($class, $jobid) = @_;
    _check_jobid ($jobid);   # may croak
    my $dir = _id2dir ($jobid);
    my ($cfg, $cfgfile) = $class->get_configuration ($dir);

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
# Check existence of the given $jobid; croak if it does not exist.
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
# Create and fill the configuration file. Return the filename.
#-----------------------------------------------------------------
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
    return $cfgfile;
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

# create and return a uniq ID
sub _generate_job_id {
    use File::Temp qw/ tempdir /;
    my $dir = tempdir ( CLEANUP => 0 );
    return $dir;
}

# return a name of a directory asociated with the given job ID
# in this implementation of _generate_job_id, it does nothing)
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
