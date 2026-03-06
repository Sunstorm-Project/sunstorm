#!/bin/ksh
# package-gcc11.sh — Create SVR4 package for GCC 11.4.0 standalone toolchain
#
# Runs on Solaris 7. Scans the installed GCC 11 tree under /opt/sst and
# creates a single self-contained SVR4 package (SSTgc11).
#
# Usage:
#   /bin/ksh package-gcc11.sh [output_dir]
#
# Prerequisites:
#   - GCC 11.4.0 installed in /opt/sst (from gcc11-solaris7-sparc.tar.gz)
#   - Package metadata in packages/gcc11/ (pkginfo, depend, postinstall, preremove)

set -e

SCRIPTDIR=$(cd "$(dirname "$0")" && pwd)
PKGMETA="${SCRIPTDIR}/packages/gcc"

OUTPUT="${1:-/tmp/sunstorm-packages}"
PREFIX="/opt/sst"
TARGET="sparc-sun-solaris2.7"
GCC_VER="11.4.0"
BINUTILS_VER="2.32"

TMPDIR=/tmp/sst-gcc11-pkg-$$
SPOOLDIR="${TMPDIR}/spool"

PKG_CODE="SSTgcc"
PKG_ARCH="sparc"

echo "============================================"
echo "  Sunstorm GCC 11 SVR4 Packager"
echo "  Install root : ${PREFIX}"
echo "  Output       : ${OUTPUT}"
echo "============================================"
echo ""

# --- Preflight ---
if [ "$(uname -s)" != "SunOS" ]; then
    echo "ERROR: Must run on Solaris (need pkgmk/pkgtrans)." >&2
    exit 1
fi
for tool in pkgmk pkgtrans gzip find; do
    if ! command -v $tool >/dev/null 2>&1; then
        echo "ERROR: Required tool '$tool' not found." >&2
        exit 1
    fi
done
if [ ! -d "${PREFIX}" ]; then
    echo "ERROR: Install root ${PREFIX} does not exist." >&2
    exit 1
fi
if [ ! -f "${PREFIX}/bin/gcc" ]; then
    echo "ERROR: GCC not found at ${PREFIX}/bin/gcc" >&2
    exit 1
fi
if [ ! -f "${PKGMETA}/pkginfo" ]; then
    echo "ERROR: Package metadata not found at ${PKGMETA}/pkginfo" >&2
    echo "       Make sure packages/gcc11/ directory is present." >&2
    exit 1
fi

mkdir -p "${OUTPUT}" "${TMPDIR}"

# ============================================================
# Build file list from installed tree
# ============================================================
echo "Scanning ${PREFIX} for GCC 11 files ..."

FILELIST="${TMPDIR}/files"
> "${FILELIST}"

# --- Compiler binaries ---
for f in gcc g++ cpp cc c++ sparc-sun-solaris2.7-gcc-11.4.0; do
    [ -f "${PREFIX}/bin/${f}" -o -L "${PREFIX}/bin/${f}" ] && echo "bin/${f}"
done >> "${FILELIST}"

# --- GNU binutils (prefixed) ---
for f in gas gld gar gnm granlib gobjdump gobjcopy gstrip \
         greadelf gsize gstrings gaddr2line; do
    [ -f "${PREFIX}/bin/${f}" -o -L "${PREFIX}/bin/${f}" ] && echo "bin/${f}"
done >> "${FILELIST}"

# --- Target binutils (used by GCC internally) ---
if [ -d "${PREFIX}/${TARGET}/bin" ]; then
    find "${PREFIX}/${TARGET}/bin" -type f -o -type l | \
        sed "s|^${PREFIX}/||" >> "${FILELIST}"
fi

# --- Compiler backends ---
LIBEXEC="libexec/gcc/${TARGET}/${GCC_VER}"
for f in cc1 cc1plus collect2 lto-wrapper; do
    [ -f "${PREFIX}/${LIBEXEC}/${f}" ] && echo "${LIBEXEC}/${f}"
done >> "${FILELIST}"
# Specs file in libexec
[ -f "${PREFIX}/${LIBEXEC}/specs" ] && echo "${LIBEXEC}/specs" >> "${FILELIST}"

# --- GCC internal libraries and CRT ---
GCCLIB="lib/gcc/${TARGET}/${GCC_VER}"
for f in libgcc.a libgcc_eh.a crtbegin.o crtbeginS.o crtend.o crtendS.o \
         crtfastmath.o crtp.o crtpg.o crt1.o crti.o crtn.o; do
    [ -f "${PREFIX}/${GCCLIB}/${f}" ] && echo "${GCCLIB}/${f}"
done >> "${FILELIST}"
# Specs file in lib
[ -f "${PREFIX}/${GCCLIB}/specs" ] && echo "${GCCLIB}/specs" >> "${FILELIST}"

# --- GCC internal headers ---
for hdir in include include-fixed; do
    [ -d "${PREFIX}/${GCCLIB}/${hdir}" ] && \
        find "${PREFIX}/${GCCLIB}/${hdir}" -type f | \
        sed "s|^${PREFIX}/||" >> "${FILELIST}"
done

# --- libsolcompat ---
if [ -d "${PREFIX}/lib/solcompat" ]; then
    find "${PREFIX}/lib/solcompat" -type f | \
        sed "s|^${PREFIX}/||" >> "${FILELIST}"
fi

