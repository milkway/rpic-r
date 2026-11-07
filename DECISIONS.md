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
  `maxZoom = 19`, the engine's JS `attach()` fit. Without the padding the
  callout fitted edge to edge at a zoom where MapLibre placed the box title
  twice (apparently once per tile the polygon crossed).

## D8 — The mapgl vignette is evaluated (2026-11-07)

Unlike D5, `vignette("mapgl")` runs its chunks (when mapgl is installed):
the point is the interactive widget, which cannot be pre-rendered as a
picture. Two widgets keep it light: the built HTML is ~2.8 MB (maplibre-gl
and mapgl's other JS inlined), ~0.6 MB compressed in the tarball. Without
mapgl the chunks are shown unevaluated with a note.
