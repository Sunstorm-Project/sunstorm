#!/bin/sh
# split-staging.sh — Split the monolithic GCC cross-build staging into
# individual Sunstorm SVR4 packages.
#
# This script runs inside the cross-build Docker container after the
# Canadian-cross build completes. It takes the staging directory
# (/opt/staging) and splits it into per-package root trees, then
# generates SVR4 package metadata for each.
#
# Usage: ./split-staging.sh [staging_dir] [output_dir]

set -e

STAGING="${1:-/opt/staging}"
OUTPUT="${2:-/opt/cross-build/output/packages}"
SCRIPTDIR="$(cd "$(dirname "$0")" && pwd)"

. "${SCRIPTDIR}/lib/sst-common.sh"

PREFIX="/opt/sunstorm"
GCC49="${PREFIX}/gcc49"

echo "============================================"
echo "  Sunstorm Package Splitter"
echo "  Staging: ${STAGING}"
echo "  Output:  ${OUTPUT}"
echo "============================================"
echo ""

# Verify staging exists
if [ ! -d "${STAGING}/usr/tgcware" ]; then
    echo "ERROR: Staging directory ${STAGING}/usr/tgcware not found"
    exit 1
fi

# Source layout in staging (built for /usr/tgcware):
#   usr/tgcware/gcc49/bin/         — compiler drivers
#   usr/tgcware/lib/gcc/...4.9.4/  — cc1, cc1plus, f951, libs
#   usr/tgcware/libexec/gcc/...    — compiler backends
#   usr/tgcware/lib/libgcc_s.so*   — libgcc runtime
#   usr/tgcware/lib/libstdc++.*    — libstdc++ runtime + static
#   usr/tgcware/lib/libgomp.*      — OpenMP runtime
#   usr/tgcware/include/c++/4.9.4/ — C++ headers
#   usr/tgcware/bin/g*             — binutils (g-prefixed)
#
# We remap /usr/tgcware -> /opt/sunstorm in the package roots.

SRC="${STAGING}/usr/tgcware"

# Helper: copy files from staging to package root, remapping prefix
pkg_copy() {
    _pkgname="$1"
    shift
    _root="${OUTPUT}/${_pkgname}/root${PREFIX}"
    mkdir -p "$_root"

    for _src in "$@"; do
        _srcpath="${SRC}/${_src}"
        if [ -e "$_srcpath" ] || ls ${_srcpath} >/dev/null 2>&1; then
            _destdir="${_root}/$(dirname "$_src")"
            mkdir -p "$_destdir"
            cp -RPp ${_srcpath} "$_destdir/" 2>/dev/null || true
        else
            echo "  WARN: ${_src} not found in staging"
        fi
    done
}

# Helper: copy pkginfo and depend from package definitions
pkg_meta() {
    _pkgname="$1"
    _pkgdir="${SCRIPTDIR}/packages/${_pkgname}"
    _outdir="${OUTPUT}/${_pkgname}"
    mkdir -p "$_outdir"
    cp "${_pkgdir}/pkginfo" "${_outdir}/"
    [ -f "${_pkgdir}/depend" ] && cp "${_pkgdir}/depend" "${_outdir}/"
    [ -f "${_pkgdir}/postinstall" ] && cp "${_pkgdir}/postinstall" "${_outdir}/"
    [ -f "${_pkgdir}/preremove" ] && cp "${_pkgdir}/preremove" "${_outdir}/"
}

# Clean output
rm -rf "${OUTPUT}"
mkdir -p "${OUTPUT}"

# ============================================================
# SSTgmp — GMP
# ============================================================
echo "--- SSTgmp: GMP 6.1.2 ---"
pkg_meta gmp
pkg_copy gmp \
    lib/libgmp.so lib/libgmp.so.10 lib/libgmp.so.10.3.2 lib/libgmp.a \
    include/gmp.h include/gmpxx.h

# ============================================================
# SSTmpfr — MPFR
# ============================================================
echo "--- SSTmpfr: MPFR 3.1.4 ---"
pkg_meta mpfr
pkg_copy mpfr \
    lib/libmpfr.so lib/libmpfr.so.4 lib/libmpfr.so.4.1.4 lib/libmpfr.a \
    include/mpfr.h include/mpf2mpfr.h

# ============================================================
# SSTmpc — MPC
# ============================================================
echo "--- SSTmpc: MPC 1.0.3 ---"
pkg_meta mpc
pkg_copy mpc \
    lib/libmpc.so lib/libmpc.so.3 lib/libmpc.so.3.0.0 lib/libmpc.a \
    include/mpc.h

# ============================================================
# SSTbinut — GNU binutils 2.32
# ============================================================
echo "--- SSTbinut: GNU binutils 2.32 ---"
pkg_meta binutils
pkg_copy binutils \
    bin/gas bin/gld bin/gar bin/gnm bin/granlib \
    bin/gobjdump bin/gobjcopy bin/gstrip bin/greadelf \
    bin/gsize bin/gstrings bin/gaddr2line bin/gc++filt \
    bin/gelfedit bin/ggprof \
    sparc-sun-solaris2.7/bin/

