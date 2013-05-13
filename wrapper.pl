#!/usr/bin/env perl
#
# Usage: ./wrapper.pl <jobid>
#
# --------------------------------------------
use warnings;
use strict;

use lib 'lib';
use Data::Dumper;
use Proc::Async;

# find and read the configuration of the process that will be wrapped
# (i.e. executed and monitored)
my $jobid = shift;
die "Missing argument.\nUsage: $0 <jobid>\n"
    unless $jobid;
my $dir = Proc::Async::_id2dir ($jobid);
my ($cfg, $cfgfile) = Proc::Async->get_configuration ($dir);

print "DIR: $dir, CFGFILE: $cfgfile\n";

# fork and start an external process
my $pid = fork();

if ($pid) {
    # this branch is executed in the parent process
    waitpid ($pid, 0);


} elsif ($pid == 0) {
    # this branch is executed in the just started child process:
#    exec ('t/data/extester', '-stdout', 'this is stdout', '-stderr', 'an error') or
    exec ('t/data/extester') or
	print STDERR "Couldn't exec: $!";

} else {
    # this branch is executed only when there is an error in the
    # forking, e.g. the system does not allow to fork any more
    # process
    warn "I couldn't fork: $!\n";
}


__END__

Role of the wrapper (monitor) parent:
-------------------------------------

* fork the real external process
* updates its status in the configuration file
