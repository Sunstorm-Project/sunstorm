# Sunstorm — A Package Distribution for Solaris 7 SPARC

**Sunstorm** (package prefix `SST`) is a software distribution for Solaris 7
(SunOS 5.7) on SPARC hardware. It provides modern GNU toolchain components,
core userland utilities, and libraries as individual SVR4 packages with full
dependency tracking.

Sunstorm is designed to be installed alongside the base Solaris 7 system
without conflicting with Sun's bundled software or other third-party
distributions.

## Prefix

All Sunstorm packages install to:

```
/opt/sst
```

## Package Naming

SVR4 package names use the `SST` prefix:

### Core Libraries

| Package | SVR4 Code | Version | Description |
|---------|-----------|---------|-------------|
| libsolcompat | `SSTlsolc` | 1.0.0 | POSIX/C99 compatibility shim for Solaris 7 |
| zlib | `SSTzlib` | 1.3.1 | Compression library |
| bzip2 | `SSTbz2` | 1.0.8 | Block-sorting compressor |
| xz | `SSTxz` | 5.4.6 | LZMA compression |
| ncurses | `SSTncurs` | 6.4 | Terminal handling library |
| readline | `SSTrdln` | 8.2 | Line editing library |
| pcre2 | `SSTpcre2` | 10.42 | Perl-compatible regular expressions |
| openssl | `SSTossl` | 1.1.1w | TLS/SSL and crypto library + CLI |

### Core Userland

| Package | SVR4 Code | Version | Description |
|---------|-----------|---------|-------------|
| bash | `SSTbash` | 5.2.21 | Bourne Again Shell |
| coreutils | `SSTcorut` | 9.4 | GNU core utilities (ls, cp, etc.) |
| gawk | `SSTgawk` | 5.3.0 | Pattern scanning and processing |
| grep | `SSTgrep` | 3.11 | Pattern matching |
| sed | `SSTsed` | 4.9 | Stream editor |
| tar | `SSTtar` | 1.35 | Tape archiver |
| gzip | `SSTgzip` | 1.13 | Compression utility |
| less | `SSTless` | 643 | Terminal pager |
| patch | `SSTpatch` | 2.7.6 | Apply diffs |
| diffutils | `SSTdiffu` | 3.10 | File comparison |
| findutils | `SSTfindu` | 4.9.0 | File search utilities |

### Build Infrastructure

| Package | SVR4 Code | Version | Description |
|---------|-----------|---------|-------------|
| make | `SSTmake` | 4.4.1 | GNU Make |
| m4 | `SSTm4` | 1.4.19 | Macro processor |
| autoconf | `SSTaconf` | 2.72 | Configure script generator |
| automake | `SSTamake` | 1.16.5 | Makefile generator |
| libtool | `SSTltool` | 2.4.7 | Library build tool |
| pkgconf | `SSTpkgcf` | 2.1.0 | Package compiler/linker flag tool |

### Network / Crypto

| Package | SVR4 Code | Version | Description |
|---------|-----------|---------|-------------|
| curl | `SSTcurl` | 8.6.0 | URL transfer tool and library |
| wget | `SSTwget` | 1.21.4 | Network downloader |

### GCC Toolchain

| Package | SVR4 Code | Version | Description |
|---------|-----------|---------|-------------|
| gcc | `SSTgcc` | 11.4.0 | GCC C/C++/Fortran/ObjC standalone toolchain |
| binutils | `SSTbinut` | 2.32 | GNU assembler, linker, and tools |
| gmp | `SSTgmp` | 6.1.2 | GMP arithmetic library |
| mpfr | `SSTmpfr` | 3.1.4 | MPFR floating-point library |
| mpc | `SSTmpc` | 1.0.3 | MPC complex arithmetic |
| libgcc | `SSTlgcc` | 11.4.0 | libgcc_s.so runtime |
| libstdc++ | `SSTlstdc` | 11.4.0 | libstdc++.so.6 runtime |
| libstdc++-devel | `SSTlstdd` | 11.4.0 | libstdc++ headers + static lib |
| libgfortran | `SSTlgfrt` | 11.4.0 | Fortran runtime library |
| libobjc | `SSTlobjc` | 11.4.0 | Objective-C runtime library |
| libgomp | `SSTlgomp` | 11.4.0 | OpenMP runtime |

