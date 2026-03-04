#!/bin/sh
# sst-deps.sh — Sunstorm dependency resolver
# Maps all package dependencies for the distribution.
#
# Usage: ./sst-deps.sh [pkgname]
#        ./sst-deps.sh          — show all packages and deps
#        ./sst-deps.sh gcc      — show install order for gcc

set -e
BASEDIR="$(cd "$(dirname "$0")" && pwd)"

# Load all depend files and build the dependency graph
load_deps() {
    for _depfile in "${BASEDIR}"/packages/*/depend; do
        [ -f "$_depfile" ] || continue
        _pkgdir=$(dirname "$_depfile")
        _pkg=$(grep '^PKG=' "${_pkgdir}/pkginfo" | head -1 | sed 's/PKG="*\([^"]*\)"*/\1/')
        _ver=$(grep '^VERSION=' "${_pkgdir}/pkginfo" | head -1 | sed 's/VERSION="*\([^"]*\)"*/\1/')
        _name=$(grep '^NAME=' "${_pkgdir}/pkginfo" | head -1 | sed 's/NAME="*\([^"]*\)"*/\1/')

        _deps=""
        while IFS= read -r _line; do
            case "$_line" in
                P\ *) _deps="${_deps} $(echo "$_line" | awk '{print $2}')" ;;
            esac
        done < "$_depfile"

        echo "${_pkg}|${_ver}|${_name}|${_deps}"
    done
}

# Resolve install order for a package (topological sort)
resolve_order() {
    _target="$1"
    _graph="$2"
    _resolved=""
    _seen=""

    _resolve_recurse() {
        _node="$1"
        case " $_seen " in *" $_node "*) return ;; esac
        _seen="$_seen $_node"

        # Find deps for this node
        _ndeps=$(echo "$_graph" | grep "^${_node}|" | head -1 | cut -d'|' -f4)
        for _dep in $_ndeps; do
            _resolve_recurse "$_dep"
        done

        case " $_resolved " in *" $_node "*) ;; *) _resolved="$_resolved $_node" ;; esac
    }

    _resolve_recurse "$_target"
    echo "$_resolved"
}

# Main
_allpkgs=$(load_deps)

if [ -z "$1" ]; then
    echo "=== Sunstorm Package Catalog ==="
    echo ""
    printf "%-12s %-12s %-40s %s\n" "PACKAGE" "VERSION" "DESCRIPTION" "DEPENDS"
    printf "%-12s %-12s %-40s %s\n" "-------" "-------" "-----------" "-------"
    echo "$_allpkgs" | while IFS='|' read -r _p _v _n _d; do
        [ -z "$_p" ] && continue
        printf "%-12s %-12s %-40s %s\n" "$_p" "$_v" "$_n" "$_d"
    done
else
    _target="$1"
    # Allow short names: gcc -> SSTgcc
    case "$_target" in SST*) ;; *) _target="SST${_target}" ;; esac

    echo "Install order for ${_target}:"
    _order=$(resolve_order "$_target" "$_allpkgs")
    _i=1
    for _pkg in $_order; do
        _info=$(echo "$_allpkgs" | grep "^${_pkg}|" | head -1)
        _ver=$(echo "$_info" | cut -d'|' -f2)
        _name=$(echo "$_info" | cut -d'|' -f3)
        printf "  %d. %-12s %-12s %s\n" "$_i" "$_pkg" "$_ver" "$_name"
        _i=$((_i + 1))
    done
fi
