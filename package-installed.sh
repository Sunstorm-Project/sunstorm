#!/bin/ksh
# package-installed.sh — Create SVR4 packages from installed software
#
# Runs on the Solaris 7 VM. Scans files already installed under
# INSTALL_ROOT (cross-build output) and packages them into individual
# sunstorm .pkg.gz files with proper dependency metadata.
#
# Usage: /bin/ksh package-installed.sh [output_dir] [install_root]
#
# This is useful for creating the initial sunstorm package set from the
# existing cross-build installation without re-running the cross-build.

set -e

OUTPUT="${1:-/export/sunstorm-packages}"
INSTALL_ROOT="${2:-/opt/sst}"
PREFIX="${INSTALL_ROOT}"
GCC_SUBDIR=gcc
GCC_DIR=${PREFIX}/${GCC_SUBDIR}
TARGET=sparc-sun-solaris2.7
GCC_VER=4.9.4
SST_PREFIX=/opt/sunstorm

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
    
    # Check if file list has any actual files
    _realcount=0
    while IFS= read -r _chkline; do
        case "$_chkline" in
            \#*|"") continue ;;
        esac
        [ -e "${PREFIX}/${_chkline}" ] && _realcount=$((_realcount + 1))
    done < "${_files}"
    if [ ${_realcount} -eq 0 ]; then
        echo "  SKIPPED (no files found)"
        echo ""
        return 0
    fi
    
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
# Helper: create the symlink package (BASEDIR=/opt/sunstorm)
# ============================================================
# This builds SSTlink — a package of symlinks under /opt/sunstorm/bin
# and /opt/sunstorm/sbin that point to actual binaries scattered across
# the install root (PREFIX/bin, PREFIX/${GCC_SUBDIR}/bin, etc).
# Users only need:  PATH=/opt/sunstorm/bin:$PATH
make_links_pkg() {
    _code="SSTlink"
    _name="sunstorm-links - Centralized binary symlinks"
    _ver="1.0"
    _desc="Symlinks in /opt/sunstorm/bin for unified toolchain access"

    _stagedir="${TMPDIR}/${_code}"
    rm -rf "${_stagedir}"
    mkdir -p "${_stagedir}"

    echo "--- ${_code}: ${_name} ---"

    # pkginfo — note BASEDIR is /opt/sunstorm, not the install root
    cat > "${_stagedir}/pkginfo" << EOF
PKG="${_code}"
NAME="${_name}"
ARCH="${PKG_ARCH}"
VERSION="${_ver},REV=1"
CATEGORY="application"
VENDOR="${PKG_VENDOR}"
EMAIL="${PKG_EMAIL}"
BASEDIR="${SST_PREFIX}"
CLASSES="none"
PSTAMP="$(hostname)$(date '+%Y%m%d%H%M%S')"
DESC="${_desc}"
EOF

    # depend
    cat > "${_stagedir}/depend" << 'DEPEOF'
P SSTbinut  GNU binary utilities
P SSTgcc  GCC C compiler
DEPEOF

    # postinstall — configure PATH and LD_LIBRARY_PATH
    cat > "${_stagedir}/postinstall" << 'PIEOF'
#!/bin/sh
PROFILE_DIR=/etc/profile.d
if [ -d "${PROFILE_DIR}" ] || mkdir -p "${PROFILE_DIR}" 2>/dev/null; then
    cat > "${PROFILE_DIR}/sunstorm.sh" << 'EOF'
# Sunstorm distribution environment setup
SST_ROOT=/opt/sst
if [ -d "$SST_ROOT/gcc/bin" ]; then
    PATH=$SST_ROOT/gcc/bin:$PATH
fi
if [ -d "$SST_ROOT/bin" ]; then
    PATH=$SST_ROOT/bin:$PATH
fi
if [ -d "$SST_ROOT/lib" ]; then
    LD_LIBRARY_PATH=$SST_ROOT/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
fi
export PATH LD_LIBRARY_PATH
EOF
    echo "Sunstorm: PATH configured in ${PROFILE_DIR}/sunstorm.sh"
    echo "Sunstorm: Run '. ${PROFILE_DIR}/sunstorm.sh' or log in again."
else
    echo "Sunstorm: Add /opt/sst/bin and /opt/sst/gcc/bin to your PATH manually."
fi
PIEOF

    # Build the prototype with symlinks.
    # Each symlink lives under bin/ (relative to BASEDIR=/opt/sunstorm)
    # and points to the real absolute path of the binary.
    _count=0
    {
        echo "i pkginfo"
        echo "i depend"
        echo "i postinstall"
        echo "d none bin 0755 root bin"
        echo "d none sbin 0755 root bin"

        # --- GCC binaries (from ${GCC_DIR}/bin) ---
        for _bin in gcc g++ c++ cpp gcov gcc-ar gcc-nm gcc-ranlib gfortran; do
            if [ -f "${GCC_DIR}/bin/${_bin}" ]; then
                echo "s none bin/${_bin}=${GCC_DIR}/bin/${_bin}"
                _count=$((_count + 1))
            fi
        done
        # Also provide 'cc' pointing to gcc
        if [ -f "${GCC_DIR}/bin/gcc" ]; then
            echo "s none bin/cc=${GCC_DIR}/bin/gcc"
            _count=$((_count + 1))
        fi

        # --- Binutils (from ${PREFIX}/bin) —
        # Original g-prefixed names
        for _bin in gas gld gar gnm granlib gobjdump gobjcopy gstrip \
                    greadelf gsize gstrings gaddr2line gc++filt gelfedit ggprof; do
            if [ -f "${PREFIX}/bin/${_bin}" ]; then
                echo "s none bin/${_bin}=${PREFIX}/bin/${_bin}"
                _count=$((_count + 1))
            fi
        done

        # Standard GNU names (without the g- prefix) for convenience
        # as→gas, ld→gld, ar→gar, nm→gnm, ranlib→granlib, etc.
        for _pair in \
            "as=gas" \
            "ld=gld" \
            "ar=gar" \
            "nm=gnm" \
            "ranlib=granlib" \
            "objdump=gobjdump" \
            "objcopy=gobjcopy" \
            "strip=gstrip" \
            "readelf=greadelf" \
            "size=gsize" \
            "strings=gstrings" \
            "addr2line=gaddr2line" \
            "c++filt=gc++filt" \
            "elfedit=gelfedit" \
            "gprof=ggprof"; do
            _stdname="${_pair%%=*}"
            _realname="${_pair#*=}"
            if [ -f "${PREFIX}/bin/${_realname}" ]; then
                echo "s none bin/${_stdname}=${PREFIX}/bin/${_realname}"
                _count=$((_count + 1))
            fi
        done
    } > "${_stagedir}/prototype"
    echo "  Symlinks: ${_count}"

    # Create the package — we need a fake root for pkgmk since
    # it will try to verify the symlink targets exist. We create
    # a staging area with just the symlinks.
    _linkroot="${TMPDIR}/linkroot"
    rm -rf "${_linkroot}"
    mkdir -p "${_linkroot}/bin" "${_linkroot}/sbin"

    # Actually create the symlinks so pkgmk can find them
    grep '^s none' "${_stagedir}/prototype" | while IFS= read -r _sline; do
        _entry="${_sline#s none }"
        _lpath="${_entry%%=*}"
        _ltarget="${_entry#*=}"
        ln -sf "${_ltarget}" "${_linkroot}/${_lpath}" 2>/dev/null || true
    done

    rm -rf "${SPOOLDIR}"
    mkdir -p "${SPOOLDIR}"

    pkgmk -o -d "${SPOOLDIR}" -r "${_linkroot}" -f "${_stagedir}/prototype" 2>&1 || {
        echo "  ERROR: pkgmk failed for ${_code}"
        return 1
    }

    _pkgfile="${OUTPUT}/${_code}-${_ver}-1.sst-${SST_OS}-sparc.pkg"
    pkgtrans -s "${SPOOLDIR}" "${_pkgfile}" "${_code}" 2>&1 || {
        echo "  ERROR: pkgtrans failed for ${_code}"
        return 1
    }

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
    for f in ${GCC_SUBDIR}/bin/gcc ${GCC_SUBDIR}/bin/cpp ${GCC_SUBDIR}/bin/gcov \
             ${GCC_SUBDIR}/bin/gcc-ar ${GCC_SUBDIR}/bin/gcc-nm ${GCC_SUBDIR}/bin/gcc-ranlib; do
        [ -f "${PREFIX}/${f}" ] && echo "$f"
    done
    # Cross-name symlink
    [ -f "${GCC_DIR}/bin/${TARGET}-gcc-${GCC_VER}" ] && echo "${GCC_SUBDIR}/bin/${TARGET}-gcc-${GCC_VER}"
    [ -f "${GCC_DIR}/bin/${TARGET}-gcc" ] && echo "${GCC_SUBDIR}/bin/${TARGET}-gcc"
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
    if [ -d "${GCC_DIR}/man" ]; then
        find "${GCC_DIR}/man" -type f | sed "s|^${PREFIX}/||"
    fi
    if [ -d "${GCC_DIR}/info" ]; then
        find "${GCC_DIR}/info" -type f | sed "s|^${PREFIX}/||"
    fi
} > "${LISTS}/gcc"

