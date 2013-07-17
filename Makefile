SOURCES=main.vala keys.vala client.vala rtp.vala crypto.vala bitwriter.vala
TARGET=test
LDFLAGS=`pkg-config --libs gio-2.0 nettle`

GSTSOURCES=gstreamer.vala
GSTTARGET=airtunes.so
GSTLDFLAGS=`pkg-config --libs gstreamer-1.0`

CFLAGS=`pkg-config --cflags gio-2.0 nettle gstreamer-1.0`
VALAC_FLAGS=--vapidir=. --pkg gio-2.0 --pkg nettle --pkg posix --pkg gstreamer-1.0 --pkg gstreamer-audio-1.0

.PHONY : all clean

all : ${TARGET} ${GSTTARGET}

clean :
	rm -f ${TARGET} ${GSTTARGET}
	rm -f ${SOURCES:=.o}
	rm -f ${GSTSOURCES:=.o}

%.vala.o : ${SOURCES} ${GSTSOURCES}
	valac -c ${VALAC_FLAGS} $<

%.c.o : %.c
	${CC} ${CFLAGS} -c $< -o $@

${TARGET} : ${SOURCES:=.o}
	gcc ${SOURCES:=.o} -o ${TARGET}

${GSTTARGET} : ${SOURCES:=.o} ${GSTSOURCES:=.o}
	echo ${SOURCES:=.o} ${GSTSOURCES:=.o}