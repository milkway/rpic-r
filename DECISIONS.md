# Decisions — rpic-r

Design decisions of the R package that are not obvious from the code. The
engine's own decisions (S1–S11 scene, G1–G8 geopic) live in
`milkway/rpic-lang`'s `DECISIONS.md`.

## D1 — Maps go through one native call; no JSON parsing in R (2026-11-07)

`rpic_geojson()` calls one shim, `rpic_geojson_(src, circuits, texlabels,
options_json)`, which returns the FeatureCollection as text and the
warnings and the registration already as R lists. The R side never parses
JSON, so `rpic_geojson()` needs no new dependency (jsonlite stays a
Suggests for examples/tests only). The options travel as a JSON object with
the keys of the engine's wasm `compile_geo` (frame, anchor, scale, bearing,
features, flatten, view_scale, screen_classes); R writes it by hand from
values it has already validated — finite numbers, pic-label feature names,
one of two frame words — so nothing needs escaping. The shim re-checks the
labels (second fence). `rpic_compile()` follows the same rule: the engine's
bundle JSON is converted to R in Rust (`value.rs`: objects → named lists,
homogeneous scalar arrays → atomic vectors, `null` → `NA`). serde_json and
serde were already in the dependency tree; adding them as direct deps cost
nothing.

## D2 — Host features: the bindings' two passes, done in Rust (2026-11-07)

The engine needs a label to exist in the source to use it as a control
point, so features the source only *uses* (`arrow from Recife to Olinda`)
must be injected, as the Python and JS bindings do: compile once with
placeholder places to learn which names the source defines itself (those
are control points of its own geometry), register with them, project the
others to canvas positions through that registration, prepend them as
places (or invisible boxes spanning the feature's bbox) and georeference
again with all features. Unlike Python (where it is Python code around
native calls), the R binding does it inside the shim (`geo.rs`), so the
whole round trip is one `.Call`. Diagnostic positions are re-based onto the
caller's source (a position inside the injected lines gets
`file = "features"`), including the `line:col:` prefix of the readable
message, which the Python binding leaves untouched.

## D3 — Features alone may register the drawing (R-only, 2026-11-07)

In the Python and JS bindings, a source with neither an anchor nor control
points of its own fails with `no_registration` even when every name it
uses is a host feature (pass 1 has nothing to place them by). rpic-r
instead anchors pass 1 at the first injected feature, with the declared
(or default) `geo_scale`/`geo_bearing`; pass 2 then registers by the
features themselves, which land exactly where pass 1 put them, so the
declared scale keeps meaning "how large pic's own lengths (arrowheads,
offsets, text) are on the ground". This turns an error into the obvious
result (`rpic_sf("arrow from Ashe to Wake", features = nc)`) and changes
nothing for inputs that already worked. Worth proposing upstream.

## D4 — Surface details (2026-11-07)

* `frame = c("enu", "mercator")` follows the R idiom, but an *omitted*
  `frame` passes nothing, so the source's `geo_frame` stays in force (the
  usual `match.arg()` would silently override it with `"enu"`).
* `rpic_geojson()` gains `name_col = "name"` (last argument) for `sf`
  features; the brief's other names are unchanged.
* Warnings: one R warning per distinct kind, message
  `"<kind> (<n> warnings), first: <message>"`, class
  `c("rpic_geo_warning", "rpic_warning", "warning", "condition")`, with
  `kind`, `count` and `info` (the warnings of that kind) fields; all
  warnings in the `"warnings"` attribute as well.
* `rpic_sf()` reads the GeoJSON with `sf::st_read()` (GDAL's GeoJSON
  driver, always present in sf) and restores the simplestyle names that
  `st_read()` makes syntactic (`stroke.width` → `stroke-width`);
  `geopic:<name>` becomes `geopic.<name>`.
* `sf` features: point = `sf::st_centroid()` (spherical under s2 for
  lon/lat data — the Python binding takes the planar centroid in degrees;
  the difference is negligible at county scale), extent = `sf::st_bbox()`;
  other CRSs are transformed to EPSG:4326 first.
