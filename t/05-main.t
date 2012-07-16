#!perl -T

use Test::More qw(no_plan);
#use Test::More tests => 7;

#-----------------------------------------------------------------
# Return a fully qualified name of the given file in the test
# directory "t/data" - if such file really exists. With no arguments,
# it returns the path of the test directory itself.
# -----------------------------------------------------------------
use FindBin qw( $Bin );
use File::Spec;
sub test_file {
    my $file = File::Spec->catfile ('t', 'data', @_);
    return $file if -e $file;
    $file = File::Spec->catfile ($Bin, 'data', @_);
    return $file if -e $file;
    return File::Spec->catfile (@_);
}

# -----------------------------------------------------------------
# Tests start here...
# -----------------------------------------------------------------
ok(1);
use Proc::Async;
diag( "Main functions" );

#my $sleeper = test_file ('bad.xml');

__END__
# start and fill a configuration
my $args = [ qw(echo yes no) ];
my $options = { OH => 'yes', BETTER => 'no' };
my $jobid = Proc::Async::_generate_job_id();
my $cfgfile = Proc::Async::_start_config ($jobid, $args, $options);
ok (-e $cfgfile, "Configuration does not exist");

# re-read and check the configuration
my ($cfg, $cfgfile) = Proc::Async->get_configuration ($jobid);
is_deeply ([ $cfg->param ('job.arg') ], $args, "Re-Read args failed");
is ($cfg->param ('job.id'), $jobid, "Re-Read jobid failed");
is ($cfg->param ('job.status'), Proc::Async::STATUS_CREATED, "Re-Read status failed");
foreach my $key (keys %$options) {
    is ($cfg->param ('option.' . $key), $options->{$key}, "Re-Read option '$key' failed");
}

__END__
