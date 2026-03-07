#!/bin/ksh
# package-installed.sh - Create SVR4 packages from cross-build output
#
# Runs on Solaris 7. Scans files installed under INSTALL_ROOT and creates
# individual .pkg.Z files following SVR4 ABI packaging conventions.
#
# Usage:
#   /bin/ksh package-installed.sh [output_dir] [install_root]
#
# Environment:
#   GCC_SUBDIR  - subdirectory under INSTALL_ROOT containing GCC
#                 (default: gcc; set to gcc49 for tgcware layout)
#
# Per-package metadata (depend, postinstall) is read from packages/<name>/
# relative to this script's directory.

set -e

SCRIPTDIR=$(cd "$(dirname "$0")" && pwd)
PKGMETA="${SCRIPTDIR}/packages"

OUTPUT="${1:-/export/sunstorm-packages}"
INSTALL_ROOT="${2:-/opt/sst}"
PREFIX="${INSTALL_ROOT}"
GCC_SUBDIR="${GCC_SUBDIR:-gcc}"
GCC_DIR="${PREFIX}/${GCC_SUBDIR}"
TARGET=sparc-sun-solaris2.7
GCC_VER=4.9.4

TMPDIR=/tmp/sst-pkg-$$
SPOOLDIR="${TMPDIR}/spool"

# SVR4 pkginfo fields
PKG_VENDOR="Sunstorm Project"
PKG_EMAIL="julian@sunstorm"
PKG_ARCH="sparc"
PKG_BASEDIR="${PREFIX}"

echo "============================================"
echo "  Sunstorm SVR4 Packager"
echo "  Install root : ${PREFIX}"
echo "  GCC subdir   : ${GCC_SUBDIR}"
echo "  Output       : ${OUTPUT}"
echo "============================================"
echo ""

# --- Preflight ---
if [ "$(uname -s)" != "SunOS" ]; then
    echo "ERROR: Must run on Solaris (need pkgmk/pkgtrans)." >&2
    exit 1
fi
for tool in pkgmk pkgtrans compress find; do
    if ! command -v $tool >/dev/null 2>&1; then
        echo "ERROR: Required tool '$tool' not found." >&2
        exit 1
    fi
done
if [ ! -d "${PREFIX}" ]; then
    echo "ERROR: Install root ${PREFIX} does not exist." >&2
    exit 1
fi

mkdir -p "${OUTPUT}" "${TMPDIR}"