* knitr `geo = TRUE` chunks emit no figure (the drawing is meant for the
  map that follows) and take their geo options with a `geo.` prefix —
  `scale` is already the PNG raster scale of ordinary chunks. The result
  is assigned into `knitr::knit_global()` — the pattern of knitr's own
  `sql` engine (`output.var`); the environment is taken into a variable
  first so R CMD check does not misread it as an assignment to the global
  environment (it is the knitting environment, which is only `globalenv()`
  when the user knits there).

## D5 — Maps vignette pre-rendered (2026-11-07)

Like the other vignettes, `maps.Rmd` has `eval = FALSE` chunks and embeds
figures produced by `data-raw/vignette-figures.R` (PNG via ggplot2 + sf,
~100 KB in total). Vignette builds stay instant and independent of sf/GDAL
on CRAN machines.

## D6 — MapLibre layers converted in Rust; one-element arrays stay lists (2026-11-07)

`rpic_maplibre_layers()` calls one shim, `rpic_maplibre_layers_(fc_json)`,
which runs `geopic_core::maplibre::layers_json()` and converts the result
with `value.rs` (D1) — no JSON parsing in R. The layers are not read by R
but handed back to a JSON serialiser (htmlwidgets, `auto_unbox = TRUE`), so
the converter has a second mode, `to_robj_arrays()`: a homogeneous array
becomes an atomic vector only from two elements up. A one-element array
(`["zoom"]`, `["geometry-type"]`) would otherwise be a length-1 vector that
`auto_unbox` writes as a scalar — breaking the expression in MapLibre — so
it stays a list. The tests pin that `jsonlite::toJSON(auto_unbox = TRUE)`
of the R layers reproduces the engine's six snapshots
(`examples/geo/maplibre/*.layers.json`; numbers within 1e-9 relative). Each
layer's keys come in reading order (`id`, `type`, `source`, `filter`,
`layout`, `paint`) instead of serde_json's alphabetical order.

## D7 — The map gets the engine's GeoJSON text, not a re-serialised sf (2026-11-07)

The layers read the GeoJSON property names (`geopic:kind`,
`stroke-width`) and test presence with `has` (a box without `fill` has no
`fill` key). `mapgl::add_source()` accepts only an `sf` (or a URL) and
re-serialises it with `geojsonsf`: the columns come out as `geopic.kind`,
absent values as `null` (so `has` would be true and unfilled boxes would
paint black), the dash object as a string and coordinates rounded to 9
decimals — measured on the radius example. So:

* `rpic_sf()` keeps the `rpic_geojson()` result it was read from in an
  attribute `"geojson"` (with the row count, `n_features`), and
  `rpic_maplibre_layers()`/`rpic_mapgl()` use that text. An `sf` whose row
  count no longer matches is an error; edited columns are not seen
  (documented). `[.sf` keeps the attribute, hence the row check.
* `rpic_mapgl()` registers the source in the widget itself — the entry
  `add_source()` would write (`id`, `type = "geojson"`, `data`,
  `generateId = TRUE`, appended to `map$x$sources`) with the engine's text
  as `data`, classed `"json"` so htmlwidgets writes it verbatim. That
  relies on mapgl's widget payload shape (mapgl 0.4.6, maplibre and
  mapboxgl widgets alike); the tests check it. Shiny proxies are refused.
