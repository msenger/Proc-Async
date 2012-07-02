#!perl -T

use Test::More qw(no_plan);
#use Test::More tests => 7;

# -----------------------------------------------------------------
# Tests start here...
# -----------------------------------------------------------------
ok(1);
use Proc::Async;
diag( "Configuration" );

my $args = [ 'echo', 'no comma', 'with comma,yes,no', 'with "quoted"', 'comma with "quote,s' ];
my $options = { AN_OPTION   => 'a value',
		ANOTHER_ONE => 'b value' };

my $jobid = Proc::Async::_generate_job_id();
my $dir = Proc::Async::_id2dir ($jobid);

my $cfgfile = Proc::Async::_start_config ($jobid, $dir, $args, $options);
ok (defined $cfgfile, "Config file not created");
diag ($cfgfile);

my $cfg = Config::Simple->new ($cfgfile);
is ($cfg->param ("job.id"), $jobid, "Job ID does not match");
for (my $i = 0; $i < @$args; $i++) {
    diag ("$i: " . $cfg->param ("job.args$i"));
    is ($cfg->param ("job.args$i"), $args->[$i], "Argument does not match");
}

    # print "READ: " . $cfg->param ("job.id") . "\n";
    # print "READ: " . join ("|", $cfg->param ("job.args")) . "\n";


__END__
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
