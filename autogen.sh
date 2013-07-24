#!/bin/bash
# Run this to generate the autotools stuff
# originally from libpeas 1.0.0

srcdir=`dirname $0`
test -z "$srcdir" && srcdir=.

PKG_NAME="libaerial"

((test -f $srcdir/configure.ac \
	&& test -f $srcdir/README.md \
	&& test -d $srcdir/src) || (
	echo "**Error**: Directory \`$srcdir' does not look like the"
	echo "top-level $PKG_NAME directory"
	exit 1
	)) && (which gnome-autogen.sh || (
		echo "You need to install gnome-common from GNOME Git (or from"
		echo "your OS vendor's package manager)."
		exit 1
		)) && . gnome-autogen.sh
