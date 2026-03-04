# Sunstorm — A Package Distribution for Solaris 7 SPARC

**Sunstorm** (package prefix `SST`) is a software distribution for Solaris 7
(SunOS 5.7) on SPARC hardware. It provides modern GNU toolchain components
and custom applications as individual SVR4 packages with full dependency
tracking.

Sunstorm is designed to be installed alongside the base Solaris 7 system
without conflicting with Sun's bundled software or other third-party
distributions.

## Prefix

All Sunstorm packages install to:

```
/opt/sunstorm
```

Versioned compilers install to sub-prefixes:

```
/opt/sunstorm/gcc    — GCC
```

## Package Naming

SVR4 package names use the `SST` prefix:

| Package | SVR4 Code | Description |
|---------|-----------|-------------|
| gmp | `SSTgmp` | GMP 6.1.2 arithmetic library |
| mpfr | `SSTmpfr` | MPFR 3.1.4 floating-point library |
| mpc | `SSTmpc` | MPC 1.0.3 complex arithmetic |
| binutils | `SSTbinut` | GNU binutils 2.32 |
| gcc | `SSTgcc` | GCC C compiler |
| gcc-c++ | `SSTgcxx` | GCC C++ compiler |
| gcc-fortran | `SSTgftn` | GCC Fortran compiler |
| gcc-objc | `SSTgobjc` | GCC Objective-C/C++ |
| libgcc | `SSTlgcc` | libgcc_s.so runtime |
| libstdc++ | `SSTlstdc` | libstdc++.so.6 runtime |
| libstdc++-devel | `SSTlstdd` | libstdc++ headers + static lib |
| libgfortran | `SSTlgfrt` | Fortran runtime library |
| libobjc | `SSTlobjc` | Objective-C runtime library |
| libgomp | `SSTlgomp` | OpenMP runtime |
| solpkg | `SSTslpkg` | Solaris SPARC package manager |
| pizzafool | `SSTpzfol` | Motif/CDE pizza ordering app |
| sparccord | `SSTspcrd` | Motif/CDE Discord client |

## Building

Sunstorm packages are cross-compiled on an x86_64 Linux host targeting
`sparc-sun-solaris2.7` using the build infrastructure in `sparc-build-host`.

```sh
# Build all packages (from the cross-build Docker container):
./build-all.sh

# Build a single package:
./build-pkg.sh packages/gcc

# List all packages and their dependencies:
./sst-deps.sh
```

## Installing

Packages are distributed as gzipped SVR4 datastreams. Install with
[solpkg](https://github.com/julianwolfe/solpkg) or directly with `pkgadd`:

```sh
# Via solpkg (auto-resolves dependencies):
solpkg install gcc

# Manual install:
gunzip < SSTgcc-4.9.4-1.sst-sunos5.7-sparc.pkg.gz | pkgadd -n -d /dev/stdin all
```

## Repository

Pre-built packages are published as GitHub releases in the
[sunstorm-releases](https://github.com/julianwolfe/sunstorm-releases) repo.

## Dependency Map

```
SSTgmp    (standalone — GMP 6.1.2)
SSTbinut  (standalone — GNU binutils 2.32)
SSTlgcc  (standalone — libgcc_s.so.1)
  ↓
SSTmpfr   ← SSTgmp
  ↓
SSTmpc    ← SSTgmp, SSTmpfr
  ↓
SSTgcc  ← SSTbinut, SSTlgcc, SSTgmp, SSTmpfr, SSTmpc
  ↓
SSTlstdc  ← SSTlgcc
  ↓
SSTlstdd  ← SSTlstdc
  ↓
SSTgcxx  ← SSTgcc, SSTlstdc, SSTlstdd
  ↓
SSTlgfrt  ← SSTlgcc
  ↓
SSTgftn  ← SSTgcc, SSTlgcc, SSTlgfrt
  ↓
SSTlobjc  ← SSTlgcc
  ↓
SSTgobjc  ← SSTgcc, SSTlgcc, SSTlobjc
  ↓
SSTlgomp  ← SSTlgcc

SSTslpkg  (standalone — solpkg)
SSTpzfol  (standalone — pizzafool)
SSTspcrd  (standalone — sparccord)
```

## License

Individual packages retain their upstream licenses (GPL, LGPL, etc.).
Build infrastructure is MIT licensed.
