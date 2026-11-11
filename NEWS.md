# rpic (development version)

## API

The API moves towards tidyverse style before the next CRAN release: one
object for the source, pipe-first verbs, snake_case columns, data frames.

* `pic(src, circuits = NULL, texlabels = NULL)` wraps pic source in an
  `rpic_source` object (the source string with its `circuits` and
  `texlabels` options as attributes). Left `NULL`, the options are detected
  from the source as the rpic Studio does: `circuits` when it uses a
  circuit element (`resistor(A,B)`, a bare `ground`, ...) or says
  `copy "circuits"`, `texlabels` when a string label is entirely `$...$`.
  `print()` shows a summary and, interactively, opens the drawing in the
  viewer; `format()` returns the summary; in knitr a visible `pic()` is drawn
  as the chunk's figure (`knit_print()`, registered for knitr when it is
  installed; figures are named by content, so several per chunk never
  collide).
* Every `rpic_*()` function takes a `pic()` or a string first, so drawings
  read as pipes: `pic(src) |> rpic_png("a.png")`,
  `pic(src) |> rpic_compile(scene = TRUE)`, `pic(src) |> rpic_sf()`. Given a
  `pic()`, its `circuits`/`texlabels` are the defaults; `circuits` and
  `texlabels` now default to `NULL` (= the `pic()`'s setting, `FALSE` for a
  string — unchanged for existing code).
* `rpic_objects()`, `rpic_places()` and `rpic_warnings()` return the compile
  bundle's tables as plain data frames, one row per object, place or
  warning: `id`, `kind`, source span, `bbox_x0`/`bbox_y0`/`bbox_x1`/
  `bbox_y1` (`NA` without extent) and `link` for objects; `label`, `x`, `y`,
  `block` and span for places; the diagnostic fields for warnings (also the
  `"warnings"` attribute of an `rpic_geojson()`/`rpic_sf()` result). They
  take a `pic()`, a string or an `rpic_compile()` result.
* **Breaking (development version only — never on CRAN):** `rpic_sf()`
  columns are snake_case: every `:` and `-` of a GeoJSON property name
  becomes `_` — `geopic.kind` → `geopic_kind`, `geopic.font_size` →
  `geopic_font_size`, `stroke-width` → `stroke_width`, `fill-opacity` →
  `fill_opacity`, ... `rpic_sf_names()` is the documented mapping, with the
  full vocabulary table. The GeoJSON text (and so the MapLibre layers) keeps
  the engine's names.
* `add_rpic(map, x, ..., before = NULL, text_scale = 1, font = "style",
  fit = TRUE)` is the
  mapgl adder, map first like mapgl's own `add_*()` verbs:
  `maplibre() |> add_rpic(pic(src))`. `rpic_mapgl()` stays as an alias (the
  same function).
* `rpic_layers(x)` returns the `ggplot2` layers that draw a georeferenced
  drawing as pic drew it — `ggplot() + rpic_layers(x)`, alone or over a
  basemap: shapes through `geom_sf()` with their fills and strokes
  (`linewidth = NULL` uses pic's own widths), texts as labels justified and
  turned as pic placed them (`geopic_anchor` → `hjust`/`vjust`,
  `geopic_rotation` → `angle`, so `"2 km" above` sits above its line), and
  `coord_sf(clip = "off")`. `x` is an `rpic_sf()` data frame or pic source.
* `autoplot()` (`ggplot2`) of a georeferenced `pic()` is `rpic_layers()` on a
  blank theme.
* `vignette("maps")` opens with a three-line quick start, shows what
  `rpic_sf()` returns column by column, tells pic's `scale`, `geo_scale` and
  text sizes apart, adds a `geo_bearing` example (a pitch laid at 55°) and
  draws every figure on the longitude/latitude grid with its labels placed
  as pic placed them.
* Vignettes, the mapgl article, README and examples are written with `pic()`
  and `|>`; the reference index is grouped as Compile and export · Drawing
  data · Maps · knitr.

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
* `rpic_sf()` reads the same result into an `sf` data frame (EPSG:4326),
  one snake_case column per property (`stroke`, `stroke_width`, `fill`,
  `geopic_kind`, ...; see API above). `sf` is a suggested package only.
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
* `add_rpic()` (named `rpic_mapgl()` earlier in this development cycle;
  that name stays as an alias) adds a drawing to a `mapgl::maplibre()` or
  `mapgl::mapboxgl()` map: the engine's GeoJSON as source `"pic"`, the six
  layers and a fit to the drawing. `rpic_sf()` results keep the engine's
  GeoJSON text in a `"geojson"` attribute for both. `vignette("maps")`
  uses the helper; live maps are in the website article "Interactive maps
  with mapgl" (<https://milkway.github.io/rpic-r/articles/mapgl.html>), which is not shipped in the package.
* `rpic_maplibre_layers()` and `add_rpic()` gain `text_scale` (engine
  0.16.0's layer option): it multiplies every label's font size, a number
  in (0, 16], default 1 (unchanged output). Strokes and dots keep their
  ground sizes. Out of range or not a number: an `rpic_geo_error` with
  `e$info$kind == "invalid_options"`.
* `add_rpic()` gains `font`: the drawing's labels (`pic-text`,
  `pic-title`) use the style's own font by default (`"style"`: the most
  common upright Regular/Medium `text-font` stack among its symbol layers —
  CARTO's positron: Montserrat Medium, Open Sans Regular, ...). The engine's
  "Noto Sans Regular", as a glyph server like CARTO's serves it, has other
  vertical metrics, and a label placed `above` a line sat on it. `"spec"`
  keeps the engine's font; a character vector is an explicit stack. An
  unreadable style keeps the engine's font, without a warning of its own.
* `add_rpic()` gains `before`: `"labels"` puts the drawing's shapes
  (`pic-fill`, `pic-stroke`, `pic-stroke-dashed`, `pic-dot`) under the
  basemap's labels — before the style's layer `labels`, else at the start
  of its trailing label block (the first layer after the last non-`symbol`
  layer; not the first `symbol` layer, which in CARTO's positron is
  `waterway_label`, below roads and buildings) — while the drawing's own labels (`pic-text`,
  `pic-title`) stay on top, the rule of the engine's JavaScript
  `attach()`; a layer id inserts before that layer; `NULL` (the default)
  appends as before. A style given as a URL is fetched once to find the
  layer; when it cannot be read, a warning, and the layers go on top.

