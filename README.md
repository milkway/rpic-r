# rpic (R)

<!-- badges: start -->
[![R-CMD-check](https://github.com/milkway/rpic-r/actions/workflows/R-CMD-check.yml/badge.svg)](https://github.com/milkway/rpic-r/actions/workflows/R-CMD-check.yml)
[![License: BSD-2](https://img.shields.io/badge/license-BSD--2--Clause-blue.svg)](LICENSE)
<!-- badges: end -->

R bindings for [**rpic**](https://github.com/milkway/rpic-lang) — a Rust
reimplementation of the **pic** picture-drawing language, rendering diagrams to
**SVG / PNG / PDF**, with a native circuit-element library and a **knitr** engine
for inline diagrams in R Markdown / Quarto.

This package wraps the Rust crates
[`rpic-core`](https://crates.io/crates/rpic-core) /
[`rpic-render`](https://crates.io/crates/rpic-render) via
[extendr](https://extendr.rs/). The engine is developed in the
[rpic-lang](https://github.com/milkway/rpic-lang) monorepo.

## Install

Requires a [Rust toolchain](https://rustup.rs) (`cargo`/`rustc`) to build.

```r
# install.packages("remotes")
remotes::install_github("milkway/rpic-r")
```

## Usage

```r
library(rpic)

rpic_svg('box "hi"; arrow; circle "x"')
rpic_png('A:(0,0); B:(2,0)\nresistor(A,B)', "circuit.png", scale = 2, circuits = TRUE)
rpic_pdf('box "hi"', "out.pdf")

# TeX math labels, exactly like `rpic -t`:
rpic_svg('box "$-\\\\frac{T}{2}$" fit', texlabels = TRUE)

# svg + animation manifest + diagnostics + structured warnings:
jsonlite::fromJSON(rpic_manifest('box; animate last box with "pop"'))
```

Compile errors are classed `rpic_error` conditions carrying the structured
diagnostic — position (relative to *your* source, even with
`circuits = TRUE`), kind, and a did-you-mean hint:

```r
tryCatch(
  rpic_svg("bxo", circuits = TRUE),
  rpic_error = function(e) list(line = e$info$line, hint = e$info$hint)
)
#> $line [1] 1      $hint "did you mean `box`?"
```

### knitr engine

```r
rpic::rpic_register_knitr()
```

then in an R Markdown / Quarto document:

````
```{rpic, circuits=TRUE, scale=2}
A:(0,0); B:(2,0)
resistor(A,B)
```
````

## Develop

```r
devtools::load_all(".")      # compiles the Rust and loads the package
```

For an installable/CRAN-ready tarball, the Rust dependencies are vendored:

```r
rextendr::vendor_pkgs(".")   # bundles crate sources into src/rust/vendor.tar.xz
R CMD build .
```

## License

BSD-2-Clause.
