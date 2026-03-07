#!/bin/sh
# sst-common.sh — Sunstorm distribution common variables
# Source this from all build/packaging scripts.

# Distribution identity
SST_NAME="sunstorm"
SST_PREFIX="SST"
SST_VERSION="1.0"

# Install prefix on Solaris target
SST_BASEDIR="/opt/sst"

# Target triplet
SST_TARGET="sparc-sun-solaris2.7"
SST_ARCH="sparc"
SST_OS="sunos5.7"

# Package filename convention:
#   <SSTcode>-<version>-<pkgrev>.sst-sunos5.7-sparc.pkg.Z
# Example: SSTgcc-4.9.4-1.sst-sunos5.7-sparc.pkg.Z
sst_pkgfile() {
    _code="$1"    # e.g. SSTgcc
    _ver="$2"     # version string
    _rev="$3"     # e.g. 1
    echo "${_code}-${_ver}-${_rev}.sst-${SST_OS}-${SST_ARCH}.pkg.Z"
}

# Standard directory layout under $SST_BASEDIR
SST_BINDIR="${SST_BASEDIR}/bin"
SST_LIBDIR="${SST_BASEDIR}/lib"
SST_INCLUDEDIR="${SST_BASEDIR}/include"
SST_MANDIR="${SST_BASEDIR}/share/man"
SST_INFODIR="${SST_BASEDIR}/share/info"
SST_DOCDIR="${SST_BASEDIR}/share/doc"

# Versioned compiler prefixes
SST_GCC="${SST_BASEDIR}/gcc"

# Packaging metadata
SST_VENDOR="Sunstorm Project"
SST_EMAIL="julian@sunstorm"
SST_CATEGORY="application"
SST_CLASSES="none"
