SUBDIRS = alac

AM_CPPFLAGS = $(GIO_CFLAGS) $(Nettle_CFLAGS)

lib_LTLIBRARIES = libaerial.la
vapi_DATA = aerial.vapi
pkginclude_HEADERS = aerial.h
bin_PROGRAMS = aerial-test

# introspection only!
if HAVE_INTROSPECTION
gir_DATA = Aerial-1.0.gir
typelib_DATA = Aerial-1.0.typelib
libaerial_dlname = \
	`$(SED) -nE "s/^dlname='([A-Za-z0-9.+-]+)'/\1/p" libaerial.la`
Aerial-1.0.typelib : Aerial-1.0.gir libaerial.la
	@INTROSPECTION_COMPILER@ -l $(libaerial_dlname) -o $@ $<
MOSTLYCLEANFILES = Aerial-1.0.typelib
endif

# I'm very very sorry about this, but Vala generates too many warnings by
# default, and I'd rather see errors easier when they occur. If you hate
# this (and you should!) go bug the Vala people.
libaerial_la_CFLAGS = -w
libaerial_la_CXXFLAGS = $(libaerial_la_CFLAGS)
libaerial_la_LIBADD = $(GIO_LIBS) $(Nettle_LIBS) alac/libalac.la
libaerial_la_VALAFLAGS = --pkg gio-2.0 --pkg posix --library aerial
libaerial_la_VALAFLAGS += -H aerial.h --gir Aerial-1.0.gir
libaerial_la_LDFLAGS = -version_info $(AERIAL_LT_VERSION)

libaerial_la_SOURCES = binary.vala client.vala rtp.vala crypto.vala
libaerial_la_SOURCES += ring-buffer.vala rtsp.vala dmap.vala alac-shim.cpp
libaerial_la_SOURCES += nettle.vapi

# we generate a few extra files, too
MAINTAINERCLEANFILES = aerial.vapi aerial.h Aerial.gir
aerial.vapi aerial.h Aerial.gir : libaerial_la_vala.stamp

aerial_test_CFLAGS = -w
aerial_test_LDADD = libaerial.la
nodist_EXTRA_aerial_test_SOURCES = dummy1.cxx # force c++ linker
aerial_test_VALAFLAGS = --pkg gio-2.0
aerial_test_SOURCES = test.vala aerial.vapi

# gstreamer only!
if ENABLE_GSTREAMER
gstplugin_LTLIBRARIES = libgstaerial.la

libgstaerial_la_CFLAGS = -w $(GStreamer_CFLAGS)
libgstaerial_la_LIBADD = $(GStreamer_LIBS) libaerial.la
nodist_EXTRA_libgstaerial_la_SOURCES = dummy2.cxx # force c++ linker
libgstaerial_la_VALAFLAGS = --pkg gio-2.0 --pkg gstreamer-1.0
libgstaerial_la_VALAFLAGS += --pkg gstreamer-audio-1.0
libgstaerial_la_LDFLAGS = -module -shared -avoid-version
libgstaerial_la_LDFLAGS += -export-symbols-regex [_]*\(gst_\|Gst\|GST_\).*
libgstaerial_la_SOURCES = gstreamer.vala gst-shim.c aerial.vapi
endif