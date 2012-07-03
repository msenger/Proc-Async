#-----------------------------------------------------------------
# Proc::Async::Config
# Author: Martin Senger <martin.senger@gmail.com>
# For copyright and disclaimer se below.
#
# ABSTRACT: Configuration helper
# PODNAME: Proc::Async::Config
#-----------------------------------------------------------------

use warnings;
use strict;
package Proc::Async::Config;

use Carp;

# VERSION

#-----------------------------------------------------------------
# Constructor. It reads a given configuration file (but does not
# complain if the file does not exist yet).
#
# Arguments:
#   config-file-name
#   name/value pairs (at the moment, not used)
# -----------------------------------------------------------------
sub new {
    my ($class, @args) = @_;

    # create an object
    my $self = bless {}, ref ($class) || $class;

    # a config file name is mandatory
    croak ("Missing config file name in the Config constructor.\n")
	unless @args > 0;
    $self->{cfgfile} = shift @args;

    # ...and the rest are optional name/value pairs
    my (%args) = @args;
    foreach my $key (keys %args) {
        $self->{$key} = $args {$key};
    }
    $self->{data} = {};  # storage for the configuration properties

    # load the configuration (if exists)
    $self->load ($self->{cfgfile})
	if -e $self->{cfgfile};

    # done
    return $self;
}

#-----------------------------------------------------------------
#
#-----------------------------------------------------------------
sub load {
    my ($self, $cfgfile) = @_;
}

#-----------------------------------------------------------------
# Return the value of the given configuration property, or undef if
# the property does not exist. Depending on the context, it returns
# the value as a scalar (and if there are more values for the given
# property then it returns the first one only), or as an array.
#
# Set the given property first if there is a second argument with the
# property value.
#
# Return a sorted list of all property names if no argument given.
# -----------------------------------------------------------------
sub param {
    my ($self, $name, $value) = @_;
    unless (defined $name) {
	return sort keys %{ $self->{data} };
    }
    if (defined $value) {
	$self->{data}->{$name} = []
	    unless exists $self->{data}->{$name};
	push (@{ $self->{data}->{$name} }, $value);
    } else {
	return undef
	    unless exists $self->{data}->{$name};
    }
    return unless defined wantarray; # don't bother doing more
    return wantarray ? @{ $self->{data}->{$name} } : $self->{data}->{$name}->[0];
}

#-----------------------------------------------------------------
# Create a configuration file (overwrite if exists). The name is
# either given or the one given in the constructor.
# -----------------------------------------------------------------
sub save {
    my ($self, $cfgfile) = @_;
    $cfgfile = $self->{cfgfile} unless defined $cfgfile;
    open (my $cfg, '>', $cfgfile)
	or croak ("Cannot create configuration file '$cfgfile': $!\n");
    foreach my $key (sort keys %{ $self->{data} }) {
	my $values = $self->{data}->{$key};
	foreach my $value (@$values) {
	    print $cfg "$key = $value\n";
	}
    }
    close $cfg;
}

1;
