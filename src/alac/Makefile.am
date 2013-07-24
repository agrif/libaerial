noinst_LTLIBRARIES = libalac.la

# I have no intention of editing applecode to not emit warnings
# besides, it's mostly multi-character constants
libalac_la_CFLAGS = -w
libalac_la_CXXFLAGS = $(libalac_la_CFLAGS)

libalac_la_SOURCES = EndianPortable.h aglib.h ALACAudioTypes.h ALACBitUtilities.h
libalac_la_SOURCES += ALACDecoder.h ALACEncoder.h dplib.h matrixlib.h
libalac_la_SOURCES += EndianPortable.c ALACBitUtilities.c ALACDecoder.cpp
libalac_la_SOURCES += ALACEncoder.cpp ag_dec.c ag_enc.c dp_dec.c dp_enc.c
libalac_la_SOURCES += matrix_dec.c matrix_enc.c
