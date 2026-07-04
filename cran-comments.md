# CRAN comments — rpic 0.6.1

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
  (`--offline -j 2`, at most 2 jobs).
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

## Submission tarball

Built with the vendored sources included:

```r
rextendr::vendor_crates(".")   # regenerates src/rust/vendor.tar.xz
```

then `R CMD build .` and `R CMD check --as-cran rpic_0.6.1.tar.gz`.

## Test environments

* local macOS (R 4.6, rustc stable)
* GitHub Actions ubuntu-latest (R release, rustc stable) — R CMD check runs
  against the vendored, offline build on every push/PR.
