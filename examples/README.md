Examples
========

This directory contains example programs using libaerial, in a variety
of languages. Some of these will be compiled with libaerial, while
others are interpreted and depend on GObject Introspection.

If you compiled libaerial with GI support, but have not yet installed
it, some of these examples will fail to run unless you setup your
environment like so:

~~~~
export GI_TYPELIB_PATH=$base/src/
export LD_LIBRARY_PATH=$base/src/.libs/
~~~~

On some platforms, some variable other than `LD_LIBRARY_PATH` is used
to change the dynamic library search path. On OSX, it's
`DYLD_LIBRARY_PATH`.

playraw
-------

This program accepts a 16-bit signed integer, 44100 Hz, stereo PCM
stream on standard input and plays it to the host listed as the first
argument. If you have [ffmpeg](http://ffmpeg.org/) installed, you can
play a file with:

~~~~
ffmpeg -i $INPUTFILE -f s16le -acodec pcm_s16le - | python3 playraw.py $HOST
~~~~
