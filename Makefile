SOURCES=main.vala binary.vala client.vala rtp.vala crypto.vala ring-buffer.vala rtsp.vala dmap.vala
TARGET=test
LDFLAGS=`pkg-config --libs gio-2.0 nettle` -L./alac/ -lalac

GSTSOURCES=gstreamer.vala
GSTTARGET=airtunes.so
GSTLDFLAGS=`pkg-config --libs gstreamer-1.0 gstreamer-audio-1.0`

CFLAGS=-w -fPIC -O3 `pkg-config --cflags gio-2.0 nettle gstreamer-1.0`
VALAC_FLAGS=--vapidir=. --pkg gio-2.0 --pkg nettle --pkg posix --pkg gstreamer-1.0 --pkg gstreamer-audio-1.0 #--disable-warnings

VALAC=valac
# we need to use c++ to link!
LD=${CXX}

.PHONY : all clean
.PRECIOUS : ${SOURCES:.vala=.c} ${GSTSOURCES:.vala=.c}

all : ${TARGET} ${GSTTARGET}

ifeq ($(V),)
quiet_DOC := "Use \"$(MAKE) V=1\" to see the verbose compile lines.\n"
quiet = @echo -e $(quiet_DOC)$(eval quiet_DOC:=)"  $1	$@"; $($1)
endif
ifeq ($(V),0)
quiet = @echo "  $1	$@"; $($1)
endif
ifeq ($(V),1)
quiet = $($1)
endif

clean :
	rm -f ${TARGET} ${GSTTARGET}
	rm -f valac.stamp
	rm -f ${SOURCES:.vala=.o}
	rm -f ${GSTSOURCES:.vala=.o}
	rm -f ${SOURCES:.vala=.c}
	rm -f ${GSTSOURCES:.vala=.c}
	rm -f gst-shim.o
	rm -f alac-shim.o
	rm -f libairtunes.h libairtunes.vapi
	make -C alac clean

valac.stamp : ${SOURCES} ${GSTSOURCES} nettle.vapi
	$(call quiet,VALAC) -C ${VALAC_FLAGS} ${SOURCES} ${GSTSOURCES} -H libairtunes.h --vapi=libairtunes.vapi
	@touch $@

alac/libalac.a :
	make -C alac

% : %.o
% : %.c

%.c : %.vala valac.stamp
	@true

%.o : %.c
	$(call quiet,CC) -c ${CFLAGS} $< -o $@

%.o : %.cpp
	$(call quiet,CXX) -c ${CFLAGS} $< -o $@

${TARGET} : alac/libalac.a alac-shim.o ${SOURCES:.vala=.o}
	$(call quiet,LD) $^ -o $@ ${LDFLAGS}

${GSTTARGET} : alac/libalac.a alac-shim.o ${SOURCES:.vala=.o} ${GSTSOURCES:.vala=.o} gst-shim.o
	$(call quiet,LD) -rdynamic -shared $^ -o $@ ${LDFLAGS} ${GSTLDFLAGS}
