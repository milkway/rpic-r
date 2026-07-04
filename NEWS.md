# rpic 0.6.2

* Track rpic 0.6.2 (the 2026-07 audit series): always-valid SVG for negative
  dimensions, canvas bounds that contain arrowheads and math fragments,
  dpic-parity fixes for `chop`/`continue`/dead `for` bodies, and structured
  eval-phase diagnostics with include attribution.
* Internal: the option builder is resilient to additive engine option fields.

# rpic 0.6.1

* Track rpic 0.6.1 (`rpic-core`/`rpic-render` from crates.io; previously 0.1.0).
* New `texlabels` argument on `rpic_svg()`, `rpic_png()`, `rpic_pdf()` and
  `rpic_manifest()`, and as a knitr chunk option: fully `$...$`-delimited
  labels are typeset as TeX math, natively (the math renderer is now
  registered — it previously was not, so math labels fell back to literal
  text).
* `circuits = TRUE` is now a compile option instead of prepending the library
  to the source: compile-error positions stay relative to your own input.
  The library can also be loaded in-source with `copy "circuits"`.
* Structured errors: compile failures are raised as a classed `rpic_error`
  condition; `e$info` holds the diagnostic (`message`, `line`, `col`,
  `end_col`, `file`, `kind`, `found`, `expected`, `hint`).
* `rpic_manifest()` bundles now include a `warnings` array with structured
  compiler warnings for accepted-but-ignored input.

# rpic 0.1.0

* First public release: `rpic_svg()`, `rpic_png()`, `rpic_pdf()`,
  `rpic_manifest()`, the knitr engine (`rpic_register_knitr()`), and the
  native circuit-element library (`circuits = TRUE`).