# --- SSTlstdc: libstdc++ shared ---
{
    for f in lib/libstdc++.so lib/libstdc++.so.6 lib/libstdc++.so.6.0.20 lib/libstdc++.so.6.0.20-gdb.py; do
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

# --- SSTgcxx: GCC C++ ---
{
    for f in ${GCC_SUBDIR}/bin/g++ ${GCC_SUBDIR}/bin/c++; do
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

# --- SSTgftn: GCC Fortran ---
{
    [ -f "${GCC_DIR}/bin/gfortran" ] && echo "${GCC_SUBDIR}/bin/gfortran"
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

# --- SSTgobjc: GCC Objective-C ---
{
    [ -f "${PREFIX}/libexec/gcc/${TARGET}/${GCC_VER}/cc1obj" ] && echo "libexec/gcc/${TARGET}/${GCC_VER}/cc1obj"
    [ -f "${PREFIX}/libexec/gcc/${TARGET}/${GCC_VER}/cc1objplus" ] && echo "libexec/gcc/${TARGET}/${GCC_VER}/cc1objplus"
} > "${LISTS}/gcc-objc"

# --- SSTlgomp: libgomp ---
{
    for f in lib/libgomp.so lib/libgomp.so.1 lib/libgomp.so.1.0.0 lib/libgomp.a \
             lib/libitm.so lib/libitm.so.1 lib/libitm.so.1.0.0 \
             lib/libssp.so lib/libssp.so.0 lib/libssp.so.0.0.0 \
             lib/libsparcatomic.so lib/libsparcatomic.so.1 lib/libsparcatomic.so.1.3.0; do
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
P SSTlgcc  GCC runtime library
P SSTgmp    GNU Multiple Precision Arithmetic Library
P SSTmpfr   GNU Multiple Precision Floating-Point Library
P SSTmpc    GNU Multiple Precision Complex Library
EOF

cat > "${DEPS}/libstdcxx" << 'EOF'
P SSTlgcc  GCC runtime library
EOF

cat > "${DEPS}/libstdcxx-devel" << 'EOF'
P SSTlstdc  libstdc++ shared library
EOF

cat > "${DEPS}/gcc-cxx" << 'EOF'
P SSTgcc  GCC C compiler
P SSTlstdc  libstdc++ shared library
P SSTlstdd  libstdc++ headers and static library
EOF

cat > "${DEPS}/libgfortran" << 'EOF'
P SSTlgcc  GCC runtime library
EOF

cat > "${DEPS}/gcc-fortran" << 'EOF'
P SSTgcc  GCC C compiler
P SSTlgcc  GCC runtime library
P SSTlgfrt  GCC Fortran runtime library
EOF

cat > "${DEPS}/libobjc" << 'EOF'
P SSTlgcc  GCC runtime library
EOF

cat > "${DEPS}/gcc-objc" << 'EOF'
P SSTgcc  GCC C compiler
P SSTlgcc  GCC runtime library
P SSTlobjc  GCC Objective-C runtime library
EOF

cat > "${DEPS}/libgomp" << 'EOF'
P SSTlgcc  GCC runtime library
EOF

# ============================================================
# Generate postinstall scripts
# ============================================================

# Common postinstall for library packages:
# 1. Register INSTALL_ROOT/lib with the Solaris runtime linker (crle)
# 2. Ensure LD_LIBRARY_PATH is configured in /etc/profile.d
POSTINSTALL_LIB=${TMPDIR}/postinstall-lib
cat > "${POSTINSTALL_LIB}" << 'LIBPOSTEOF'
#!/bin/sh
LIBDIR="${BASEDIR}/lib"

# --- Runtime linker: add LIBDIR to default search path ---
if [ -x /usr/bin/crle ] && [ -d "$LIBDIR" ]; then
    CURRENT=$(/usr/bin/crle 2>/dev/null | grep "Default Library Path" | sed 's/.*:[	 ]*//')
    case "$CURRENT" in
        *"${LIBDIR}"*) ;; # already registered
        "")
            /usr/bin/crle -l "/usr/lib:${LIBDIR}" 2>/dev/null && \
                echo "Registered ${LIBDIR} with runtime linker" || true
            ;;
        *)
            /usr/bin/crle -l "${CURRENT}:${LIBDIR}" 2>/dev/null && \
                echo "Registered ${LIBDIR} with runtime linker" || true
            ;;
    esac
fi

# --- Login profile: LD_LIBRARY_PATH + PATH ---
PROFILE_DIR=/etc/profile.d
if [ -d "$PROFILE_DIR" ] || mkdir -p "$PROFILE_DIR" 2>/dev/null; then
    cat > "$PROFILE_DIR/sunstorm.sh" << 'PROFEOF'
# Sunstorm distribution environment setup
SST_ROOT=/opt/sst
if [ -d "$SST_ROOT/gcc/bin" ]; then
    PATH=$SST_ROOT/gcc/bin:$PATH
fi
if [ -d "$SST_ROOT/bin" ]; then
    PATH=$SST_ROOT/bin:$PATH
fi
if [ -d "$SST_ROOT/lib" ]; then
    LD_LIBRARY_PATH=$SST_ROOT/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
fi
export PATH LD_LIBRARY_PATH
PROFEOF
fi
LIBPOSTEOF

# Postinstall for GCC compiler package
POSTINSTALL_GCC=${TMPDIR}/postinstall-gcc
cat > "${POSTINSTALL_GCC}" << 'GCCPOSTEOF'
#!/bin/sh
# Register library path (GCC depends on libgmp, libmpfr, libmpc in BASEDIR/lib)
LIBDIR="${BASEDIR}/lib"
if [ -x /usr/bin/crle ] && [ -d "$LIBDIR" ]; then
    CURRENT=$(/usr/bin/crle 2>/dev/null | grep "Default Library Path" | sed 's/.*:[	 ]*//')
    case "$CURRENT" in
        *"${LIBDIR}"*) ;;
        "") /usr/bin/crle -l "/usr/lib:${LIBDIR}" 2>/dev/null || true ;;
        *)  /usr/bin/crle -l "${CURRENT}:${LIBDIR}" 2>/dev/null || true ;;
    esac
