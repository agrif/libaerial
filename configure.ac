dnl =============================
dnl Version Rules and AM/AC setup
dnl =============================

AC_PREREQ([2.65])

dnl human-friendly version number, major.minor.patch scheme
m4_define(aerial_major_version, 0)
m4_define(aerial_minor_version, 0)
m4_define(aerial_patch_version, 0)

dnl libtool library version, current:revision:age scheme
m4_define(aerial_lt_current_version, 0)
m4_define(aerial_lt_revision_version, 0)
m4_define(aerial_lt_age_version, 0)

dnl Handy-Dandy Version Management Guide
dnl ------------------------------------
dnl
dnl Bump patch for any release that doesn't change the interface, bump
dnl minor for any change that does, and bump major for a major
dnl restructuring. Major-0 is special: it's basically beta-phase, and
dnl the last Major-0 release will likely be similar to the first Major-1
dnl release.
dnl
dnl Bump revision for any release, then if the external interface has
dnl changed, bump current and set revision to 0. If all new interfaces
dnl are backwards-compatible, bump age, and if not, set age to 0.

m4_define(aerial_version, [aerial_major_version.aerial_minor_version.aerial_patch_version])
m4_define(aerial_lt_version, [aerial_lt_current_version:aerial_lt_revision_version:aerial_lt_age_version])

AC_INIT([libaerial], [aerial_version], [aargri@gmail.com], [libaerial],
	[http://github.com/agrif/libaerial])

AC_SUBST(AERIAL_LT_VERSION, aerial_lt_version)

AC_CONFIG_SRCDIR([src/client.vala])
AC_CONFIG_MACRO_DIR([m4])

AM_INIT_AUTOMAKE([1.11 foreign dist-bzip2 no-dist-gzip])
AM_MAINTAINER_MODE([enable])

AM_SILENT_RULES([yes])

dnl =====================
dnl Basic Compiler Checks
dnl =====================

LT_INIT
AC_PROG_CC
AC_PROG_CXX
AC_PROG_INSTALL

VALA_ADD_CHECKFILE([src/aerial_test_vala.stamp])
VALA_ADD_CHECKFILE([src/libgstaerial_la_vala.stamp])
VALA_ADD_CHECKFILE([src/libaerial_la_vala.stamp])
VALA_CHECK([])

GOBJECT_INTROSPECTION_CHECK([0.9.0])

dnl =================
dnl pkg-config Checks
dnl =================

PKG_PROG_PKG_CONFIG

GIO_REQUIRED=2.24.1
NETTLE_REQUIRED=2.4
GST_REQUIRED=1.0.0

PKG_CHECK_MODULES(GIO, [
	gio-2.0 >= $GIO_REQUIRED
])

PKG_CHECK_MODULES(NETTLE, [
	nettle >= $NETTLE_REQUIRED
])

PKG_CHECK_MODULES(GSTREAMER, [
	gstreamer-1.0 >= $GST_REQUIRED
	gstreamer-audio-1.0 >= $GST_REQUIRED
])

dnl ===========
dnl Other Stuff
dnl ===========

AC_DEFINE(G_LOG_DOMAIN, "libaerial", [Log domain])
GNOME_COMPILE_WARNINGS([maximum])
GNOME_MAINTAINER_MODE_DEFINES

dnl vala vapi directory
vapidir="\$(datadir)/vala/vapi"
AC_SUBST(vapidir)

dnl gir/typelib directory
girdir="\$(INTROSPECTION_GIRDIR)"
typelibdir="\$(INTROSPECTION_TYPELIBDIR)"
AC_SUBST(girdir)
AC_SUBST(typelibdir)

dnl pkgconfig directory
pkgconfigdir="\$(libdir)/pkgconfig"
AC_SUBST(pkgconfigdir)

dnl set up gstreamer plugin directory
gstplugindir="\$(libdir)/gstreamer-1.0"
AC_SUBST(gstplugindir)

dnl =================
dnl Substitution List
dnl =================

AC_CONFIG_FILES([
	aerial.pc
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
	Enable Introspection : $enable_introspection
	Use Vala Compiler    : $enable_vala"
AS_IF([test x$enable_vala == xyes],
	[echo "	Vala Compiler        : $VALAC"])

echo "	Installation prefix  : $prefix
"