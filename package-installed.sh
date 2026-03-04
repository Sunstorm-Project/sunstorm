#!/bin/ksh
# package-installed.sh — Create SVR4 packages from installed software
#
# Runs on the Solaris 7 VM. Scans files already installed under
# /usr/tgcware (cross-build output) and packages them into individual
# sunstorm .pkg.gz files with proper dependency metadata.
#
# Usage: /bin/ksh package-installed.sh [output_dir]
#
# This is useful for creating the initial sunstorm package set from the
# existing cross-build installation without re-running the cross-build.

set -e

OUTPUT="${1:-/export/sunstorm-packages}"
PREFIX=/usr/tgcware
GCC49=${PREFIX}/gcc49
TARGET=sparc-sun-solaris2.7
GCC_VER=4.9.4

TMPDIR=/tmp/sst-pkg-$$
SPOOLDIR=${TMPDIR}/spool

PKG_VENDOR="Sunstorm Project"
PKG_EMAIL="julian@sunstorm"
PKG_ARCH="sparc"
PKG_BASEDIR="${PREFIX}"
SST_OS="sunos5.7"

echo "============================================"
echo "  Sunstorm Native Packager"
echo "  Source: ${PREFIX}"
echo "  Output: ${OUTPUT}"
echo "============================================"
echo ""

# Verify we're on Solaris
if [ "$(uname -s)" != "SunOS" ]; then
    echo "ERROR: This script must run on Solaris."
    exit 1
fi

# Verify tools
for tool in pkgmk pkgtrans; do
    if ! command -v $tool >/dev/null 2>&1; then
        echo "ERROR: $tool not found"
        exit 1
    fi
done

mkdir -p "${OUTPUT}" "${TMPDIR}"

# ============================================================
# Helper: create SVR4 package from a file list
# ============================================================
# Args: pkg_code name version description file_list_file [depend_file]
make_pkg() {
    _code="$1"
    _name="$2"
    _ver="$3"
    _desc="$4"
    _files="$5"
    _depend="$6"
    _postinstall="$7"
    
    _stagedir="${TMPDIR}/${_code}"
    rm -rf "${_stagedir}"
    mkdir -p "${_stagedir}"
    
    echo "--- ${_code}: ${_name} ---"
    
    # Generate pkginfo
    cat > "${_stagedir}/pkginfo" << EOF
PKG="${_code}"
NAME="${_name}"
ARCH="${PKG_ARCH}"
VERSION="${_ver},REV=1"
CATEGORY="application"
VENDOR="${PKG_VENDOR}"
EMAIL="${PKG_EMAIL}"
BASEDIR="${PKG_BASEDIR}"
CLASSES="none"
PSTAMP="$(hostname)$(date '+%Y%m%d%H%M%S')"
DESC="${_desc}"
EOF
    
    # Copy depend file
    if [ -n "${_depend}" ] && [ -f "${_depend}" ]; then
        cp "${_depend}" "${_stagedir}/depend"
    fi
    
    # Copy postinstall
    if [ -n "${_postinstall}" ] && [ -f "${_postinstall}" ]; then
        cp "${_postinstall}" "${_stagedir}/postinstall"
    fi
    
    # Generate prototype
    {
        echo "i pkginfo"
        [ -f "${_stagedir}/depend" ] && echo "i depend"
        [ -f "${_stagedir}/postinstall" ] && echo "i postinstall"
        
        # Process file list: each line is a path relative to BASEDIR
        _count=0
        while IFS= read -r _line; do
            case "$_line" in
                \#*|"") continue ;;
            esac
            _fullpath="${PREFIX}/${_line}"
            if [ -d "$_fullpath" ]; then
                echo "d none ${_line} 0755 root bin"
            elif [ -L "$_fullpath" ]; then
                _target=$(ls -l "$_fullpath" | sed 's/.*-> //')
                echo "s none ${_line}=${_target}"
            elif [ -x "$_fullpath" ]; then
                echo "f none ${_line} 0755 root bin"
                _count=$((_count + 1))
            elif [ -f "$_fullpath" ]; then
                echo "f none ${_line} 0644 root bin"
                _count=$((_count + 1))
            fi
        done < "${_files}"
        echo "  Files: ${_count}" >&2
    } > "${_stagedir}/prototype"
    
    # Create SVR4 package
    rm -rf "${SPOOLDIR}"
    mkdir -p "${SPOOLDIR}"
    
    pkgmk -o -d "${SPOOLDIR}" -r "${PREFIX}" -f "${_stagedir}/prototype" 2>&1 || {
        echo "  ERROR: pkgmk failed for ${_code}"
        return 1
    }
    
    _pkgfile="${OUTPUT}/${_code}-${_ver}-1.sst-${SST_OS}-sparc.pkg"
    pkgtrans -s "${SPOOLDIR}" "${_pkgfile}" "${_code}" 2>&1 || {
        echo "  ERROR: pkgtrans failed for ${_code}"
        return 1
    }
    
    # Compress
    gzip -9f "${_pkgfile}"
    _size=$(ls -lh "${_pkgfile}.gz" | awk '{print $5}')
    echo "  Created: ${_code}-${_ver}-1.sst-${SST_OS}-sparc.pkg.gz (${_size})"
    echo ""
}

