# rpic (development version)

## New features

* `rpic_geojson()` places a pic drawing on the Earth and returns it as a
  GeoJSON `FeatureCollection` (WGS84), through the engine's new
  `geopic-core` crate: registration by `geo_lon`/`geo_lat`/`geo_scale`/
  `geo_bearing` in the source (or the `anchor`, `scale`, `bearing`, `frame`
  arguments, which win) or by control points `<Label>_lon`/`<Label>_lat`;
  geometry densified so lines and circles are true on the ellipsoid. The
  registration and the warnings ride as attributes. `features` injects
  named places from R — a named list, a data frame or an `sf` object
  (centroid + bounding box) — that the source can use by name.
* `rpic_sf()` reads the same result into an `sf` data frame (EPSG:4326):
  simplestyle columns keep their names (`stroke`, `stroke-width`, `fill`,
  ...), `geopic:<name>` properties become `geopic.<name>`. `sf` is a
  suggested package only.
* Losses are never silent: one `rpic_geo_warning` (an `rpic_warning`) per
  kind; registration failures raise `rpic_geo_error` (an `rpic_error`) with
  `e$info$kind` and `e$info$hint`.
* `rpic_compile()` returns the engine's whole compile bundle as an R list —
  `svg`, `animations`, `diagnostics`, `warnings`, `objects`, `places`,
  `passthrough` and, with `scene = TRUE`, the scene — without JSON parsing
  in R.
* The knitr engine georeferences chunks with `geo = TRUE`: the chunk
  assigns its `rpic_sf()` result (or `rpic_geojson()` without `sf`) to a
  variable named by `geo.var` (default: the chunk label) for later R
  chunks, e.g. `ggplot2::geom_sf()`.
* New vignette `vignette("maps")`: the engine's four geo examples with
  `ggplot2`, features from `sf`'s `nc` dataset, and `mapgl`.
* `rpic_maplibre_layers()` returns the engine's MapLibre style-spec layers
  for a georeferenced drawing (engine 0.15.0, `geopic-core`'s `maplibre`
  module): the six layers rpic.dev's Maps page draws with — fills, solid and
  dashed strokes, dots, text, shape titles — with every size true to the
  ground, as R lists that serialise back to the engine's JSON. It takes an
  `rpic_geojson()` result, an `rpic_sf()` data frame or pic source.
* `rpic_mapgl()` adds a drawing to a `mapgl::maplibre()` or
  `mapgl::mapboxgl()` map: the engine's GeoJSON as source `"pic"`, the six
  layers and a fit to the drawing. `rpic_sf()` results keep the engine's
  GeoJSON text in a `"geojson"` attribute for both. `vignette("maps")`
  uses the helper; live maps are in the website article "Interactive maps
  with mapgl" (<https://milkway.github.io/rpic-r/articles/mapgl.html>), which is not shipped in the package.

## Bug fixes

* The knitr engine includes the rendered PNG as a figure again; with
  current knitr it printed the figure's path as text output.

## Engine 0.15.0

Tracks the rpic engine 0.15.0 (vendored crates `rpic-core`/`rpic-render`/
`geopic-core` 0.15.0; 0.15.0 adds the MapLibre layers above). The existing
R functions and their arguments are unchanged; rendering is byte-identical to 0.12.1 over the engine's whole corpus. What reaches R users
through the pic source and the JSON outputs:

* `rpic_scene()` gains a top-level `places` array — every `Label: position`
  statement as a named point in scene units, with its enclosing block and
  source span — and block items carry `span` (the outermost macro call that
  produced the block, or its `[`) and `call` (`name`, `args`). The scene
  format version stays 1 (additive).
* troff requests (a line with `.` in column 1 other than `.PS`/`.PE`, e.g.
  `.ft B`) are set aside as classic pic and dpic do instead of failing to
  parse.

# rpic 0.12.1

Tracks the rpic engine from 0.11.3 to 0.12.1 and adds one function.

* New `rpic_scene()`: the engine's **scene output** — the resolved draw list
  as versioned, device-independent JSON (final geometry in inches, curves as
  cubic Béziers or `flatten`ed polylines, style descriptors with hex colors,
  text with baseline anchors, every variable's final value under `vars`, and
  items in draw order carrying the SVG's stable `s<N>` ids). Parse it with
  `jsonlite::fromJSON()` and build map layers, TikZ output or editors on top
  of rpic's layout. Anything the SVG paints that the scene cannot represent
  raises a classed `rpic_warning` (engine kind `scene_unsupported`).
* Engine updates reaching R users: the whole corpus renders byte-identically
  to 0.11.3 (the 0.12.x line's changes are the opt-in scene export plus
  packaging); dependency refreshes (resvg 0.49, RaTeX 0.1.15) are likewise
  output-identical.

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
