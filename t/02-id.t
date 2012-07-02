#!perl -T

#use Test::More qw(no_plan);
use Test::More tests => 7;

# -----------------------------------------------------------------
# Tests start here...
# -----------------------------------------------------------------
ok(1);
use Proc::Async;
diag( "Job ID creation" );

# create a non-empty ID
my $jobid = Proc::Async::_generate_job_id();
ok (defined $jobid, "Job ID is empty");

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
