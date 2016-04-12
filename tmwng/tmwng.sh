#!/bin/sh

(flock -n 9 || exit 1; /usr/bin/perl $(dirname $(readlink -f $0))/tmwng.pl "$@") 9>/var/lock/tmwng
