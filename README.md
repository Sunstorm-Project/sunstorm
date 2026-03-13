# Sunstorm

A package distribution for Solaris 7 (SunOS 5.7) SPARC. Package prefix: `SST`.

Public repo: github.com/firefly128/sunstorm — v1.0.0 released.

Sunstorm is registry-only. This repo contains no package source code. It holds the packaging scripts, dependency manifest, and spm repository configuration. Pre-built SVR4 `.pkg` files are published as GitHub Releases.

## Install prefix

All Sunstorm packages install to `/opt/sst`.

## Installing packages

Packages are distributed as SVR4 datastreams. Install with [spm](https://github.com/firefly128/spm) (recommended) or directly with `pkgadd`:

```sh
# Via spm (resolves dependencies automatically):
spm install gcc
spm install bash coreutils grep sed make curl

# Manual install:
pkgadd -n -d SSTgcc-11.4.0-1.sst-sunos5.7-sparc.pkg all
```

Pre-built packages are published as [GitHub Releases](https://github.com/firefly128/sunstorm/releases). The `current` pre-release contains the latest build of every package.

The `solpkg-repo.conf` file configures the spm repository pointing at this GitHub repo's releases.

## Package list

### Core Libraries

| Package | SVR4 Code | Description |
|---------|-----------|-------------|
| libsolcompat | `SSTlsolc` | POSIX/C99/C11 compatibility shim for Solaris 7 |
| zlib | `SSTzlib` | Compression library |
| bzip2 | `SSTbz2` | Block-sorting compressor |
| xz | `SSTxz` | LZMA compression |
| ncurses | `SSTncurs` | Terminal handling library |
| readline | `SSTrdln` | Line editing library |
| pcre2 | `SSTpcre2` | Perl-compatible regular expressions |
| openssl | `SSTossl` | TLS/SSL and crypto library + CLI |

### Core Userland

| Package | SVR4 Code | Description |
|---------|-----------|-------------|
| bash | `SSTbash` | Bourne Again Shell |
| coreutils | `SSTcorut` | GNU core utilities |
| gawk | `SSTgawk` | Pattern scanning and processing |
| grep | `SSTgrep` | Pattern matching |
| sed | `SSTsed` | Stream editor |
| tar | `SSTtar` | Tape archiver |
| gzip | `SSTgzip` | Compression utility |
| less | `SSTless` | Terminal pager |
| patch | `SSTpatch` | Apply diffs |
| diffutils | `SSTdiffu` | File comparison |
| findutils | `SSTfindu` | File search utilities |
| make | `SSTmake` | GNU Make |
| m4 | `SSTm4` | Macro processor |

### Build Infrastructure

| Package | SVR4 Code | Description |
|---------|-----------|-------------|
| autoconf | `SSTaconf` | Configure script generator |
| automake | `SSTamake` | Makefile generator |
| libtool | `SSTltool` | Library build tool |
| pkgconf | `SSTpkgcf` | Package compiler/linker flag tool |
| bison | `SSTbison` | Parser generator |
| flex | `SSTflex` | Lexical analyzer generator |
| texinfo | `SSTtxinf` | Documentation format tools |

### GCC Toolchain

| Package | SVR4 Code | Description |
|---------|-----------|-------------|
| gcc (C) | `SSTgcc` | GCC 11.4.0 C compiler |
| gcc-c++ | `SSTgcxx` | GCC 11.4.0 C++ compiler |
| gcc-fortran | `SSTgftn` | GCC 11.4.0 Fortran compiler |
| gcc-objc | `SSTgobjc` | GCC 11.4.0 Objective-C compiler |
| binutils | `SSTbinut` | GNU assembler, linker, and tools |
| gmp | `SSTgmp` | GMP arbitrary-precision arithmetic |
| mpfr | `SSTmpfr` | MPFR floating-point library |
| mpc | `SSTmpc` | MPC complex arithmetic library |
| libgcc | `SSTlgcc` | libgcc_s.so runtime |
| libstdc++ | `SSTlstdc` | libstdc++.so.6 runtime |
| libstdc++-devel | `SSTlstdd` | libstdc++ headers + static lib |
| libgfortran | `SSTlgfrt` | Fortran runtime library |
| libobjc | `SSTlobjc` | Objective-C runtime library |
| libgomp | `SSTlgomp` | OpenMP runtime |

### Network / Crypto

| Package | SVR4 Code | Description |
|---------|-----------|-------------|
| curl | `SSTcurl` | URL transfer tool and library |
| wget | `SSTwget` | Network downloader |
| openssh | `SSTossh` | OpenSSH client and server |

### Development Essentials

| Package | SVR4 Code | Description |
|---------|-----------|-------------|
| expat | `SSTexpat` | XML parser library |
| libiconv | `SSTliconv` | Character encoding conversion |
| gettext | `SSTgtxt` | Internationalization library |
| perl | `SSTperl` | Perl interpreter |
| git | `SSTgit` | Distributed version control |
| vim | `SSTvim` | Vi IMproved text editor |
| screen | `SSTscrn` | Terminal multiplexer |

### Media Libraries

| Package | SVR4 Code | Description |
|---------|-----------|-------------|
| libpng | `SSTlpng` | PNG image library |
| libjpeg | `SSTljpeg` | JPEG image library |
| libutf8proc | `SSTlutf8` | Unicode processing library |

### Applications

| Package | SVR4 Code | Description |
|---------|-----------|-------------|
| spm | `SSTspm` | Sunstorm Package Manager |
| pizzafool | `SSTpzfol` | Motif/CDE pizza ordering app |
| sparccord | `SSTspcrd` | Motif/CDE Discord client |
| solpkg | `SSTslpkg` | Low-level SVR4 package utilities |
| prngd | `SSTprngd` | Pseudo-random number generator daemon (entropy for OpenSSL) |

## Dependency map

```
Foundation (no deps):
  SSTbinut  SSTlgcc  SSTgmp  SSTlsolc

Toolchain:
  SSTmpfr   <- SSTgmp
  SSTmpc    <- SSTgmp SSTmpfr
  SSTgcc    <- SSTbinut SSTlgcc SSTgmp SSTmpfr SSTmpc
  SSTlstdc  <- SSTlgcc
  SSTlstdd  <- SSTlstdc
  SSTgcxx   <- SSTgcc SSTlstdc SSTlstdd
  SSTlgfrt  <- SSTlgcc
  SSTlobjc  <- SSTlgcc

Core libraries:
  SSTzlib   <- SSTlsolc
  SSTbz2    <- SSTlsolc
  SSTxz     <- SSTlsolc
  SSTncurs  <- SSTlsolc
  SSTrdln   <- SSTlsolc SSTncurs
  SSTpcre2  <- SSTlsolc SSTzlib

Core userland / build infra:
  SSTbash   <- SSTlsolc SSTncurs SSTrdln
  SSTcorut  <- SSTlsolc
  SSTgrep   <- SSTlsolc SSTpcre2
  SSTaconf  <- SSTlsolc SSTm4
  SSTamake  <- SSTlsolc SSTaconf

Network / crypto:
  SSTossl   <- SSTlsolc SSTzlib
  SSTcurl   <- SSTlsolc SSTzlib SSTossl
  SSTwget   <- SSTlsolc SSTossl
  SSTossh   <- SSTlsolc SSTzlib SSTossl

Applications (standalone):
  SSTslpkg  SSTpzfol  SSTspcrd
```

## How packages are built

Packages are cross-compiled on an x86_64 Linux host using `ghcr.io/firefly128/sparc-toolchain:latest` (GCC 11.4.0 targeting `sparc-sun-solaris2.7`). The build pipeline lives in [sparc-build-host](https://github.com/firefly128/sparc-build-host).

Finalization — converting cross-compiled staging tarballs into SVR4 `.pkg` files using native `pkgmk`/`pkgtrans` — runs on a Solaris 7 QEMU VM.

The `build-packages.yml` workflow in sparc-build-host automates this two-stage process and uploads finished `.pkg` files to the `current` pre-release on this repo.

To package manually on Solaris:

```sh
./make-packages.sh [staging_dir] [output_dir]
```

## License

Individual packages retain their upstream licenses (GPL, LGPL, BSD, etc.).
Build and packaging infrastructure is MIT licensed.