* The layers go through mapgl's generic `add_layer(map, id, type, source,
  paint, layout, filter)` — mapgl has one, so no per-type adders and no
  mapping of paint/layout arguments.
* `fit = TRUE` uses `mapgl::fit_bounds()` with the bbox of the collection's
  coordinates (computed in Rust, `rpic_geojson_bbox_()`), 48 px padding and
  `maxZoom = 19`, the engine's JS `attach()` fit. (Without the padding the
  callout fitted edge to edge and its box title showed twice: an engine
  bug — the title was placed once per tile the polygon crossed — fixed in
  engine 0.15.1 by title point features.)

## D8 — The mapgl page is a pkgdown article, evaluated (2026-11-07)

Unlike D5, the mapgl page runs its chunks (when mapgl is installed): the
point is the interactive widget, which cannot be pre-rendered as a
picture. But a self-contained widget inlines maplibre-gl and mapgl's other
JavaScript — the rendered HTML is ~2.8 MB — and as a package vignette it
grew the CRAN tarball from ~14 MB to 16.8 MB. So it lives in
`vignettes/articles/mapgl.Rmd`, a pkgdown article: built and published on
the website (https://milkway.github.io/rpic-r/articles/mapgl.html),
excluded from the tarball by `.Rbuildignore` (`^vignettes/articles$`).
`vignette("maps")` keeps a short unevaluated `rpic_mapgl()` snippet and
links to the article; the help pages link to it too. Without mapgl the
article's chunks are shown unevaluated with a note.

## D9 — `text_scale` goes to the engine; `before` is resolved in R (2026-11-07)

Engine 0.16.0 answered the request behind both arguments (its DECISIONS
G11) and fixed the signature: `rpic_mapgl(map, x, ..., before = NULL,
text_scale = 1, fit = TRUE)`.

* **`text_scale` is a layer option, not R arithmetic.** It travels as JSON
  text, `{"text_scale": k}`, to the shim `rpic_maplibre_layers_(fc_json,
  opts_json)` → `geopic_core::maplibre::layers_json_with`. The scale lives
  inside the engine's sizing (it moves the upper `text-size` zoom stop so
  labels stay under MapLibre's 255 px), so scaling the R lists afterwards
  would not give the CLI's `--text-scale` output; the test pins the R
  layers at 1.5 to a fixture made by the v0.16.0 binary. The engine
  validates the range ((0, 16], `invalid_options`); R checks only what it
  must to write a JSON number — a single finite number — and raises the
  same `rpic_geo_error`/`invalid_options` otherwise (`Inf` and `NaN`
  have no JSON spelling).
* **`before` is placement, a property of the map**, so it stays out of the
  specs and is resolved by `rpic_mapgl()` with the JS `attach()` rule: only
  the four geometry layers get mapgl's `add_layer(before_id =)`; `pic-text`
  and `pic-title` are appended on top (the engine's first cut moved all
  six and buried the drawing's own labels). `"labels"` = a layer whose id
  is `labels`, else the first `symbol` layer, looked up among the style's
  layers and then the layers already added to the map. The JS reads
  `map.getStyle()` in the browser; R builds the widget before any browser
  exists, so it reads `map$x$style` — a list as is (its `layers` may be a
  data frame, as `jsonlite::fromJSON()` simplifies it), an http(s) URL
  fetched with `jsonlite` (10 s timeout, `.fetch_style()`, mocked in the
  tests) and memoised per URL for the session, so the maps of one document
  download a style once. The layers already added to the map are
  consulted first and also when the style cannot be read (the JS
  `map.getLayer('labels')` / `getStyle()` see them too); layers without an
  id are never a target. The alternative — resolving in the widget's JavaScript — would
  need a hook into mapgl's init that mapgl does not offer. When the style
  cannot be read (offline, `mapbox://`, mapboxgl()'s `NULL` default, a list
  without `layers`, no jsonlite), `"labels"` warns and appends; an
  explicit id is then used as given with a warning that it could not be
  checked (MapLibre drops a layer whose `beforeId` is missing at runtime;
  when the style *can* be read a missing id warns and appends, like the JS
  `console.warn`). An id among the map's own added layers needs no fetch.

## D10 — Drawing data are plain data frames (2026-11-07)

