Keybinder
=========

Bind IR remote control to shell commands

This script reads /dev/input/eventX on a linux system and starts commands, when a configured 
key was recognized.

The configuration is currently in the script, but will be moved to a config file in the future.

The configuration in the script is working for a HAMA remote control with the USB signature:
  
  Bus 002 Device 005: ID 05a4:9881 Ortek Technology, Inc.

