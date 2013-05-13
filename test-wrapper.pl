#!/usr/bin/env perl

use warnings;
use strict;

use lib 'lib';
use Proc::Async;

# create a job ID and a job directory
my $jobid = Proc::Async::_generate_job_id();
my $dir = Proc::Async::_id2dir ($jobid);

# create configuration file
my $options = {};
my $cfgfile = Proc::Async::_start_config ($jobid, \@ARGV, $options);

# exexute the wrapper
#my @wrapper_args = ('./wrapper.pl', $jobid);

use Proc::Daemon;
my $daemon = Proc::Daemon->new(
    work_dir     => '/home/senger/my-perl-modules/Proc-Async',
    child_STDOUT => '/home/senger/my-perl-modules/Proc-Async/stdout.file',
    child_STDERR => '/home/senger/my-perl-modules/Proc-Async/stderr.file',
    pid_file     => '/home/senger/my-perl-modules/Proc-Async/pid.file',
#    exec_command => "./wrapper.pl $jobid",
    );
my $dpid = $daemon->Init();   # $dpid is a PID of the daemon (the one in the pid.file above)
# if ($dpid) {
#     # parent (of a daemon child)
#     print "DAEMON: $dpid\n";
#     print "WAITPID: " . waitpid ($dpid, 0) . "\n";
# } else {

unless ($dpid) {
    # child (a daemon)

    # fork and start an external process
    my $pid = fork();

    if ($pid) {
	# this branch is executed in the parent process;
	# here should go all the funtionality of a wrapper
	print "PID: $pid\n";
	print "waitpid: " . waitpid ($pid, 0) . "\n";
	print "\$?: $?\n";
	if ($? == -1) {
	    print "failed to execute: $!\n";
	}
	elsif ($? & 127) {
	    printf "child died with signal %d, %s coredump\n",
	    ($? & 127),  ($? & 128) ? 'with' : 'without';
	}
	else {
	    printf "child exited with value %d\n", $? >> 8;
	}
	# or: http://docstore.mik.ua/orelly/perl/cookbook/ch16_20.htm
	#     and http://perldoc.perl.org/perlipc.html

    } elsif ($pid == 0) {
	# this branch is executed in the just started child process:
	exec ('t/data/extester', '-stdout', 'this is stdout', '-stderr', 'an error', '-sleep', 10, '-exit', 32) or
	    print STDERR "Couldn't exec: $!";

    } else {
	# this branch is executed only when there is an error in the
	# forking, e.g. the system does not allow to fork any more
	# process
	warn "I couldn't fork: $!\n";
    }

}

#die "Cannot execute '" . join (' ', @wrapper_args) . "': $!\n";