# ============================================================
# make_pkg - create one SVR4 package from a file list
# ============================================================
# Args: pkg_code pkg_name version category description filelist_file pkg_meta_dir
#
# pkg_meta_dir may contain: depend, postinstall, preinstall, postremove, preremove
make_pkg() {
    _code="$1"; _name="$2"; _ver="$3"; _cat="$4"
    _desc="$5"; _files="$6"; _meta="$7"

    _stagedir="${TMPDIR}/${_code}"
    rm -rf "${_stagedir}"
    mkdir -p "${_stagedir}"

    echo "--- ${_code}: ${_name} v${_ver} ---"

    # Count real files
    _realcount=0
    while IFS= read -r _line; do
        case "$_line" in \#*|"") continue ;; esac
        [ -e "${PREFIX}/${_line}" ] && _realcount=$((_realcount + 1))
    done < "${_files}"
    if [ ${_realcount} -eq 0 ]; then
        echo "  SKIPPED (no files found under ${PREFIX})"
        echo ""
        return 0
    fi

    # --- pkginfo ---
    cat > "${_stagedir}/pkginfo" << EOF
PKG=${_code}
NAME=${_name}
ARCH=${PKG_ARCH}
VERSION=${_ver},REV=$(date '+%Y.%m.%d')
CATEGORY=${_cat}
VENDOR=${PKG_VENDOR}
EMAIL=${PKG_EMAIL}
BASEDIR=${PKG_BASEDIR}
CLASSES=none
PSTAMP=$(hostname)$(date '+%Y%m%d%H%M%S')
DESC=${_desc}
EOF

    # --- Copy packaging scripts from metadata dir ---
    for _script in depend postinstall preinstall postremove preremove; do
        if [ -n "${_meta}" ] && [ -f "${_meta}/${_script}" ]; then
            cp "${_meta}/${_script}" "${_stagedir}/${_script}"
        fi
    done

    # --- prototype ---
    {
        echo "i pkginfo"
        for _script in depend postinstall preinstall postremove preremove; do
            [ -f "${_stagedir}/${_script}" ] && echo "i ${_script}"
        done

        while IFS= read -r _line; do
            case "$_line" in \#*|"") continue ;; esac
            _fullpath="${PREFIX}/${_line}"
            if [ -d "$_fullpath" ]; then
                echo "d none ${_line} 0755 root bin"
            elif [ -L "$_fullpath" ]; then
                _target=$(ls -l "$_fullpath" | sed 's/.*-> //')
                echo "s none ${_line}=${_target}"
            elif [ -x "$_fullpath" ]; then
                echo "f none ${_line} 0755 root bin"
            elif [ -f "$_fullpath" ]; then
                echo "f none ${_line} 0644 root bin"
            fi
        done < "${_files}"
    } > "${_stagedir}/prototype"

    # --- pkgmk + pkgtrans ---
    rm -rf "${SPOOLDIR}"
    mkdir -p "${SPOOLDIR}"

    if ! pkgmk -o -d "${SPOOLDIR}" -r "${PREFIX}" \
         -f "${_stagedir}/prototype" 2>&1; then
        echo "  ERROR: pkgmk failed for ${_code}" >&2
        return 1
    fi

    _pkgfile="${OUTPUT}/${_code}-${_ver}-${PKG_ARCH}.pkg"
    if ! pkgtrans -s "${SPOOLDIR}" "${_pkgfile}" "${_code}" 2>&1; then
        echo "  ERROR: pkgtrans failed for ${_code}" >&2
        return 1
    fi

    compress "${_pkgfile}"
    _size=$(ls -l "${_pkgfile}.Z" | awk '{print $5}')
    echo "  ${_realcount} objects -> ${_code}-${_ver}-${PKG_ARCH}.pkg.Z (${_size} bytes)"
    echo ""
}

# ============================================================
# Scan installed files and build file lists
# ============================================================
echo "Scanning ${PREFIX} ..."
echo ""

LISTS="${TMPDIR}/lists"
mkdir -p "${LISTS}"

# --- SSTbinut: GNU binutils ---
{
    for f in gas gld gar gnm granlib gobjdump gobjcopy gstrip \
             greadelf gsize gstrings gaddr2line gc++filt gelfedit ggprof; do
        [ -f "${PREFIX}/bin/${f}" ] && echo "bin/${f}"
    done
    if [ -d "${PREFIX}/${TARGET}/bin" ]; then
        find "${PREFIX}/${TARGET}/bin" -type f | sed "s|^${PREFIX}/||"
    fi
    if [ -d "${PREFIX}/${TARGET}/lib" ]; then
        find "${PREFIX}/${TARGET}/lib" -type f -o -type l | sed "s|^${PREFIX}/||"
    fi
} > "${LISTS}/binutils"

# --- SSTgmp: GMP ---
{
    for f in lib/libgmp.so lib/libgmp.so.10 lib/libgmp.so.10.3.2 lib/libgmp.a \
             lib/libgmpxx.so lib/libgmpxx.so.4 lib/libgmpxx.so.4.5.2 lib/libgmpxx.a; do
        [ -e "${PREFIX}/${f}" ] && echo "$f"
    done
    [ -f "${PREFIX}/include/gmp.h" ] && echo "include/gmp.h"
    [ -f "${PREFIX}/include/gmpxx.h" ] && echo "include/gmpxx.h"
} > "${LISTS}/gmp"

# --- SSTmpfr: MPFR ---
{
    for f in lib/libmpfr.so lib/libmpfr.so.4 lib/libmpfr.so.4.1.4 lib/libmpfr.a; do
        [ -e "${PREFIX}/${f}" ] && echo "$f"
    done
    [ -f "${PREFIX}/include/mpfr.h" ] && echo "include/mpfr.h"
    [ -f "${PREFIX}/include/mpf2mpfr.h" ] && echo "include/mpf2mpfr.h"
} > "${LISTS}/mpfr"