### Applications

| Package | SVR4 Code | Description |
|---------|-----------|-------------|
| spm | `SSTspm` | Sunstorm Package Manager |
| pizzafool | `SSTpzfol` | Motif/CDE pizza ordering app |
| sparccord | `SSTspcrd` | Motif/CDE Discord client |

## Building

Sunstorm packages are cross-compiled on an x86_64 Linux host targeting
`sparc-sun-solaris2.7` using the build infrastructure in `sparc-build-host`.

```sh
# Build all packages (from the cross-build Docker container):
./build-all.sh

# List all packages and their dependencies:
./sst-deps.sh
```

## Installing

Packages are distributed as compressed SVR4 datastreams (`.pkg.Z`). Install with
[spm](https://github.com/firefly128/spm) or directly with `pkgadd`:

```sh
# Via spm (auto-resolves dependencies):
spm install gcc
spm install bash coreutils grep sed make curl

# Manual install:
uncompress SSTgcc-11.4.0-1.sst-sunos5.7-sparc.pkg.Z
pkgadd -n -d SSTgcc-11.4.0-1.sst-sunos5.7-sparc.pkg all
```

## Repository

Pre-built packages are published as
[GitHub releases](https://github.com/firefly128/sunstorm/releases) on this repo.

The `solpkg-repo.conf` file configures the GitHub-based package repository
that `spm` uses for dependency resolution and downloads.

## Dependency Map

```
Foundation (no deps):
  SSTbinut  SSTlgcc  SSTgmp  SSTlsolc

Toolchain deps:
  SSTmpfr   ← SSTgmp
  SSTmpc    ← SSTgmp, SSTmpfr
  SSTgcc    ← SSTbinut, SSTlgcc, SSTgmp, SSTmpfr, SSTmpc

GCC runtime libs:
  SSTlstdc  ← SSTlgcc
  SSTlstdd  ← SSTlstdc
  SSTlgfrt  ← SSTlgcc
  SSTlobjc  ← SSTlgcc
  SSTlgomp  ← SSTlgcc

Core libraries:
  SSTzlib   ← SSTlsolc
  SSTbz2    ← SSTlsolc
  SSTxz     ← SSTlsolc
  SSTncurs  ← SSTlsolc
  SSTrdln   ← SSTlsolc, SSTncurs
  SSTpcre2  ← SSTlsolc, SSTzlib

Core userland:
  SSTbash   ← SSTlsolc, SSTncurs, SSTrdln
  SSTcorut  ← SSTlsolc
  SSTgawk   ← SSTlsolc, SSTrdln
  SSTgrep   ← SSTlsolc, SSTpcre2
  SSTsed    ← SSTlsolc
  SSTtar    ← SSTlsolc
  SSTgzip   ← SSTlsolc
  SSTless   ← SSTlsolc, SSTncurs
  SSTpatch  ← SSTlsolc
  SSTdiffu  ← SSTlsolc
  SSTfindu  ← SSTlsolc

Build infrastructure:
  SSTmake   ← SSTlsolc
  SSTm4     ← SSTlsolc
  SSTaconf  ← SSTlsolc, SSTm4
  SSTamake  ← SSTlsolc, SSTaconf
  SSTltool  ← SSTlsolc
  SSTpkgcf  ← SSTlsolc

Network / Crypto:
  SSTossl   ← SSTlsolc, SSTzlib
  SSTcurl   ← SSTlsolc, SSTzlib, SSTossl
  SSTwget   ← SSTlsolc, SSTossl

Applications (standalone):
  SSTslpkg  SSTpzfol  SSTspcrd
```

## License

Individual packages retain their upstream licenses (GPL, LGPL, etc.).
Build infrastructure is MIT licensed.
