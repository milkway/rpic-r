# rpic 0.11.3

Tracks the rpic engine from 0.6.2 to 0.11.3. The R functions and their
arguments are unchanged; everything below is reached through the pic source.

* New pic extensions, all opt-in: `canvas` (fixed page), per-string font
  attributes (`bold`, `italic`, `mono`, `font`, `fontsize`, `big`, `small`),
  `rotated` and `aligned` labels, colour literals `rgb(r, g, b)` and
  `0xRRGGBB`, variables and expressions in colour position, `thin`, and
  `link "<url>"` for clickable objects in SVG output.
* `animate` grew from three effects to a full set: `move`, `highlight`,
  `slide`, `morph`, `type`, `scramble` and `wiggle`, plus `out`, `repeat`,
  `yoyo`, `ease`, `stagger`, a partial `draw from ... to ...`, and
  `draggable` objects.
* `rpic_manifest()` bundles gain an `objects` array (id, kind, bounding box
  and source position of every drawn object) and, when `draggable` is used,
  an `interactions` array.
* Better compatibility with 'dpic': extension words such as `after`,
  `repeat` and `previous` no longer shadow identifiers, so sources that use
  them as variable or macro names compile.
* Recursive macro expansion is no longer exponential in its depth.
* Robustness: deeply nested input is rejected with a diagnostic instead of
  overflowing the stack, and `invalid_color` warnings carry a source
  position.
* Rust 1.88 or later is now required to build from source
  (`SystemRequirements`).

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