# --- SSTmpc: MPC ---
{
    for f in lib/libmpc.so lib/libmpc.so.3 lib/libmpc.so.3.0.0 lib/libmpc.a; do
        [ -e "${PREFIX}/${f}" ] && echo "$f"
    done
    [ -f "${PREFIX}/include/mpc.h" ] && echo "include/mpc.h"
} > "${LISTS}/mpc"

# --- SSTlgcc: libgcc runtime ---
{
    for f in lib/libgcc_s.so lib/libgcc_s.so.1; do
        [ -e "${PREFIX}/${f}" ] && echo "$f"
    done
    for f in lib/gcc/${TARGET}/${GCC_VER}/libgcc.a \
             lib/gcc/${TARGET}/${GCC_VER}/libgcc_eh.a \
             lib/gcc/${TARGET}/${GCC_VER}/libgcov.a \
             lib/gcc/${TARGET}/${GCC_VER}/crt1.o \
             lib/gcc/${TARGET}/${GCC_VER}/crti.o \
             lib/gcc/${TARGET}/${GCC_VER}/crtn.o \
             lib/gcc/${TARGET}/${GCC_VER}/crtbegin.o \
             lib/gcc/${TARGET}/${GCC_VER}/crtend.o \
             lib/gcc/${TARGET}/${GCC_VER}/crtbeginS.o \
             lib/gcc/${TARGET}/${GCC_VER}/crtendS.o \
             lib/gcc/${TARGET}/${GCC_VER}/crtbeginT.o \
             lib/gcc/${TARGET}/${GCC_VER}/crtfastmath.o \
             lib/gcc/${TARGET}/${GCC_VER}/gcrt1.o \
             lib/gcc/${TARGET}/${GCC_VER}/gmon.o; do
        [ -f "${PREFIX}/${f}" ] && echo "$f"
    done
} > "${LISTS}/libgcc"

# --- SSTgcc: GCC C compiler ---
{
    for f in ${GCC_SUBDIR}/bin/gcc ${GCC_SUBDIR}/bin/cpp \
             ${GCC_SUBDIR}/bin/gcov ${GCC_SUBDIR}/bin/gcc-ar \
             ${GCC_SUBDIR}/bin/gcc-nm ${GCC_SUBDIR}/bin/gcc-ranlib; do
        [ -f "${PREFIX}/${f}" ] && echo "$f"
    done
    [ -f "${GCC_DIR}/bin/${TARGET}-gcc-${GCC_VER}" ] && \
        echo "${GCC_SUBDIR}/bin/${TARGET}-gcc-${GCC_VER}"
    [ -f "${GCC_DIR}/bin/${TARGET}-gcc" ] && \
        echo "${GCC_SUBDIR}/bin/${TARGET}-gcc"
    for f in libexec/gcc/${TARGET}/${GCC_VER}/cc1 \
             libexec/gcc/${TARGET}/${GCC_VER}/collect2 \
             libexec/gcc/${TARGET}/${GCC_VER}/lto-wrapper \
             libexec/gcc/${TARGET}/${GCC_VER}/lto1; do
        [ -f "${PREFIX}/${f}" ] && echo "$f"
    done
    for d in include include-fixed; do
        _hdir="${PREFIX}/lib/gcc/${TARGET}/${GCC_VER}/${d}"
        [ -d "$_hdir" ] && find "$_hdir" -type f | sed "s|^${PREFIX}/||"
    done
    [ -d "${GCC_DIR}/man" ] && find "${GCC_DIR}/man" -type f | sed "s|^${PREFIX}/||"
    [ -d "${GCC_DIR}/info" ] && find "${GCC_DIR}/info" -type f | sed "s|^${PREFIX}/||"
} > "${LISTS}/gcc"

