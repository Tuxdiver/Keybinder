#! /usr/bin/env perl

use strict;
use warnings;

use Data::Dumper;
use Linux::Input;
use List::Util qw(first any all);

use File::Basename qw(basename);

# commands to be performed at keypress
my %commands = (
    'yellow' => ['/usr/bin/hyperion-remote -c yellow'],
    'blue'   => ['/usr/bin/hyperion-remote -c blue'],
    'green'  => ['/usr/bin/hyperion-remote -c green'],
    'red'    => ['/usr/bin/hyperion-remote -c red'],

    'below yellow' => [ '/usr/bin/hyperion-remote --clearall', 'echo 0 >  /sys/class/gpio/gpio4/value' ],
    'below blue'   => [ '/usr/bin/hyperion-remote --clearall', 'echo 1 >  /sys/class/gpio/gpio4/value' ],

    'clear' => ['/usr/bin/hyperion-remote --clearall'],
    'power' => [ 'killall hyperion-v4l2', '/usr/bin/hyperion-remote --clearall' ],
    'start' => [
        '/usr/bin/hyperion-v4l2 --width 720 --height 576 -d /dev/video0 --input 0 --pixel-format RGB32 -s 4 -f 1 -t 0.1 --crop-left 10 --crop-top 3 --crop-right 10 --crop-bottom 5 -v PAL 2>&1 >>/var/log/hyperion_v4l2.log &'
    ],
);

# configration of the input devices and their keys
my @inputs = (
    {
        device   => '/dev/input/event3',
        modifier => [],
        keys     => [
            { key => 172, name => 'home', },
            { key => 142, name => 'power', },
            { key => 165, name => '|<<', },
            { key => 164, name => 'play / pause', },
            { key => 163, name => '>>|', },
            { key => 166, name => 'stop', },
            { key => 272, name => 'left mouse btn', },
            { key => 273, name => 'right mouse btn / i', },
            { key => 115, name => 'vol up', },
            { key => 114, name => 'vol down', },
            { key => 113, name => 'mute', },
        ],
    },
    {
        device   => '/dev/input/event2',
        modifier => [
            { key => 29,  name => 'LEFTCTRL', },
            { key => 42,  name => 'LEFTSHIFT', },
            { key => 56,  name => 'LEFTALT', },
            { key => 125, name => 'LEFTMETA', },
            { key => 69,  name => 'NUMLOCK', },
        ],
        keys => [
            { key => 20, name => 'yellow', modifier => { LEFTCTRL => 1, LEFTSHIFT => 1 }, },
            { key => 50, name => 'blue',   modifier => { LEFTCTRL => 1 }, },
            { key => 23, name => 'green',  modifier => { LEFTCTRL => 1 }, },
            { key => 18, name => 'red',    modifier => { LEFTCTRL => 1 }, },

            { key => 24, name => 'below yellow', modifier => { LEFTCTRL => 1 }, },
            { key => 34, name => 'below blue',   modifier => { LEFTCTRL => 1 }, },
            { key => 20, name => 'below green',  modifier => { LEFTCTRL => 1 }, },
            { key => 50, name => 'below red',    modifier => { LEFTCTRL => 1, LEFTSHIFT => 1 }, },

            { key => 48, name => '<<',     modifier => { LEFTCTRL => 1, LEFTSHIFT => 1 }, },
            { key => 33, name => '>>',     modifier => { LEFTCTRL => 1, LEFTSHIFT => 1 }, },
            { key => 19, name => 'record', modifier => { LEFTCTRL => 1 }, },
            { key => 14, name => 'back', },

            { key => 103, name => 'up', },
            { key => 108, name => 'down', },
            { key => 105, name => 'left', },
            { key => 106, name => 'right', },
            { key => 28,  name => 'ok', },
            { key => 104, name => 'channel up', },
            { key => 109, name => 'channel down', },
            { key => 28,  name => 'start', modifier => { LEFTMETA => 1, LEFTALT => 1 }, },

            { key => 79, name => '1', },
            { key => 80, name => '2', },
            { key => 81, name => '3', },
            { key => 75, name => '4', },
            { key => 76, name => '5', },
            { key => 77, name => '6', },
            { key => 71, name => '7', },
            { key => 72, name => '8', },
            { key => 73, name => '9', },
            { key => 55, name => '*', },
            { key => 82, name => '0', },

            { key => 62, name => 'close', modifier => { LEFTALT => 1 }, },
            { key => 1,  name => 'clear', },
        ],
    }
);

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
                    print "code=$code, value=$event->{value}\n";
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
                            print "Found: $key->{name}\n";

                            # execute commands defined for this key
                            for my $command ( @{ $commands{ $key->{name} } } ) {
                                print "Exec: $command\n";
                                system("$command");
                            }
                        }
                    }
                }
            }
        }
    }
}
