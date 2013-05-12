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
my @wrapper_args = ('./wrapper.pl', $jobid);
exec @wrapper_args;
#die "Cannot execute '" . join (' ', @wrapper_args) . "': $!\n";