# --- SSTlstdc: libstdc++ shared ---
{
    for f in lib/libstdc++.so lib/libstdc++.so.6 lib/libstdc++.so.6.0.20 \
             lib/libstdc++.so.6.0.20-gdb.py; do
        [ -e "${PREFIX}/${f}" ] && echo "$f"
    done
} > "${LISTS}/libstdcxx"

# --- SSTlstdd: libstdc++ devel ---
{
    [ -f "${PREFIX}/lib/libstdc++.a" ] && echo "lib/libstdc++.a"
    [ -d "${PREFIX}/include/c++/${GCC_VER}" ] && \
        find "${PREFIX}/include/c++/${GCC_VER}" -type f | sed "s|^${PREFIX}/||"
} > "${LISTS}/libstdcxx-devel"

# --- SSTgcxx: GCC C++ compiler ---
{
    for f in ${GCC_SUBDIR}/bin/g++ ${GCC_SUBDIR}/bin/c++; do
        [ -f "${PREFIX}/${f}" ] && echo "$f"
    done
    [ -f "${PREFIX}/libexec/gcc/${TARGET}/${GCC_VER}/cc1plus" ] && \
        echo "libexec/gcc/${TARGET}/${GCC_VER}/cc1plus"
} > "${LISTS}/gcc-cxx"

# --- SSTlgfrt: libgfortran ---
{
    find "${PREFIX}/lib" -name 'libgfortran.*' \( -type f -o -type l \) 2>/dev/null | \
        sed "s|^${PREFIX}/||"
} | grep -v '/gcc/' | sort -u > "${LISTS}/libgfortran"

# --- SSTgftn: GCC Fortran compiler ---
{
    [ -f "${GCC_DIR}/bin/gfortran" ] && echo "${GCC_SUBDIR}/bin/gfortran"
    [ -f "${PREFIX}/libexec/gcc/${TARGET}/${GCC_VER}/f951" ] && \
        echo "libexec/gcc/${TARGET}/${GCC_VER}/f951"
    [ -d "${PREFIX}/lib/gcc/${TARGET}/${GCC_VER}/finclude" ] && \
        find "${PREFIX}/lib/gcc/${TARGET}/${GCC_VER}/finclude" -type f | \
        sed "s|^${PREFIX}/||"
} > "${LISTS}/gcc-fortran"

# --- SSTlobjc: libobjc ---
{
    find "${PREFIX}/lib" -name 'libobjc.*' \( -type f -o -type l \) 2>/dev/null | \
        sed "s|^${PREFIX}/||"
} | grep -v '/gcc/' | sort -u > "${LISTS}/libobjc"

# --- SSTgobjc: GCC Objective-C ---
{
    [ -f "${PREFIX}/libexec/gcc/${TARGET}/${GCC_VER}/cc1obj" ] && \
        echo "libexec/gcc/${TARGET}/${GCC_VER}/cc1obj"
    [ -f "${PREFIX}/libexec/gcc/${TARGET}/${GCC_VER}/cc1objplus" ] && \
        echo "libexec/gcc/${TARGET}/${GCC_VER}/cc1objplus"
} > "${LISTS}/gcc-objc"

# --- SSTlgomp: libgomp + libitm + libssp + libatomic ---
{
    for _pat in 'libgomp.*' 'libitm.*' 'libssp.*' 'libsparcatomic.*' 'libatomic.*'; do
        find "${PREFIX}/lib" -name "${_pat}" \( -type f -o -type l \) 2>/dev/null | \
            sed "s|^${PREFIX}/||"
    done
} | grep -v '/gcc/' | sort -u > "${LISTS}/libgomp"

# ============================================================
# Build all packages
# ============================================================
# Categories per SVR4 ABI:
#   system      - runtime libraries
#   application - compilers, tools
echo ""
echo "Building SVR4 packages..."
echo ""

