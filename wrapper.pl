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

__END__

Role of the wrapper (monitor) parent:
-------------------------------------

* fork the real external process
* updates its status in the configuration file
