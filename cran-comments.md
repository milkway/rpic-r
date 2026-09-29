# CRAN comments — rpic 0.11.3 (update)

This is an update of rpic 0.6.2 (on CRAN since 2026-07-15, all check flavors
OK). It tracks the upstream engine from 0.6.2 to 0.11.3; the R API is
unchanged. See NEWS.md.

* The engine now uses Rust `let` chains, so the minimum Rust version rises
  to 1.88. `SystemRequirements` states `rustc (>= 1.88.0)` and
  `tools/msrv.R` enforces it at configure time. The CRAN check machines
  currently report rustc 1.92 to 1.98.
* `inst/AUTHORS` is regenerated from the new dependency graph
  (`data-raw/authors.R`, 181 crates).

## R CMD check results

0 errors | 0 warnings | 1 note

* Size of tarball: 15.7 MB, from the vendored Rust sources (see below).

## Rust code (CRAN policy compliance)

The package statically links compiled Rust code via the extendr framework:

* `SystemRequirements: Cargo (Rust's package manager), rustc` is declared;
  `tools/msrv.R` verifies the toolchain and reports `cargo`/`rustc` versions
  during configure.
* All crate dependencies are fetched from crates.io by version (the engine
  crates `rpic-core`/`rpic-render` are published there) and **vendored** into
  `src/rust/vendor.tar.xz`; on CRAN the build runs **offline**
  (`--offline -j 2`, at most 2 jobs) and fails closed if the vendored
  sources are missing.
* Authorship/copyright of the vendored crates is acknowledged in
  `Authors@R` (`cph`) and itemized in `inst/AUTHORS` (crate, version,
  license, authors); full license texts ship inside the vendored sources.
* Build leftovers (`.cargo`, `vendor/`, `target/`) are removed by the
  Makevars cleanup targets.

## Package size

The source tarball (15.7 MB; 0.6.2 was 13.9 MB) exceeds the usual size
guideline because of the vendored Rust sources (`src/rust/vendor.tar.xz`), which the CRAN Rust policy requires
for offline builds. The vendored archive is xz-compressed and contains only
crate sources.

## Test environments

* local macOS (R 4.6, rustc stable)
* win-builder R-devel (offline vendored build), before submission
* GitHub Actions ubuntu-latest (R release, rustc stable) — R CMD check runs
  against the vendored, offline build on every push/PR.
