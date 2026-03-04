#!/bin/sh
# make-packages.sh — Create SVR4 .pkg.gz files from split staging
#
# This script takes the per-package staging directories created by
# split-staging.sh and produces proper SVR4 datastream packages.
#
# On Solaris: uses pkgmk + pkgtrans to create real .pkg.gz files
# On Linux:   creates tar.gz archives (for later pkgmk on target)
#
# Usage: ./make-packages.sh [staging_dir] [output_dir]
#   staging_dir: directory with per-package subdirs (default: ./staging)
#   output_dir:  where to write .pkg.gz files (default: ./output)

set -e

BASEDIR="$(cd "$(dirname "$0")" && pwd)"
STAGING="${1:-${BASEDIR}/staging}"
OUTPUT="${2:-${BASEDIR}/output}"

. "${BASEDIR}/lib/sst-common.sh"

echo "============================================"
echo "  Sunstorm SVR4 Package Builder"
echo "  Staging: ${STAGING}"
echo "  Output:  ${OUTPUT}"
echo "============================================"
echo ""

if [ ! -d "${STAGING}" ]; then
    echo "ERROR: Staging directory not found: ${STAGING}"
    echo "Run split-staging.sh first to create per-package staging directories."
    exit 1
fi

mkdir -p "${OUTPUT}"

# Detect if we're on Solaris (real SVR4 tools available)
ON_SOLARIS=false
if [ "$(uname -s)" = "SunOS" ] && command -v pkgmk >/dev/null 2>&1; then
    ON_SOLARIS=true
    echo "Running on Solaris — will create native SVR4 packages."
else
    echo "Not on Solaris — will create tar.gz staging archives."
    echo "Transfer these to Solaris and run: make-packages.sh --finalize"
fi
echo ""

