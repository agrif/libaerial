# libalac make

.PHONY : all clean

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

AR=ar

CFLAGS = -O3 -c -fPIC -Wno-multichar

SRCDIR=.

HEADERS = \
$(SRCDIR)/EndianPortable.h \
$(SRCDIR)/aglib.h \
$(SRCDIR)/ALACAudioTypes.h \
$(SRCDIR)/ALACBitUtilities.h\
$(SRCDIR)/ALACDecoder.h \
$(SRCDIR)/ALACEncoder.h \
$(SRCDIR)/dplib.h \
$(SRCDIR)/matrixlib.h

SOURCES = \
$(SRCDIR)/EndianPortable.c \
$(SRCDIR)/ALACBitUtilities.c \
$(SRCDIR)/ALACDecoder.cpp \
$(SRCDIR)/ALACEncoder.cpp \
$(SRCDIR)/ag_dec.c \
$(SRCDIR)/ag_enc.c \
$(SRCDIR)/dp_dec.c \
$(SRCDIR)/dp_enc.c \
$(SRCDIR)/matrix_dec.c \
$(SRCDIR)/matrix_enc.c

OBJS = \
EndianPortable.o \
ALACBitUtilities.o \
ALACDecoder.o \
ALACEncoder.o \
ag_dec.o \
ag_enc.o \
dp_dec.o \
dp_enc.o \
matrix_dec.o \
matrix_enc.o

all : libalac.a

libalac.a:	$(OBJS)
	$(call quiet,AR) rcs libalac.a $(OBJS)

%.o : %.c
	$(call quiet,CC) -c ${CFLAGS} $< -o $@

%.o : %.cpp
	$(call quiet,CXX) -c ${CFLAGS} $< -o $@

clean:
	rm -f $(OBJS) libalac.a
