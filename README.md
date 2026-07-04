# rpic <a href="https://milkway.github.io/rpic-r/"><img src="man/figures/logo.svg" align="right" height="120" alt="rpic website" /></a>

<!-- badges: start -->
[![R-CMD-check](https://github.com/milkway/rpic-r/actions/workflows/R-CMD-check.yml/badge.svg)](https://github.com/milkway/rpic-r/actions/workflows/R-CMD-check.yml)
[![pkgdown](https://github.com/milkway/rpic-r/actions/workflows/pkgdown.yml/badge.svg)](https://milkway.github.io/rpic-r/)
[![CRAN status](https://www.r-pkg.org/badges/version/rpic)](https://CRAN.R-project.org/package=rpic)
[![GitHub release](https://img.shields.io/github/v/release/milkway/rpic-r)](https://github.com/milkway/rpic-r/releases)
[![License: BSD-2](https://img.shields.io/badge/license-BSD--2--Clause-blue.svg)](LICENSE)
<!-- badges: end -->

R bindings for [**rpic**](https://rpic.dev) — a Rust reimplementation of
Brian Kernighan's **pic** picture-drawing language. You describe a diagram
by *walking around a plane dropping primitives*; rpic renders it to
**SVG / PNG / PDF**, pure Rust, no system dependencies (no troff, no LaTeX,
no ImageMagick):

- **79 native circuit elements** — a from-scratch re-imagining of
  `circuit_macros` (`circuits = TRUE` or `copy "circuits"` in the source);
- **TeX math labels** typeset natively (`texlabels = TRUE`, KaTeX-grade via
  a pure-Rust engine);
- **structured diagnostics** — compile errors are classed conditions with
  exact positions and did-you-mean hints;
- a **knitr engine** for inline diagrams in R Markdown / Quarto.

The language, its extensions and a live playground are documented at
[rpic.dev](https://rpic.dev); this package wraps the same engine via
[extendr](https://extendr.rs/).

## Install

```r
# install.packages("remotes")
remotes::install_github("milkway/rpic-r")
```

Building from source requires a [Rust toolchain](https://rustup.rs)
(`cargo`/`rustc`). Release tarballs with vendored Rust dependencies (no
network needed at build time) are attached to each
[GitHub release](https://github.com/milkway/rpic-r/releases).

## Usage

```r
library(rpic)

rpic_svg('box "input"; arrow; box "process" fill 0.9; arrow; ellipse "output"')

# circuit library — two-terminal elements take two named points:
rpic_png('A:(0,0); B:(2,0)
resistor(A,B)', "circuit.png", scale = 2, circuits = TRUE)

# TeX math labels, typeset natively:
rpic_svg('box "$-\\frac{T}{2}$" fit', texlabels = TRUE)

# the full bundle: svg + animation manifest + diagnostics + warnings
jsonlite::fromJSON(rpic_manifest('box; animate last box with "pop"'))
```

### Errors you can point at

Compile failures raise a classed `rpic_error` condition carrying the
structured diagnostic — position (always relative to *your* source, even
with `circuits = TRUE`), kind, and a did-you-mean hint:

```r
tryCatch(
  rpic_svg("bxo", circuits = TRUE),
  rpic_error = function(e) list(line = e$info$line, hint = e$info$hint)
)
#> $line
#> [1] 1
#> $hint
#> [1] "did you mean `box`?"
```

`e$info$file` names a `copy` include when the problem is inside one
(`NA` means your own input).

### knitr / Quarto engine

```r
rpic::rpic_register_knitr()
```

then write pic code directly in a chunk:

````
```{rpic, circuits=TRUE, scale=2}
A:(0,0); B:(2,0)
resistor(A,B)
```
````

Chunk options: `circuits`, `texlabels`, `scale`.

## Develop

```r
devtools::load_all(".")      # compiles the Rust and loads the package
```

For an installable/CRAN-style tarball, the Rust dependencies are vendored:

```r
rextendr::vendor_crates(".")   # bundles crate sources into src/rust/vendor.tar.xz
R CMD build .
```

## Acknowledgments

pic was created by **Brian W. Kernighan**; `dpic` and `circuit_macros` are
**J. D. Aplevich**'s; `pikchr` is **D. Richard Hipp**'s. See
[ACKNOWLEDGMENTS](https://github.com/milkway/rpic-lang/blob/main/ACKNOWLEDGMENTS.md)
in the engine repository.

## License

BSD-2-Clause. Compiled Rust dependencies are acknowledged in
[`inst/AUTHORS`](inst/AUTHORS).
