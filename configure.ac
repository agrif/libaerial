dnl =============================
dnl Version Rules and AM/AC setup
dnl =============================

AC_PREREQ([2.65])

m4_define(aerial_major_version, 0)
m4_define(aerial_minor_version, 0)
m4_define(aerial_patch_version, 0)

m4_define(aerial_version, [aerial_major_version.aerial_minor_version.aerial_patch_version])

AC_INIT([libaerial], [aerial_version], [aargri@gmail.com])

AC_CONFIG_SRCDIR([src/client.vala])
AC_CONFIG_MACRO_DIR([m4])

AC_DEFINE(AERIAL_VERSION, "aerial_version", [Aerial version])
AC_SUBST(AERIAL_VERSION, aerial_version)

AM_INIT_AUTOMAKE([1.11 foreign dist-bzip2 no-dist-gzip])
AM_MAINTAINER_MODE([enable])

AM_SILENT_RULES([yes])

dnl =====================
dnl Basic Compiler Checks
dnl =====================

LT_INIT
AC_PROG_CC
AC_PROG_CXX
AM_PROG_VALAC
AC_PROG_INSTALL

dnl =================
dnl pkg-config Checks
dnl =================

PKG_PROG_PKG_CONFIG

GIO_REQUIRED=2.24.1
NETTLE_REQUIRED=2.4

PKG_CHECK_MODULES(GIO, [
	gio-2.0 >= $GIO_REQUIRED
])

PKG_CHECK_MODULES(NETTLE, [
	nettle >= $NETTLE_REQUIRED
])

dnl ===========
dnl Other Stuff
dnl ===========

AC_DEFINE(G_LOG_DOMAIN, "libaerial", [Log domain])
GNOME_COMPILE_WARNINGS([maximum])
GNOME_MAINTAINER_MODE_DEFINES

dnl =================
dnl Substitution List
dnl =================

AC_CONFIG_FILES([
	Makefile
	src/Makefile
	src/alac/Makefile
])

AC_OUTPUT

dnl =======
dnl Summary
dnl =======

echo "

Configuration:

	Source code location : $srcdir
	C Compiler           : $CC
	C++ Compiler         : $CXX
	Vala Compiler        : $VALAC
	Installation prefix  : $prefix
"