make_pkg "SSTgmp"   "gmp - GNU MP Arithmetic"               "6.1.2"      "system"      "GMP arbitrary precision arithmetic library"  "${LISTS}/gmp"           "${PKGMETA}/gmp"
make_pkg "SSTmpfr"  "mpfr - GNU MP Floating-Point"          "3.1.4"      "system"      "MPFR multiple precision floating-point"      "${LISTS}/mpfr"          "${PKGMETA}/mpfr"
make_pkg "SSTmpc"   "mpc - GNU MP Complex"                  "1.0.3"      "system"      "MPC multiple precision complex arithmetic"   "${LISTS}/mpc"           "${PKGMETA}/mpc"
make_pkg "SSTbinut" "binutils - GNU Binary Utilities"       "2.32"       "application" "GNU assembler, linker, and binary tools"     "${LISTS}/binutils"      "${PKGMETA}/binutils"
make_pkg "SSTlgcc"  "libgcc - GCC Runtime Library"          "${GCC_VER}" "system"      "GCC shared runtime library (libgcc_s.so)"   "${LISTS}/libgcc"        "${PKGMETA}/libgcc"
make_pkg "SSTgcc"   "gcc - GNU C Compiler"                  "${GCC_VER}" "application" "GCC C compiler, preprocessor, coverage"      "${LISTS}/gcc"           "${PKGMETA}/gcc"
make_pkg "SSTlstdc" "libstdc++ - C++ Standard Library"      "${GCC_VER}" "system"      "libstdc++.so.6 shared library"              "${LISTS}/libstdcxx"     "${PKGMETA}/libstdcxx"
make_pkg "SSTlstdd" "libstdc++-devel - C++ Headers"         "${GCC_VER}" "application" "C++ standard library headers and archives"   "${LISTS}/libstdcxx-devel" "${PKGMETA}/libstdcxx-devel"
make_pkg "SSTgcxx"  "gcc-c++ - GNU C++ Compiler"            "${GCC_VER}" "application" "GCC C++ compiler (g++)"                     "${LISTS}/gcc-cxx"       "${PKGMETA}/gcc-cxx"
make_pkg "SSTlgfrt" "libgfortran - Fortran Runtime"         "${GCC_VER}" "system"      "GCC Fortran runtime library"                "${LISTS}/libgfortran"   "${PKGMETA}/libgfortran"
make_pkg "SSTgftn"  "gcc-fortran - GNU Fortran Compiler"    "${GCC_VER}" "application" "GCC Fortran compiler (gfortran)"            "${LISTS}/gcc-fortran"   "${PKGMETA}/gcc-fortran"
make_pkg "SSTlobjc" "libobjc - Objective-C Runtime"         "${GCC_VER}" "system"      "GCC Objective-C runtime library"             "${LISTS}/libobjc"       "${PKGMETA}/libobjc"
make_pkg "SSTgobjc" "gcc-objc - GNU Objective-C Compiler"   "${GCC_VER}" "application" "GCC Objective-C/C++ compiler"               "${LISTS}/gcc-objc"      "${PKGMETA}/gcc-objc"
make_pkg "SSTlgomp" "libgomp - OpenMP Runtime"              "${GCC_VER}" "system"      "GCC OpenMP parallel runtime library"         "${LISTS}/libgomp"       "${PKGMETA}/libgomp"

# ============================================================
# Summary
# ============================================================
echo ""
echo "============================================"
echo "  Package build complete"
echo "============================================"
echo ""

_total=0
for f in "${OUTPUT}"/*.pkg.Z; do
    [ -f "$f" ] || continue
    _total=$((_total + 1))
    printf "  %-45s %s\n" "$(basename "$f")" "$(ls -lh "$f" | awk '{print $5}')"
done

echo ""
echo "  Total: ${_total} packages in ${OUTPUT}/"
echo ""
echo "  Install order (respecting dependencies):"
echo "    1. SSTgmp  SSTbinut  SSTlgcc"
echo "    2. SSTmpfr"
echo "    3. SSTmpc"
echo "    4. SSTgcc  SSTlstdc  SSTlgfrt  SSTlobjc  SSTlgomp"
echo "    5. SSTlstdd"
echo "    6. SSTgcxx  SSTgftn  SSTgobjc"
echo ""
echo "  Install with:  uncompress <file>.pkg.Z && pkgadd -d <file>.pkg all"

# Cleanup
rm -rf "${TMPDIR}"