# --- Sysroot values-*.o files (for C standard conformance modes) ---
if [ -d "${PREFIX}/lib/sysroot" ]; then
    find "${PREFIX}/lib/sysroot" -type f | \
        sed "s|^${PREFIX}/||" >> "${FILELIST}"
fi

# --- Deploy/verification script ---
[ -f "${PREFIX}/deploy-gcc11.sh" ] && echo "deploy-gcc11.sh" >> "${FILELIST}"

# De-duplicate and count
sort -u "${FILELIST}" > "${FILELIST}.sorted"
mv "${FILELIST}.sorted" "${FILELIST}"
FILECOUNT=$(wc -l < "${FILELIST}" | tr -d ' ')

echo "  Found ${FILECOUNT} files to package."
echo ""

# ============================================================
# Build prototype
# ============================================================
echo "Generating SVR4 prototype ..."

STAGEDIR="${TMPDIR}/stage"
mkdir -p "${STAGEDIR}"

# Copy package metadata
cp "${PKGMETA}/pkginfo" "${STAGEDIR}/pkginfo"
# Add PSTAMP and REV date
PSTAMP=$(hostname)$(date '+%Y%m%d%H%M%S')
REVDATE=$(date '+%Y.%m.%d')
# Update VERSION with current REV date
sed "s/REV=[0-9]*/REV=${REVDATE}/" "${STAGEDIR}/pkginfo" > "${STAGEDIR}/pkginfo.new"
mv "${STAGEDIR}/pkginfo.new" "${STAGEDIR}/pkginfo"
echo "PSTAMP=\"${PSTAMP}\"" >> "${STAGEDIR}/pkginfo"

for script in depend postinstall preremove preinstall postremove; do
    [ -f "${PKGMETA}/${script}" ] && cp "${PKGMETA}/${script}" "${STAGEDIR}/${script}"
done

{
    echo "i pkginfo"
    [ -f "${STAGEDIR}/depend" ] && echo "i depend"
    [ -f "${STAGEDIR}/postinstall" ] && echo "i postinstall"
    [ -f "${STAGEDIR}/preremove" ] && echo "i preremove"

    # Auto-generate directory entries
    while IFS= read -r _f; do
        case "$_f" in \#*|"") continue ;; esac
        _dir=$(dirname "$_f")
        [ -n "$_dir" ] && [ "$_dir" != "." ] && echo "$_dir"
    done < "${FILELIST}" | sort -u | while IFS= read -r _d; do
        # Walk up the path to ensure all parent directories are listed
        _walk="$_d"
        while [ -n "$_walk" ] && [ "$_walk" != "." ]; do
            echo "d none ${_walk} 0755 root bin"
            _walk=$(dirname "$_walk")
        done
    done | sort -u

    # File entries
    while IFS= read -r _f; do
        case "$_f" in \#*|"") continue ;; esac
        _full="${PREFIX}/${_f}"
        if [ -L "$_full" ]; then
            _target=$(ls -l "$_full" | sed 's/.*-> //')
            echo "s none ${_f}=${_target}"
        elif [ -x "$_full" ]; then
            echo "f none ${_f} 0755 root bin"
        elif [ -f "$_full" ]; then
            echo "f none ${_f} 0644 root bin"
        fi
    done < "${FILELIST}"
} > "${STAGEDIR}/prototype"

PROTO_FILES=$(grep -c '^f ' "${STAGEDIR}/prototype" 2>/dev/null || echo 0)
PROTO_DIRS=$(grep -c '^d ' "${STAGEDIR}/prototype" 2>/dev/null || echo 0)
PROTO_SYMS=$(grep -c '^s ' "${STAGEDIR}/prototype" 2>/dev/null || echo 0)
PROTO_INFO=$(grep -c '^i ' "${STAGEDIR}/prototype" 2>/dev/null || echo 0)

echo "  Prototype: ${PROTO_FILES} files, ${PROTO_DIRS} dirs, ${PROTO_SYMS} symlinks, ${PROTO_INFO} info files"
echo ""

# ============================================================
# Build SVR4 package
# ============================================================
echo "Running pkgmk ..."

mkdir -p "${SPOOLDIR}"

pkgmk -o \
    -d "${SPOOLDIR}" \
    -r "${PREFIX}" \
    -f "${STAGEDIR}/prototype" 2>&1

echo ""
echo "Running pkgtrans ..."

PKGFILE="${OUTPUT}/${PKG_CODE}-${GCC_VER}-${PKG_ARCH}.pkg"
pkgtrans -s "${SPOOLDIR}" "${PKGFILE}" "${PKG_CODE}" 2>&1

echo ""
echo "Compressing ..."

gzip -9f "${PKGFILE}"

PKGSIZE=$(ls -l "${PKGFILE}.gz" | awk '{print $5}')
PKGSIZE_H=$(ls -lh "${PKGFILE}.gz" | awk '{print $5}')

echo ""
echo "============================================"
echo "  Package created successfully!"
echo "============================================"
echo ""
echo "  File:    $(basename "${PKGFILE}.gz")"
echo "  Size:    ${PKGSIZE_H} (${PKGSIZE} bytes)"
echo "  Path:    ${PKGFILE}.gz"
echo ""
echo "  Install: gunzip -c ${PKGFILE}.gz | pkgadd -d - ${PKG_CODE}"
echo "           or: pkgadd -d ${PKGFILE}.gz all"
echo ""
echo "  Remove:  pkgrm ${PKG_CODE}"
echo ""
echo "  Verify:  pkginfo -l ${PKG_CODE}"
echo ""

# Cleanup
rm -rf "${TMPDIR}"