fi

# Configure PATH and LD_LIBRARY_PATH in login profile
PROFILE_DIR=/etc/profile.d
if [ -d "$PROFILE_DIR" ] || mkdir -p "$PROFILE_DIR" 2>/dev/null; then
    cat > "$PROFILE_DIR/sunstorm.sh" << 'PROFEOF'
# Sunstorm distribution environment setup
SST_ROOT=/opt/sst
if [ -d "$SST_ROOT/gcc/bin" ]; then
    PATH=$SST_ROOT/gcc/bin:$PATH
fi
if [ -d "$SST_ROOT/bin" ]; then
    PATH=$SST_ROOT/bin:$PATH
fi
if [ -d "$SST_ROOT/lib" ]; then
    LD_LIBRARY_PATH=$SST_ROOT/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
fi
export PATH LD_LIBRARY_PATH
PROFEOF
    echo "Sunstorm: PATH configured in $PROFILE_DIR/sunstorm.sh"
    echo "Run '. $PROFILE_DIR/sunstorm.sh' or log in again to activate."
fi
GCCPOSTEOF

# ============================================================
# Build all packages
# ============================================================
echo ""
echo "Building SVR4 packages..."
echo ""

make_pkg "SSTgmp"    "gmp - GNU Multiple Precision Arithmetic"      "6.1.2" "GMP arbitrary precision arithmetic library"  "${LISTS}/gmp"            "${DEPS}/gmp"       "${POSTINSTALL_LIB}"
make_pkg "SSTmpfr"   "mpfr - GNU Multiple Precision Floating-Point" "3.1.4" "MPFR multiple precision floating-point"       "${LISTS}/mpfr"           "${DEPS}/mpfr"      "${POSTINSTALL_LIB}"
make_pkg "SSTmpc"    "mpc - GNU Multiple Precision Complex"         "1.0.3" "MPC multiple precision complex arithmetic"    "${LISTS}/mpc"            "${DEPS}/mpc"       "${POSTINSTALL_LIB}"
make_pkg "SSTbinut"  "binutils - GNU binary utilities"              "2.32"  "GNU assembler, linker, and binary utilities"  "${LISTS}/binutils"       "${DEPS}/binutils"  ""
make_pkg "SSTlgcc"  "libgcc - GCC runtime library"                "${GCC_VER}" "GCC runtime library (libgcc_s.so)"       "${LISTS}/libgcc"         "${DEPS}/libgcc"    "${POSTINSTALL_LIB}"
make_pkg "SSTgcc"  "gcc - GNU C Compiler"                        "${GCC_VER}" "GCC C compiler, preprocessor, coverage"  "${LISTS}/gcc"            "${DEPS}/gcc"       "${POSTINSTALL_GCC}"
make_pkg "SSTlstdc"  "libstdc++ - C++ standard library"            "${GCC_VER}" "libstdc++.so.6 shared library"           "${LISTS}/libstdcxx"      "${DEPS}/libstdcxx" "${POSTINSTALL_LIB}"
make_pkg "SSTlstdd"  "libstdc++-devel - C++ headers and static lib" "${GCC_VER}" "C++ standard library headers and archives" "${LISTS}/libstdcxx-devel" "${DEPS}/libstdcxx-devel" ""
make_pkg "SSTgcxx"  "gcc-c++ - GCC C++ compiler"                  "${GCC_VER}" "GCC C++ compiler (g++)"                  "${LISTS}/gcc-cxx"        "${DEPS}/gcc-cxx"   ""
make_pkg "SSTlgfrt"  "libgfortran - Fortran runtime"               "${GCC_VER}" "GCC Fortran runtime library"             "${LISTS}/libgfortran"    "${DEPS}/libgfortran" "${POSTINSTALL_LIB}"
make_pkg "SSTgftn"  "gcc-fortran - GCC Fortran compiler"          "${GCC_VER}" "GCC Fortran compiler (gfortran)"         "${LISTS}/gcc-fortran"    "${DEPS}/gcc-fortran" ""
make_pkg "SSTlobjc"  "libobjc - Objective-C runtime"               "${GCC_VER}" "GCC Objective-C runtime library"         "${LISTS}/libobjc"        "${DEPS}/libobjc"   "${POSTINSTALL_LIB}"
make_pkg "SSTgobjc"  "gcc-objc - GCC Objective-C compiler"         "${GCC_VER}" "GCC Objective-C/C++ compiler"            "${LISTS}/gcc-objc"       "${DEPS}/gcc-objc"  ""
make_pkg "SSTlgomp"  "libgomp - OpenMP runtime"                    "${GCC_VER}" "GCC OpenMP parallel runtime library"     "${LISTS}/libgomp"        "${DEPS}/libgomp"   "${POSTINSTALL_LIB}"

# --- SSTlink: symlinks in /opt/sunstorm/bin ---
make_links_pkg

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
echo "  1. SSTgmp SSTbinut SSTlgcc"
echo "  2. SSTmpfr"
echo "  3. SSTmpc"
echo "  4. SSTgcc SSTlstdc SSTlgfrt SSTlobjc SSTlgomp"
echo "  5. SSTlstdd"
echo "  6. SSTgcxx SSTgftn SSTgobjc"
echo "  7. SSTlink  (symlinks in /opt/sunstorm/bin + PATH setup)"

# Cleanup
rm -rf "${TMPDIR}"
