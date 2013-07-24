SUBDIRS = alac

AM_CPPFLAGS = $(AERIAL_CFLAGS)

lib_LTLIBRARIES = libaerial.la
bin_PROGRAMS = aerial-test

# I'm very very sorry about this, but Vala generates too many warnings by
# default, and I'd rather see errors easier when they occur. If you hate
# this (and you should!) go bug the Vala people.
libaerial_la_CFLAGS = -w
libaerial_la_LIBADD = $(AERIAL_LIBS) alac/libalac.la
libaerial_la_VALAFLAGS = --pkg gio-2.0 --pkg posix --library aerial -H aerial.h

libaerial_la_SOURCES = binary.vala client.vala rtp.vala crypto.vala
libaerial_la_SOURCES += ring-buffer.vala rtsp.vala dmap.vala alac-shim.cpp
libaerial_la_SOURCES += nettle.vapi

# we generate a few extra files, too
aerial.vapi aerial.h : libaerial_la_vala.stamp

aerial_test_CFLAGS = -w
aerial_test_LDADD = libaerial.la
aerial_test_VALAFLAGS = --pkg gio-2.0
aerial_test_SOURCES = main.vala aerial.vapi

MAINTAINERCLEANFILES = aerial.vapi aerial.h