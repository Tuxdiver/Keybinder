#! /usr/bin/env perl

use strict;
use warnings;

use YAML;
use Data::Dumper;
use Linux::Input;
use List::Util qw(first any all);
use Getopt::Long;
use Pod::Usage;

my $inputs_config_file   = 'inputs.yaml';
my $commands_config_file = 'commands.yaml';
my $verbose              = 0;
my $help                 = 0;

GetOptions(
    "inputs_file|i=s"   => \$inputs_config_file,
    "commands_file|c=s" => \$commands_config_file,
    "verbose|v"         => \$verbose,
    "help|h"            => \$help,
) or pod2usage(2);

pod2usage(-verbose => 2, -exitval=>1) if $help;

# Load config from YAML-Files
my @inputs;
eval {
    @inputs   = @{ YAML::LoadFile($inputs_config_file) };
};
if ($!) {
    print STDERR "Can't open $inputs_config_file: $!\n";
    exit 2;
}


my %commands;
eval {
    %commands = %{ YAML::LoadFile($commands_config_file) };
};
if ($!) {
    print STDERR "Can't open $commands_config_file: $!\n";
    exit 2;
}


# open all inputs and store information in the inputs structure
my $selector = IO::Select->new();
foreach my $input (@inputs) {

    # create input device
    my $device = Linux::Input->new( $input->{device} );

    # add it to the selector
    $selector->add( $device->fh );

    # store information in structure
    $input->{dev} = $device;

    # create reverse hash for faster set/get of modifier values
    $input->{modifier_by_name} = { map { $_->{name} => { key => $_->{key}, value => 0 } } @{ $input->{modifier} } };
}
print "setup complete, start mainloop\n" if $verbose;

# endless loop
# wait for event
while ( my @fh = $selector->can_read ) {

    # loop over all filehandles and poll events
    foreach my $fh (@fh) {

        # serach the matching input device
        my $input = first { $_->{dev}->fh() == $fh } @inputs;

        # poll event from input
        my @events = $input->{dev}->poll();

        foreach my $event (@events) {
            if ( $event->{type} == 1 ) {
                my $code = $event->{code};

                # look for modifiers in the config
                my @modifiers = grep { $_->{key} == $code } @{ $input->{modifier} };

                # look for key in config
                my @keys = grep { $_->{key} == $code } @{ $input->{keys} };

                # no matching key found -> print the code and event value
                if ( !@keys && !@modifiers ) {
                    print "code=$code, value=$event->{value}\n" if $verbose;
                }

                # for all modifiers: set the value in the modifier structure
                foreach my $modifier (@modifiers) {
                    $input->{modifier_by_name}->{ $modifier->{name} }->{value} = $event->{value};
                }

                # there may be more than one key with this code, so loop over them
                foreach my $key (@keys) {

                    # key press?
                    if ( $event->{value} == 1 ) {

                        # check the modifier of the key. Only if all match, the key is processed
                        if ( all { $input->{modifier_by_name}->{$_}->{value} == ( $key->{modifier}->{$_} // 0 ) } keys %{ $input->{modifier_by_name} } ) {
                            print "Found: $key->{name}\n" if $verbose;

                            # execute commands defined for this key
                            for my $command ( @{ $commands{ $key->{name} } } ) {
                                print "Exec: $command\n" if $verbose;
                                system("$command");
                            }
                        }
                    }
                }
            }
        }
    }
}

__END__

=head1 NAME

keybinder.pl

=head1 SYNOPSIS

 keybinder.pl [--inputs_file <file>] [--commands_file <file>]

 Options:
   -h        help
   -v        verbose
   -i <file> inputs file
   -c <file> commands file

=head1 OPTIONS

=over 8

=item B<--inputs_file | -i>
YAML file with definition of inputs. Default: inputs.yaml

=item B<--commands_file | -c>
YAML file with definition of commands. Default: commands.yaml

=item B<--help | -h>
Print this help message and exits.

=item B<--verbose | -v>
Print verbose messages.

=back

=head1 DESCRIPTION

B<keybinder.pl> reads a linux input device, recognizes the pressed keys with optional modifiers and
executes programms when a configured key is pressed.


=head1 AUTHOR

Dirk Melchers (dirk@tuxdiver.de)

=cut
