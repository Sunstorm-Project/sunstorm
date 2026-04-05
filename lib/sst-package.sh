#!/bin/sh
# sst-package.sh — SVR4 package creation for Sunstorm
# Creates individual .pkg.Z files from a staging directory.
#
# Usage: . lib/sst-package.sh
#        sst_make_pkg <pkgdir> <stagedir> <outputdir>

. "$(dirname "$0")/../lib/sst-common.sh" 2>/dev/null || true

# Generate pkginfo from a package definition
# Args: pkgdir stagedir
sst_gen_pkginfo() {
    _pkgdir="$1"
    _stagedir="$2"
    _pkginfo="${_pkgdir}/pkginfo"

    if [ ! -f "$_pkginfo" ]; then
        echo "ERROR: $_pkginfo not found" >&2
        return 1
    fi

    # Copy pkginfo to staging
    cp "$_pkginfo" "${_stagedir}/pkginfo"

    # Add PSTAMP
    _pstamp="$(hostname)$(date '+%Y%m%d%H%M%S')"
    echo "PSTAMP=\"${_pstamp}\"" >> "${_stagedir}/pkginfo"
}

# Generate prototype file from staging contents
# Args: pkgdir stagedir
sst_gen_prototype() {
    _pkgdir="$1"
    _stagedir="$2"

    {
        echo "i pkginfo"
        [ -f "${_pkgdir}/depend" ] && echo "i depend" && cp "${_pkgdir}/depend" "${_stagedir}/depend"
        [ -f "${_pkgdir}/postinstall" ] && echo "i postinstall" && cp "${_pkgdir}/postinstall" "${_stagedir}/postinstall"
        [ -f "${_pkgdir}/preremove" ] && echo "i preremove" && cp "${_pkgdir}/preremove" "${_stagedir}/preremove"

        # Auto-generate from file list
        if [ -f "${_pkgdir}/files" ]; then
            # files list: one path per line, relative to BASEDIR
            while IFS= read -r _line; do
                case "$_line" in
                    \#*|"") continue ;;
                    d\ *) echo "$_line" ;;
                    *)
                        _fullpath="${_stagedir}/root${_line}"
                        if [ -d "$_fullpath" ]; then
                            echo "d none ${_line} 0755 root bin"
                        elif [ -L "$_fullpath" ]; then
                            _target=$(readlink "$_fullpath")
                            echo "s none ${_line}=${_target}"
                        elif [ -x "$_fullpath" ]; then
                            echo "f none ${_line} 0755 root bin"
                        else
                            echo "f none ${_line} 0644 root bin"
                        fi
                        ;;
                esac
            done < "${_pkgdir}/files"
        else
            # Auto-discover all files under root/
            cd "${_stagedir}/root" 2>/dev/null || return 1
            find . -type d | sed 's|^\.||' | while read -r _d; do
                [ -z "$_d" ] && continue
                echo "d none ${_d} 0755 root bin"
            done
            # Solaris 7's find emits duplicates (including directories)
            # when `-type f -o -type l` is used — run the two tests
            # separately for portability.
            { find . -type f; find . -type l; } | sed 's|^\.||' | sort -u | while read -r _f; do
                _full="${_stagedir}/root${_f}"
                if [ -L "$_full" ]; then
                    _target=$(readlink "$_full")
                    echo "s none ${_f}=${_target}"
                elif [ -x "$_full" ]; then
                    echo "f none ${_f} 0755 root bin"
                else
                    echo "f none ${_f} 0644 root bin"
                fi
            done
            cd - >/dev/null
        fi
    } > "${_stagedir}/prototype"
}

# Build SVR4 package
# Args: pkgdir stagedir outputdir
sst_make_pkg() {
    _pkgdir="$1"
    _stagedir="$2"
    _outputdir="$3"

    # Read package code from pkginfo
    _pkg=$(grep '^PKG=' "${_pkgdir}/pkginfo" | head -1 | sed 's/PKG="*\([^"]*\)"*/\1/')
    _ver=$(grep '^VERSION=' "${_pkgdir}/pkginfo" | head -1 | sed 's/VERSION="*\([^"]*\)"*/\1/')
    _name=$(grep '^NAME=' "${_pkgdir}/pkginfo" | head -1 | sed 's/NAME="*\([^"]*\)"*/\1/')

    echo "=== Building package: ${_pkg} ${_ver} ==="
    echo "    ${_name}"

    # Setup staging
    mkdir -p "${_stagedir}" "${_outputdir}"

    # Generate metadata
    sst_gen_pkginfo "$_pkgdir" "$_stagedir"
    sst_gen_prototype "$_pkgdir" "$_stagedir"

    # Build SVR4 package (on Solaris)
    if command -v pkgmk >/dev/null 2>&1; then
        _spooldir="${_stagedir}/spool"
        mkdir -p "$_spooldir"
        pkgmk -o -d "$_spooldir" -r "${_stagedir}/root" -f "${_stagedir}/prototype"
        _pkgstream="${_outputdir}/${_pkg}-${_ver}.sst-${SST_OS}-${SST_ARCH}.pkg"
        pkgtrans -s "$_spooldir" "$_pkgstream" "$_pkg"
        compress "$_pkgstream"
        echo "    Created: ${_pkgstream}.Z"
    else
        # Cross-build: create a tar-based package for later pkgmk on target
        echo "    NOTE: Not on Solaris — creating staging tarball"
        _tarball="${_outputdir}/${_pkg}-${_ver}.sst-${SST_OS}-${SST_ARCH}.tar.gz"
        tar czf "$_tarball" -C "${_stagedir}/root" .
        echo "    Created: ${_tarball}"
    fi

    echo "=== Done: ${_pkg} ==="
}