`rpic_objects()`, `rpic_places()` and `rpic_warnings()` return a plain
`data.frame`, never a tibble — not even when tibble is installed. The class
of a result must not depend on what else happens to be in the library
(a test, a CRAN check machine and a user would see different printing and
different `[` semantics: `df[, "kind"]` is a vector for a data.frame, a
one-column tibble for a tibble), and the package keeps zero Imports.
`tibble::as_tibble(rpic_objects(p))` is one call for those who want it.
The columns are fixed per function and always present — a drawing with
nothing to report is a zero-row frame with the same columns and types — so
code written against them does not branch on emptiness. Absent fields are
`NA` (the package idiom); source positions are integers; `bbox` (engine
`{x, y, w, h}` in viewBox units, y down) is split into corners
`bbox_x0, bbox_y0, bbox_x1, bbox_y1` so it filters and joins without list
columns. `places$block` is the engine's enclosing block path when the
bundle carries one; engine 0.16.0's bundle does not (its `places` records
have no `block` key), so the column is `NA` for now — kept so the shape does
not change when the engine adds it. For `rpic_geojson()`/`rpic_sf()`
results `rpic_warnings()` tabulates their `"warnings"` attribute (the geo
vocabulary: `kind`, `message`, `hint`, `id`, span) instead of compiling.

## D11 — `pic()`: a classed string, `NULL` defaults, Studio detection (2026-11-07)

* **Representation.** An `rpic_source` is the source as a character scalar
  with class `rpic_source` and logical attributes `circuits`/`texlabels`.
  It is still `is.character()`, so a `pic()` passed to code that expects a
  string keeps working; `as.character()` drops the class and attributes.
* **Defaults.** `circuits`/`texlabels` on every `rpic_*()` function default
  to `NULL`: the `pic()`'s setting, else `FALSE`. `missing()` was the
  alternative, but it breaks as soon as a wrapper passes the argument on;
  `NULL` composes. A plain string keeps `FALSE`, so code written for CRAN's
  0.12.1 renders byte-identically. An explicit argument always wins over
  the object.
* **Detection** follows the Studio (`rpic-app/apps/web/src/lib/detect.ts`):
  `circuits` = a call `name(` / `name (` of one of the 80 public macros of
  the engine's `circuits.pic`, outside strings and comments, or a
  `copy "circuits"` line (`circuits = TRUE` alongside it is harmless — the
  library only defines macros, and the SVG is identical); `texlabels` = a
  string literal that is entirely `$...$` after trimming. The macro list is
  a constant in `R/source.R` — refresh it when the engine adds elements.
  Detection is a guess, so it only sets defaults and is overridable both in
  `pic()` and per call.
* **Printing.** `print()` never fails on a broken drawing (the summary is
  printed first; a compile error in the interactive preview is a message).
  The preview goes to `getOption("viewer")` (an HTML page in `tempdir()`,
  what RStudio/Positron accept) or `utils::browseURL()` of an SVG file.
  `knit_print()` writes a PNG at the chunk's `fig_path()` like the `rpic`
  engine does (not inline SVG: two inline SVGs on one page share ids such
  as gradient definitions, and PNG works in every output format).
* **S3 registration for Suggests generics** (`knitr::knit_print`,
  `ggplot2::autoplot`) uses roxygen's `@exportS3Method pkg::generic` — the
  delayed `S3method(pkg::gen, class)` NAMESPACE directive (R ≥ 3.6): the
  method is registered when knitr/ggplot2 is loaded, with no `.onLoad`
  code and no hard dependency.
* **snake_case columns.** `rpic_sf()` names columns by one rule,
  `rpic_sf_names()`: every `:` and `-` of the GeoJSON property becomes `_`.
  sf's reader has already turned both into `.`, and no property of the
  geopic vocabulary contains a dot, so `.` → `_` on its names is the same
  map. The engine's GeoJSON text (and its MapLibre layers) keeps
  `geopic:kind`/`stroke-width`: the R names are an R-side view.
* **`add_rpic()`** is mapgl's verb shape (`add_*()`, map first, returns the
  map). `rpic_mapgl` is bound to the same function object (`identical()`),
  documented on the same page, so the alias can never drift.
* **`autoplot.rpic_source()`** is cheap (ggplot2 and sf were already in
  Suggests): `rpic_sf()` + identity fill/colour scales + `geom_sf_text()` of
  the `text`/`title` points (`fun.geometry` = identity, they are points
  already, which also avoids sf's lon/lat `st_point_on_surface()` warning).