# --finalize mode: create .pkg.gz from pre-staged tar.gz archives
if [ "$1" = "--finalize" ]; then
    if [ "${ON_SOLARIS}" != "true" ]; then
        echo "ERROR: --finalize requires Solaris with pkgmk/pkgtrans."
        exit 1
    fi
    shift
    TARDIR="${1:-.}"
    echo "Finalizing packages from tarballs in ${TARDIR}..."
    for tarball in "${TARDIR}"/*.sst-*.tar.gz; do
        [ -f "$tarball" ] || continue
        _base=$(basename "$tarball" .tar.gz)
        _tmpdir="/tmp/sst-finalize-$$/${_base}"
        mkdir -p "$_tmpdir"
        
        echo "  Extracting: $(basename "$tarball")"
        cd "$_tmpdir"
        /usr/tgcware/bin/gtar xzf "$tarball" 2>/dev/null || tar xf "$tarball"
        
        # Generate .pkg.gz from extracted staging
        _create_svr4_pkg "$_tmpdir" "${OUTPUT}"
        rm -rf "$_tmpdir"
    done
    echo ""
    echo "Finalized packages in: ${OUTPUT}/"
    ls -lh "${OUTPUT}"/*.pkg.gz 2>/dev/null
    exit 0
fi

# ============================================================
# Generate prototype file from package root
# ============================================================
gen_prototype() {
    _pkgdir="$1"     # directory containing pkginfo, depend, root/
    _proto="${_pkgdir}/prototype"
    
    {
        echo "i pkginfo"
        [ -f "${_pkgdir}/depend" ] && echo "i depend"
        [ -f "${_pkgdir}/postinstall" ] && echo "i postinstall"
        [ -f "${_pkgdir}/preremove" ] && echo "i preremove"
        
        if [ -d "${_pkgdir}/root" ]; then
            cd "${_pkgdir}/root"
            # Directories
            find . -type d | sort | while IFS= read -r _d; do
                _d=$(echo "$_d" | sed 's|^\./||')
                [ -z "$_d" ] && continue
                echo "d none /${_d} 0755 root bin"
            done
            # Files and symlinks
            find . \( -type f -o -type l \) | sort | while IFS= read -r _f; do
                _f=$(echo "$_f" | sed 's|^\./||')
                _full="${_pkgdir}/root/${_f}"
                if [ -L "$_full" ]; then
                    _target=$(ls -l "$_full" | sed 's/.*-> //')
                    echo "s none /${_f}=${_target}"
                elif [ -x "$_full" ]; then
                    echo "f none /${_f} 0755 root bin"
                else
                    echo "f none /${_f} 0644 root bin"
                fi
            done
            cd - >/dev/null
        fi
    } > "$_proto"
}

# ============================================================
# Create SVR4 package from a staged package directory
# ============================================================
create_svr4_pkg() {
    _pkgstage="$1"
    _outdir="$2"
    
    _pkg=$(grep '^PKG=' "${_pkgstage}/pkginfo" | head -1 | sed 's/PKG="*\([^"]*\)"*/\1/')
    _ver=$(grep '^VERSION=' "${_pkgstage}/pkginfo" | head -1 | sed 's/VERSION="*\([^"]*\)"*/\1/' | cut -d, -f1)
    _name=$(grep '^NAME=' "${_pkgstage}/pkginfo" | head -1 | sed 's/NAME="*\([^"]*\)"*/\1/')
    _filename=$(sst_pkgfile "$_pkg" "$_ver" "1")
    
    echo "=== ${_pkg} ${_ver} ==="
    echo "    ${_name}"
    
    # Add PSTAMP
    _pstamp="$(hostname 2>/dev/null || echo sunstorm)$(date '+%Y%m%d%H%M%S' 2>/dev/null || echo 0)"
    grep -v '^PSTAMP=' "${_pkgstage}/pkginfo" > "${_pkgstage}/pkginfo.new"
    echo "PSTAMP=\"${_pstamp}\"" >> "${_pkgstage}/pkginfo.new"
    mv "${_pkgstage}/pkginfo.new" "${_pkgstage}/pkginfo"
    
    # Generate prototype
    gen_prototype "${_pkgstage}"
    
    _filecount=$(grep -c '^f ' "${_pkgstage}/prototype" 2>/dev/null || echo 0)
    echo "    Files: ${_filecount}"
    
    if [ "${ON_SOLARIS}" = "true" ]; then
        # Real SVR4 package creation
        _spooldir="/tmp/sst-spool-$$"
        mkdir -p "${_spooldir}"
        
        pkgmk -o \
            -d "${_spooldir}" \
            -r "${_pkgstage}/root" \
            -f "${_pkgstage}/prototype" \
            2>&1 || { echo "    ERROR: pkgmk failed for ${_pkg}"; return 1; }
        
        _pkgstream="${_outdir}/${_pkg}-${_ver}-1.sst-${SST_OS}-${SST_ARCH}.pkg"
        pkgtrans -s "${_spooldir}" "${_pkgstream}" "${_pkg}" \
            2>&1 || { echo "    ERROR: pkgtrans failed for ${_pkg}"; return 1; }
        
        gzip -9f "${_pkgstream}"
        _size=$(ls -lh "${_pkgstream}.gz" | awk '{print $5}')
        echo "    Created: $(basename "${_pkgstream}.gz") (${_size})"
        
        rm -rf "${_spooldir}"
    else
        # Create tar.gz for later pkgmk on Solaris
        _tarball="${_outdir}/${_pkg}-${_ver}-1.sst-${SST_OS}-${SST_ARCH}.tar.gz"
        tar czf "$_tarball" -C "${_pkgstage}" .
        _size=$(ls -lh "$_tarball" | awk '{print $5}')
        echo "    Created: $(basename "$_tarball") (${_size})"
    fi
    
    echo ""
}

# ============================================================
# Process all packages
# ============================================================
TOTAL=0
BUILT=0

for _pkgdir in "${STAGING}"/*/; do
    [ -f "${_pkgdir}/pkginfo" ] || continue
    TOTAL=$((TOTAL + 1))
    
    if create_svr4_pkg "$_pkgdir" "${OUTPUT}"; then
        BUILT=$((BUILT + 1))
    fi
done

echo "============================================"
echo "  Packages built: ${BUILT}/${TOTAL}"
echo "  Output: ${OUTPUT}/"
echo "============================================"

if [ "${ON_SOLARIS}" != "true" ]; then
    echo ""
    echo "To create real SVR4 packages, transfer the archives to Solaris and run:"
    echo "  ./make-packages.sh --finalize <tarball_dir>"
fi