## Bug fixes

* The knitr engine includes the rendered PNG as a figure again; with
  current knitr it printed the figure's path as text output.

## Engine 0.19.0

Tracks the rpic engine 0.19.0 (vendored crates 0.19.0). What reaches R users:

* A label's face reaches the map. `"Marco Zero" bold`, `"Porto" italic`,
  `"8080" mono` and `font "Georgia"` travel as `geopic:font_weight`,
  `geopic:font_style` and `geopic:font_family` (`rpic_sf()` columns
  `geopic_font_weight`, `geopic_font_style`, `geopic_font_family`, present
  only when a label sets them), and the `text-font` of
  `rpic_maplibre_layers()` picks a Bold / Italic stack from them.
* `add_rpic(font = "style")` takes the bold, italic and bold italic stacks
  from the style's own symbol layers (the body font when the style has
  none), and `font` also accepts
  `list(regular =, bold =, italic =, bold_italic =)`. `mono` and
  `font "..."` labels are drawn in the body family on the map.
* `rpic_layers()` / `autoplot()` draw bold and italic labels with the
  matching `fontface`, and `mono` labels in the `"mono"` family.

## Engine 0.18.0

Tracks the rpic engine 0.18.0 (vendored crates 0.18.0). What reaches R users:

* A text object takes colour the dpic way: `"note" shaded "gray"` fills the
  glyphs (`outlined` strokes them, `colored` both). `rpic_scene()` text lines
  carry `color`/`stroke` when set; `rpic_sf()`/`rpic_geojson()` are unchanged.
* A free text of several lines keeps every line at 11 pt one em apart (they
  were squeezed before), and a `"Name" "sub" small` stack keeps the name at
  11 pt. A repeated size word keeps its last value (`box wid 1 wid 2` is 2 in).
* The engine repo now ships an Agent Skill (`skills/rpic`) that draws
  diagrams, circuits and maps with rpic; its map recipes use this package.

## Engine 0.17.1

Tracks the rpic engine 0.17.1 (vendored crates 0.17.1): a fix in macro
substitution so a `"$n"` label inside a library macro keeps the library's
source position (it surfaced as a user position before); no R-visible
change beyond `rpic_objects()` reporting the right `file`/`end_col` for
such labels.

## Engine 0.17.0

Tracks the rpic engine 0.17.0 (vendored crates `rpic-core`/`rpic-render`/
`geopic-core` 0.17.0). Nothing changes in what reaches R users: the
release carries the engine's embedder additions (`CompileOptions.preludes`,
`places[].block` in the `--json` bundle) and the JS MapLibre module's
`before = "labels"`/`font = "style"` rules, which `add_rpic()` already
implemented on the R side in the previous entry.

## Engine 0.16.0

Tracks the rpic engine 0.16.0 (vendored crates `rpic-core`/`rpic-render`/
`geopic-core` 0.16.0). What reaches R users:

* Blank rows of a label stack are kept in `geopic:text` (`box "" "below"`
  gives `"\nbelow"`), so a map draws "below" one row under the centre, as
  the SVG does; the `pic-text`/`pic-title` layers set `text-line-height`
  to 1 and pad a trailing empty row so MapLibre keeps it.
* Scene (`rpic_scene()`, `rpic_compile(scene = TRUE)`): each text line
  carries `row`, its row in the label stack, and the item `text_rows`, the
  stack's height; blocks made by a macro call carry `call$raw_args`, each
  argument as written (`1e-9` stays `1e-9`) with its source position.
* Labels on flat macro calls: `R1: resistor(A, B)` names the group of
  objects the call draws, like a block (`R1.n`, `R1.start`), when the
  macro body could not take a label before (it starts with assignments,
  a label or a control statement). Sources that compiled before render
  the same.
* troff passthrough: a `+` line right after a passthrough line continues
  it (the bundle's `passthrough` entry gains `end_line`).

## Engine 0.15.1

Tracks the rpic engine 0.15.1 (vendored crates `rpic-core`/`rpic-render`/
`geopic-core` 0.15.1; 0.15.0 added the MapLibre layers above). The existing
R functions and their arguments are unchanged; rendering is
byte-identical to 0.12.1 over the engine's whole corpus. What reaches R
users through the pic source and the JSON outputs:

* `rpic_scene()` gains a top-level `places` array — every `Label: position`
  statement as a named point in scene units, with its enclosing block and
  source span — and block items carry `span` (the outermost macro call that
  produced the block, or its `[`) and `call` (`name`, `args`). The scene
  format version stays 1 (additive).
* A shape with text (`box "Marco Zero"`) gains a `title` point feature at
  the centre of its text: in `rpic_sf()` a row with `geopic_kind ==
  "title"`, `geopic_id` `"<id>:title"` and `geopic_for` naming the shape;
  arrowheads no longer repeat the shape's `title`/`geopic_text`. The
  `pic-title` MapLibre layer draws these points (a box's title was drawn
  twice when the box straddled a map tile boundary). The scene's text
  items gain `text_center` (additive).
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
