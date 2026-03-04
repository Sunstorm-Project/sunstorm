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

PREFIX="/opt/sst"
GCC_SUBDIR="gcc"
GCC_DIR="${PREFIX}/${GCC_SUBDIR}"
GCC_VER="4.9.4"
TARGET="${TARGET}"

echo "============================================"
echo "  Sunstorm Package Splitter"
echo "  Staging: ${STAGING}"
echo "  Output:  ${OUTPUT}"
echo "============================================"
echo ""

# Verify staging exists — look for the install root inside staging
STAGING_ROOT="${STAGING}/opt/sst"
if [ ! -d "${STAGING_ROOT}" ]; then
    # Fallback: check legacy layout
    for _try in "${STAGING}/opt/sunstorm" "${STAGING}/usr/local"; do
        if [ -d "$_try" ]; then
            STAGING_ROOT="$_try"
            break
        fi
    done
    if [ ! -d "${STAGING_ROOT}" ]; then
        echo "ERROR: No install root found under ${STAGING}/"
        exit 1
    fi
fi

# Source layout in staging (built for ${PREFIX}):
#   ${GCC_SUBDIR}/bin/         — compiler drivers
#   lib/gcc/...${GCC_VER}/  — cc1, cc1plus, f951, libs
#   libexec/gcc/...    — compiler backends
#   lib/libgcc_s.so*   — libgcc runtime
#   lib/libstdc++.*    — libstdc++ runtime + static
#   lib/libgomp.*      — OpenMP runtime
#   include/c++/${GCC_VER}/ — C++ headers
#   bin/g*             — binutils (g-prefixed)

SRC="${STAGING_ROOT}"

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
    ${TARGET}/bin/

# ============================================================
# SSTlgcc — libgcc runtime
# ============================================================
echo "--- SSTlgcc: libgcc runtime ---"
pkg_meta libgcc
pkg_copy libgcc \
    lib/libgcc_s.so lib/libgcc_s.so.1 \
    lib/gcc/${TARGET}/${GCC_VER}/libgcc.a \
    lib/gcc/${TARGET}/${GCC_VER}/libgcc_eh.a \
    lib/gcc/${TARGET}/${GCC_VER}/libgcov.a \
    lib/gcc/${TARGET}/${GCC_VER}/crtbegin.o \
    lib/gcc/${TARGET}/${GCC_VER}/crtend.o \
    lib/gcc/${TARGET}/${GCC_VER}/crtbeginS.o \
    lib/gcc/${TARGET}/${GCC_VER}/crtendS.o \
    lib/gcc/${TARGET}/${GCC_VER}/crtbeginT.o \
    lib/gcc/${TARGET}/${GCC_VER}/crtfastmath.o

# ============================================================
# SSTgcc — GCC C compiler
# ============================================================
echo "--- SSTgcc: GCC C compiler ---"
pkg_meta gcc
pkg_copy gcc \
    ${GCC_SUBDIR}/bin/gcc ${GCC_SUBDIR}/bin/cpp ${GCC_SUBDIR}/bin/gcov \
    ${GCC_SUBDIR}/bin/gcc-ar ${GCC_SUBDIR}/bin/gcc-nm ${GCC_SUBDIR}/bin/gcc-ranlib \
    ${GCC_SUBDIR}/bin/${TARGET}-gcc-${GCC_VER} \
    ${GCC_SUBDIR}/man/ ${GCC_SUBDIR}/info/ \
    libexec/gcc/${TARGET}/${GCC_VER}/cc1 \
    libexec/gcc/${TARGET}/${GCC_VER}/collect2 \
    libexec/gcc/${TARGET}/${GCC_VER}/lto-wrapper \
    libexec/gcc/${TARGET}/${GCC_VER}/lto1 \
    libexec/gcc/${TARGET}/${GCC_VER}/install-tools/ \
    lib/gcc/${TARGET}/${GCC_VER}/include/ \
    lib/gcc/${TARGET}/${GCC_VER}/include-fixed/ \
    lib/gcc/${TARGET}/${GCC_VER}/install-tools/

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
    include/c++/${GCC_VER}/

# ============================================================
# SSTgcxx — GCC C++ compiler
# ============================================================
echo "--- SSTgcxx: GCC C++ compiler ---"
pkg_meta gcc-cxx
pkg_copy gcc-cxx \
    ${GCC_SUBDIR}/bin/g++ ${GCC_SUBDIR}/bin/c++ \
    libexec/gcc/${TARGET}/${GCC_VER}/cc1plus

# ============================================================
# SSTgftn — GCC Fortran compiler
# ============================================================
echo "--- SSTgftn: GCC Fortran compiler ---"
pkg_meta gcc-fortran
pkg_copy gcc-fortran \
    ${GCC_SUBDIR}/bin/gfortran \
    libexec/gcc/${TARGET}/${GCC_VER}/f951 \
    lib/gcc/${TARGET}/${GCC_VER}/finclude/

# ============================================================
# SSTgobjc — GCC Objective-C/C++ compiler
# ============================================================
echo "--- SSTgobjc: GCC Objective-C/C++ compiler ---"
pkg_meta gcc-objc
pkg_copy gcc-objc \
    libexec/gcc/${TARGET}/${GCC_VER}/cc1obj \
    libexec/gcc/${TARGET}/${GCC_VER}/cc1objplus

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