# ============================================================
# Generate file lists by scanning installed files
# ============================================================
echo "Scanning installed files..."
echo ""

LISTS=${TMPDIR}/lists
DEPS=${TMPDIR}/deps
mkdir -p "${LISTS}" "${DEPS}"

# --- SSTbinut: GNU binutils ---
{
    for tool in gas gld gar gnm granlib gobjdump gobjcopy gstrip greadelf gsize gstrings gaddr2line gc++filt gelfedit ggprof; do
        [ -f "${PREFIX}/bin/${tool}" ] && echo "bin/${tool}"
    done
    if [ -d "${PREFIX}/${TARGET}/bin" ]; then
        ls "${PREFIX}/${TARGET}/bin/" 2>/dev/null | while read _f; do
            echo "${TARGET}/bin/${_f}"
        done
    fi
    if [ -d "${PREFIX}/${TARGET}/lib" ]; then
        ls "${PREFIX}/${TARGET}/lib/" 2>/dev/null | while read _f; do
            echo "${TARGET}/lib/${_f}"
        done
    fi
} > "${LISTS}/binutils"

# --- SSTgmp: GMP ---
{
    for f in lib/libgmp.so lib/libgmp.so.10 lib/libgmp.so.10.3.2 lib/libgmp.a; do
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

# --- SSTlgcc1: libgcc runtime ---
{
    for f in lib/libgcc_s.so lib/libgcc_s.so.1; do
        [ -e "${PREFIX}/${f}" ] && echo "$f"
    done
    for f in lib/gcc/${TARGET}/${GCC_VER}/libgcc.a \
             lib/gcc/${TARGET}/${GCC_VER}/libgcc_eh.a \
             lib/gcc/${TARGET}/${GCC_VER}/libgcov.a \
             lib/gcc/${TARGET}/${GCC_VER}/crtbegin.o \
             lib/gcc/${TARGET}/${GCC_VER}/crtend.o \
             lib/gcc/${TARGET}/${GCC_VER}/crtbeginS.o \
             lib/gcc/${TARGET}/${GCC_VER}/crtendS.o \
             lib/gcc/${TARGET}/${GCC_VER}/crtbeginT.o \
             lib/gcc/${TARGET}/${GCC_VER}/crtfastmath.o; do
        [ -f "${PREFIX}/${f}" ] && echo "$f"
    done
} > "${LISTS}/libgcc"

# --- SSTgcc49: GCC C compiler ---
{
    for f in gcc49/bin/gcc gcc49/bin/cpp gcc49/bin/gcov \
             gcc49/bin/gcc-ar gcc49/bin/gcc-nm gcc49/bin/gcc-ranlib; do
        [ -f "${PREFIX}/${f}" ] && echo "$f"
    done
    # Cross-name symlink
    [ -f "${PREFIX}/gcc49/bin/${TARGET}-gcc-${GCC_VER}" ] && echo "gcc49/bin/${TARGET}-gcc-${GCC_VER}"
    [ -f "${PREFIX}/gcc49/bin/${TARGET}-gcc" ] && echo "gcc49/bin/${TARGET}-gcc"
    # Compiler backends
    for f in libexec/gcc/${TARGET}/${GCC_VER}/cc1 \
             libexec/gcc/${TARGET}/${GCC_VER}/collect2 \
             libexec/gcc/${TARGET}/${GCC_VER}/lto-wrapper \
             libexec/gcc/${TARGET}/${GCC_VER}/lto1; do
        [ -f "${PREFIX}/${f}" ] && echo "$f"
    done
    # GCC internal headers
    if [ -d "${PREFIX}/lib/gcc/${TARGET}/${GCC_VER}/include" ]; then
        find "${PREFIX}/lib/gcc/${TARGET}/${GCC_VER}/include" -type f | sed "s|^${PREFIX}/||"
    fi
    if [ -d "${PREFIX}/lib/gcc/${TARGET}/${GCC_VER}/include-fixed" ]; then
        find "${PREFIX}/lib/gcc/${TARGET}/${GCC_VER}/include-fixed" -type f | sed "s|^${PREFIX}/||"
    fi
    # Man/info pages
    if [ -d "${PREFIX}/gcc49/man" ]; then
        find "${PREFIX}/gcc49/man" -type f | sed "s|^${PREFIX}/||"
    fi
    if [ -d "${PREFIX}/gcc49/info" ]; then
        find "${PREFIX}/gcc49/info" -type f | sed "s|^${PREFIX}/||"
    fi
} > "${LISTS}/gcc"

# --- SSTlstdc: libstdc++ shared ---
{
    for f in lib/libstdc++.so lib/libstdc++.so.6 lib/libstdc++.so.6.0.20; do
        [ -e "${PREFIX}/${f}" ] && echo "$f"
    done
} > "${LISTS}/libstdcxx"

# --- SSTlstdd: libstdc++ devel ---
{
    [ -f "${PREFIX}/lib/libstdc++.a" ] && echo "lib/libstdc++.a"
    if [ -d "${PREFIX}/include/c++/${GCC_VER}" ]; then
        find "${PREFIX}/include/c++/${GCC_VER}" -type f | sed "s|^${PREFIX}/||"
    fi
} > "${LISTS}/libstdcxx-devel"

# --- SSTg49cx: GCC C++ ---
{
    for f in gcc49/bin/g++ gcc49/bin/c++; do
        [ -f "${PREFIX}/${f}" ] && echo "$f"
    done
    [ -f "${PREFIX}/libexec/gcc/${TARGET}/${GCC_VER}/cc1plus" ] && echo "libexec/gcc/${TARGET}/${GCC_VER}/cc1plus"
} > "${LISTS}/gcc-cxx"

# --- SSTlgfrt: libgfortran ---
{
    for f in lib/libgfortran.so lib/libgfortran.so.3 lib/libgfortran.so.3.0.0 lib/libgfortran.a; do
        [ -e "${PREFIX}/${f}" ] && echo "$f"
    done
} > "${LISTS}/libgfortran"

# --- SSTg49cf: GCC Fortran ---
{
    [ -f "${PREFIX}/gcc49/bin/gfortran" ] && echo "gcc49/bin/gfortran"
    [ -f "${PREFIX}/libexec/gcc/${TARGET}/${GCC_VER}/f951" ] && echo "libexec/gcc/${TARGET}/${GCC_VER}/f951"
    if [ -d "${PREFIX}/lib/gcc/${TARGET}/${GCC_VER}/finclude" ]; then
        find "${PREFIX}/lib/gcc/${TARGET}/${GCC_VER}/finclude" -type f | sed "s|^${PREFIX}/||"
    fi
} > "${LISTS}/gcc-fortran"

# --- SSTlobjc: libobjc ---
{
    for f in lib/libobjc.so lib/libobjc.so.4 lib/libobjc.so.4.0.0 lib/libobjc.a; do
        [ -e "${PREFIX}/${f}" ] && echo "$f"
    done
} > "${LISTS}/libobjc"

# --- SSTg49co: GCC Objective-C ---
{
    [ -f "${PREFIX}/libexec/gcc/${TARGET}/${GCC_VER}/cc1obj" ] && echo "libexec/gcc/${TARGET}/${GCC_VER}/cc1obj"
    [ -f "${PREFIX}/libexec/gcc/${TARGET}/${GCC_VER}/cc1objplus" ] && echo "libexec/gcc/${TARGET}/${GCC_VER}/cc1objplus"
} > "${LISTS}/gcc-objc"

# --- SSTlgomp: libgomp ---
{
    for f in lib/libgomp.so lib/libgomp.so.1 lib/libgomp.so.1.0.0 lib/libgomp.a; do
        [ -e "${PREFIX}/${f}" ] && echo "$f"
    done
} > "${LISTS}/libgomp"

# ============================================================
# Generate depend files
# ============================================================
cat > "${DEPS}/gmp" << 'EOF'
EOF

cat > "${DEPS}/mpfr" << 'EOF'
P SSTgmp    GNU Multiple Precision Arithmetic Library
EOF

cat > "${DEPS}/mpc" << 'EOF'
P SSTgmp    GNU Multiple Precision Arithmetic Library
P SSTmpfr   GNU Multiple Precision Floating-Point Library
EOF

cat > "${DEPS}/binutils" << 'EOF'
EOF

cat > "${DEPS}/libgcc" << 'EOF'
EOF

cat > "${DEPS}/gcc" << 'EOF'
P SSTbinut  GNU binary utilities
P SSTlgcc1  GCC runtime library
P SSTgmp    GNU Multiple Precision Arithmetic Library
P SSTmpfr   GNU Multiple Precision Floating-Point Library
P SSTmpc    GNU Multiple Precision Complex Library
EOF

cat > "${DEPS}/libstdcxx" << 'EOF'
P SSTlgcc1  GCC runtime library
EOF

cat > "${DEPS}/libstdcxx-devel" << 'EOF'
P SSTlstdc  libstdc++ shared library
EOF

cat > "${DEPS}/gcc-cxx" << 'EOF'
P SSTgcc49  GCC 4.9.4 C compiler
P SSTlstdc  libstdc++ shared library
P SSTlstdd  libstdc++ headers and static library
EOF

cat > "${DEPS}/libgfortran" << 'EOF'
P SSTlgcc1  GCC runtime library
EOF

cat > "${DEPS}/gcc-fortran" << 'EOF'
P SSTgcc49  GCC 4.9.4 C compiler
P SSTlgcc1  GCC runtime library
P SSTlgfrt  GCC Fortran runtime library
EOF

cat > "${DEPS}/libobjc" << 'EOF'
P SSTlgcc1  GCC runtime library
EOF

cat > "${DEPS}/gcc-objc" << 'EOF'
P SSTgcc49  GCC 4.9.4 C compiler
P SSTlgcc1  GCC runtime library
P SSTlobjc  GCC Objective-C runtime library
EOF

cat > "${DEPS}/libgomp" << 'EOF'
P SSTlgcc1  GCC runtime library
EOF

# Postinstall for gcc
POSTINSTALL=${TMPDIR}/postinstall-gcc
cat > "${POSTINSTALL}" << 'POSTEOF'
#!/bin/sh
mkdir -p /etc/profile.d 2>/dev/null
cat > /etc/profile.d/sunstorm.sh << 'EOF'
# Sunstorm distribution PATH setup
if [ -d /usr/tgcware/gcc49/bin ]; then
    PATH=/usr/tgcware/gcc49/bin:/usr/tgcware/bin:$PATH
    export PATH
fi
if [ -d /usr/tgcware/lib ]; then
    LD_LIBRARY_PATH=/usr/tgcware/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
    export LD_LIBRARY_PATH
fi
EOF
echo "Sunstorm: PATH configured in /etc/profile.d/sunstorm.sh"
POSTEOF

# ============================================================
# Build all packages
# ============================================================
echo ""
echo "Building SVR4 packages..."
echo ""

make_pkg "SSTgmp"    "gmp - GNU Multiple Precision Arithmetic"      "6.1.2" "GMP arbitrary precision arithmetic library"  "${LISTS}/gmp"            "${DEPS}/gmp"       ""
make_pkg "SSTmpfr"   "mpfr - GNU Multiple Precision Floating-Point" "3.1.4" "MPFR multiple precision floating-point"       "${LISTS}/mpfr"           "${DEPS}/mpfr"      ""
make_pkg "SSTmpc"    "mpc - GNU Multiple Precision Complex"         "1.0.3" "MPC multiple precision complex arithmetic"    "${LISTS}/mpc"            "${DEPS}/mpc"       ""
make_pkg "SSTbinut"  "binutils - GNU binary utilities"              "2.32"  "GNU assembler, linker, and binary utilities"  "${LISTS}/binutils"       "${DEPS}/binutils"  ""
make_pkg "SSTlgcc1"  "libgcc - GCC runtime library"                "${GCC_VER}" "GCC runtime library (libgcc_s.so)"       "${LISTS}/libgcc"         "${DEPS}/libgcc"    ""
make_pkg "SSTgcc49"  "gcc - GNU C Compiler 4.9.4"                  "${GCC_VER}" "GCC C compiler, preprocessor, coverage"  "${LISTS}/gcc"            "${DEPS}/gcc"       "${POSTINSTALL}"
make_pkg "SSTlstdc"  "libstdc++ - C++ standard library"            "${GCC_VER}" "libstdc++.so.6 shared library"           "${LISTS}/libstdcxx"      "${DEPS}/libstdcxx" ""
make_pkg "SSTlstdd"  "libstdc++-devel - C++ headers and static lib" "${GCC_VER}" "C++ standard library headers and archives" "${LISTS}/libstdcxx-devel" "${DEPS}/libstdcxx-devel" ""
make_pkg "SSTg49cx"  "gcc-c++ - GCC C++ compiler"                  "${GCC_VER}" "GCC C++ compiler (g++)"                  "${LISTS}/gcc-cxx"        "${DEPS}/gcc-cxx"   ""
make_pkg "SSTlgfrt"  "libgfortran - Fortran runtime"               "${GCC_VER}" "GCC Fortran runtime library"             "${LISTS}/libgfortran"    "${DEPS}/libgfortran" ""
make_pkg "SSTg49cf"  "gcc-fortran - GCC Fortran compiler"          "${GCC_VER}" "GCC Fortran compiler (gfortran)"         "${LISTS}/gcc-fortran"    "${DEPS}/gcc-fortran" ""
make_pkg "SSTlobjc"  "libobjc - Objective-C runtime"               "${GCC_VER}" "GCC Objective-C runtime library"         "${LISTS}/libobjc"        "${DEPS}/libobjc"   ""
make_pkg "SSTg49co"  "gcc-objc - GCC Objective-C compiler"         "${GCC_VER}" "GCC Objective-C/C++ compiler"            "${LISTS}/gcc-objc"       "${DEPS}/gcc-objc"  ""
make_pkg "SSTlgomp"  "libgomp - OpenMP runtime"                    "${GCC_VER}" "GCC OpenMP parallel runtime library"     "${LISTS}/libgomp"        "${DEPS}/libgomp"   ""

# ============================================================
# Summary
# ============================================================
echo ""
echo "============================================"
echo "  Package creation complete"
echo "============================================"
echo ""

_total=0
_totalsize=0
for f in "${OUTPUT}"/*.pkg.gz; do
    [ -f "$f" ] || continue
    _total=$((_total + 1))
    _s=$(ls -l "$f" | awk '{print $5}')
    _totalsize=$((_totalsize + _s))
    printf "  %-50s %s\n" "$(basename "$f")" "$(ls -lh "$f" | awk '{print $5}')"
done

echo ""
echo "  Total: ${_total} packages"
echo "  Output: ${OUTPUT}/"
echo ""
echo "Install order (respecting dependencies):"
echo "  1. SSTgmp SSTbinut SSTlgcc1"
echo "  2. SSTmpfr"
echo "  3. SSTmpc"
echo "  4. SSTgcc49 SSTlstdc SSTlgfrt SSTlobjc SSTlgomp"
echo "  5. SSTlstdd"
echo "  6. SSTg49cx SSTg49cf SSTg49co"

# Cleanup
rm -rf "${TMPDIR}"