# ============================================================
# SSTlgcc1 — libgcc runtime
# ============================================================
echo "--- SSTlgcc1: libgcc runtime ---"
pkg_meta libgcc
pkg_copy libgcc \
    lib/libgcc_s.so lib/libgcc_s.so.1 \
    lib/gcc/sparc-sun-solaris2.7/4.9.4/libgcc.a \
    lib/gcc/sparc-sun-solaris2.7/4.9.4/libgcc_eh.a \
    lib/gcc/sparc-sun-solaris2.7/4.9.4/libgcov.a \
    lib/gcc/sparc-sun-solaris2.7/4.9.4/crtbegin.o \
    lib/gcc/sparc-sun-solaris2.7/4.9.4/crtend.o \
    lib/gcc/sparc-sun-solaris2.7/4.9.4/crtbeginS.o \
    lib/gcc/sparc-sun-solaris2.7/4.9.4/crtendS.o \
    lib/gcc/sparc-sun-solaris2.7/4.9.4/crtbeginT.o \
    lib/gcc/sparc-sun-solaris2.7/4.9.4/crtfastmath.o

# ============================================================
# SSTgcc49 — GCC 4.9.4 C compiler
# ============================================================
echo "--- SSTgcc49: GCC 4.9.4 C compiler ---"
pkg_meta gcc
pkg_copy gcc \
    gcc49/bin/gcc gcc49/bin/cpp gcc49/bin/gcov \
    gcc49/bin/gcc-ar gcc49/bin/gcc-nm gcc49/bin/gcc-ranlib \
    gcc49/bin/sparc-sun-solaris2.7-gcc-4.9.4 \
    gcc49/man/ gcc49/info/ \
    libexec/gcc/sparc-sun-solaris2.7/4.9.4/cc1 \
    libexec/gcc/sparc-sun-solaris2.7/4.9.4/collect2 \
    libexec/gcc/sparc-sun-solaris2.7/4.9.4/lto-wrapper \
    libexec/gcc/sparc-sun-solaris2.7/4.9.4/lto1 \
    libexec/gcc/sparc-sun-solaris2.7/4.9.4/install-tools/ \
    lib/gcc/sparc-sun-solaris2.7/4.9.4/include/ \
    lib/gcc/sparc-sun-solaris2.7/4.9.4/include-fixed/ \
    lib/gcc/sparc-sun-solaris2.7/4.9.4/install-tools/

# ============================================================
# SSTlstdc — libstdc++ shared
# ============================================================
echo "--- SSTlstdc: libstdc++ shared ---"
pkg_meta libstdcxx
pkg_copy libstdcxx \
    lib/libstdc++.so lib/libstdc++.so.6 lib/libstdc++.so.6.0.20

# ============================================================
# SSTlstdd — libstdc++ headers + static
# ============================================================
echo "--- SSTlstdd: libstdc++ devel ---"
pkg_meta libstdcxx-devel
pkg_copy libstdcxx-devel \
    lib/libstdc++.a \
    include/c++/4.9.4/

# ============================================================
# SSTg49cx — GCC C++ compiler
# ============================================================
echo "--- SSTg49cx: GCC C++ compiler ---"
pkg_meta gcc-cxx
pkg_copy gcc-cxx \
    gcc49/bin/g++ gcc49/bin/c++ \
    libexec/gcc/sparc-sun-solaris2.7/4.9.4/cc1plus

# ============================================================
# SSTg49cf — GCC Fortran compiler
# ============================================================
echo "--- SSTg49cf: GCC Fortran compiler ---"
pkg_meta gcc-fortran
pkg_copy gcc-fortran \
    gcc49/bin/gfortran \
    libexec/gcc/sparc-sun-solaris2.7/4.9.4/f951 \
    lib/gcc/sparc-sun-solaris2.7/4.9.4/finclude/

# ============================================================
# SSTg49co — GCC Objective-C/C++ compiler
# ============================================================
echo "--- SSTg49co: GCC Objective-C/C++ compiler ---"
pkg_meta gcc-objc
pkg_copy gcc-objc \
    libexec/gcc/sparc-sun-solaris2.7/4.9.4/cc1obj \
    libexec/gcc/sparc-sun-solaris2.7/4.9.4/cc1objplus

# ============================================================
# SSTlgomp — OpenMP runtime
# ============================================================
echo "--- SSTlgomp: OpenMP runtime ---"
pkg_meta libgomp
pkg_copy libgomp \
    lib/libgomp.so lib/libgomp.so.1 lib/libgomp.so.1.0.0

# ============================================================
# SSTlgfrt — libgfortran runtime
# ============================================================
echo "--- SSTlgfrt: libgfortran runtime ---"
pkg_meta libgfortran
pkg_copy libgfortran \
    lib/libgfortran.so lib/libgfortran.so.3 lib/libgfortran.so.3.0.0 lib/libgfortran.a

# ============================================================
# SSTlobjc — libobjc runtime
# ============================================================
echo "--- SSTlobjc: libobjc runtime ---"
pkg_meta libobjc
pkg_copy libobjc \
    lib/libobjc.so lib/libobjc.so.4 lib/libobjc.so.4.0.0 lib/libobjc.a

# ============================================================
# Summary
# ============================================================
echo ""
echo "============================================"
echo "  Package split complete"
echo "============================================"
echo ""
for _dir in "${OUTPUT}"/*/; do
    _name=$(basename "$_dir")
    _pkg=$(grep '^PKG=' "${_dir}/pkginfo" | sed 's/PKG="*\([^"]*\)"*/\1/')
    _size=$(du -sh "${_dir}root" 2>/dev/null | awk '{print $1}')
    printf "  %-20s %-10s %s\n" "$_name" "$_pkg" "${_size:-empty}"
done
echo ""
echo "Output: ${OUTPUT}"
