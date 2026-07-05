# CRAN comments — rpic 0.6.2 (resubmission)

## Changes since the 2026-07-05 pretest

The pretest failures traced to one process error on our side: the submitted
tarball was built **without the vendored Rust sources**, so cargo downloaded
crates (Debian WARNING "Downloads Rust crates"), built with unbounded
parallelism (Debian NOTE, CPU 6.7x elapsed) and failed on Windows during
that online build. Fixed structurally:

* `tools/config.R` now **fails closed**: a CRAN build without
  `src/rust/vendor.tar.xz` stops with a clear error, so this class of
  submission cannot happen again. `-j 2 --offline` is always applied for
  CRAN builds.
* With the offline vendored build in place, the Rust library compiles
  cleanly on win-builder. A residual spurious failure remained in the
  optional wrapper-regeneration step (`cargo run --bin document`, debug
  profile); CRAN builds now **skip wrapper regeneration entirely** and use
  the pre-generated `R/extendr-wrappers.R` shipped in the tarball
  (developers still regenerate under `NOT_CRAN`).
* This tarball ships the vendored sources and was verified on win-builder
  (R-devel) before resubmission.

About the "possibly misspelled words" NOTE: *Kernighan* is a proper name
(Brian W. Kernighan, the author of pic); *natively* and *reimplementation*
are intended English words.

## R CMD check results

0 errors | 0 warnings | 1 note

* New submission.

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

The source tarball exceeds the usual size guideline because of the vendored
Rust sources (`src/rust/vendor.tar.xz`), which the CRAN Rust policy requires
for offline builds. The vendored archive is xz-compressed and contains only
crate sources.

## Test environments

* local macOS (R 4.6, rustc stable)
* win-builder R-devel (offline vendored build)
* GitHub Actions ubuntu-latest (R release, rustc stable) — R CMD check runs
  against the vendored, offline build on every push/PR.
