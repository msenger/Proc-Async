#!perl -T

use Test::More qw(no_plan);
#use Test::More tests => 7;

# -----------------------------------------------------------------
# Tests start here...
# -----------------------------------------------------------------
ok(1);
use Proc::Async;
diag( "My configuration" );

# start and fill a configuration
my $args = [ qw(echo yes no) ];
my $options = { OH => 'yes', BETTER => 'no' };
my $jobid = Proc::Async::_generate_job_id();
my $cfgfile = Proc::Async::_start_config ($jobid, $args, $options);
ok (-e $cfgfile, "Configuration does not exist");

# re-read and check the configuration
my ($cfg, $cfgfile) = Proc::Async->get_configuration ($jobid);

__END__

# create a directory asociated with the given job ID
my $dir = Proc::Async::_id2dir ($jobid);
ok (-e $dir, "Directory '$dir' does not exist");
ok (-d $dir, "'$dir' is not a directory");
ok (-w $dir, "'$dir' is not writable");

# ...and remove that directory
Proc::Async->clean ($jobid);
ok (!-e $dir, "Directory '$dir' should not exist");

# job ID is the same as job directory
is ($jobid, $dir, "Job ID is not equal to the job directory");

__END__
