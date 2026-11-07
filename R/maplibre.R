# MapLibre layers for a geopic FeatureCollection (engine docs/geopic.md § 6)
# and the mapgl helper that puts a drawing on a map.

#' MapLibre layers that draw a georeferenced pic drawing
#'
#' The MapLibre style-spec layers the engine emits for a geopic
#' FeatureCollection (`geopic-core`'s `maplibre` module; the engine's
#' `docs/geopic.md` § 6): the same six layers the rpic.dev Maps page, the
#' JavaScript and Python bindings and `rpic --geojson --maplibre` draw with,
#' so a drawing looks the same on every map. In draw order:
#' `pic-fill` (polygon fills), `pic-stroke` and `pic-stroke-dashed` (outlines
#' and lines), `pic-dot` (dots), `pic-text` (text) and `pic-title` (shape
#' titles). Every layer reads one GeoJSON source named `"pic"` and styles
#' each feature from its simplestyle and `geopic:*` properties.
#'
#' Every size — stroke width, dot radius, font size — is **true to the
#' ground**: the collection's registration gives metres per inch, so a
#' 1-inch-wide label covers the same ground at every zoom (an exponential
#' interpolation over `zoom`, base 2).
#'
#' The layers read the feature properties under their GeoJSON names
#' (`stroke-width`, `geopic:kind`, ...), so the source they draw must be the
#' engine's GeoJSON, not a re-serialised `sf` data frame (whose columns are
#' `geopic_kind`, ...: [rpic_sf_names()]). [add_rpic()] takes care of that.
#'
#' @param x the drawing: the result of [rpic_geojson()] (or any GeoJSON
#'   FeatureCollection text: a string of class `"json"`, or one whose first
#'   non-blank character is an opening brace or bracket — so pic source that
#'   opens with a brace group needs a statement or comment before it), an
#'   `sf` data frame
#'   from [rpic_sf()] (its `"geojson"` attribute, the engine's own text, is
#'   used — not its rows, so an `sf` that has lost rows since is an error and
#'   edited columns are not seen), or pic source — a [pic()] object or a
#'   string — which is georeferenced with `rpic_geojson(x, ...)`.
#' @param ... arguments passed to [rpic_geojson()] when `x` is pic source.
#' @param text_scale multiplies every label's font size (`pic-text` and
#'   `pic-title`): a finite number in (0, 16]. The default, 1, keeps the
#'   labels true to the ground; 1.5 draws them half as large again, so they
#'   stay legible further out. Strokes and dots keep their ground sizes. The
#'   scale is applied inside the engine's sizing (`LayerOptions`, the
#'   engine's DECISIONS G11), so the upper `text-size` zoom stop still keeps
#'   labels within MapLibre's 255 px limit — the same output as
#'   `rpic --geojson --maplibre --text-scale`.
#' @return a list of six layer specs, each a named list with `id`, `type`,
#'   `source` (`"pic"`), `filter`, `paint` and (for some) `layout`, in draw
#'   order. JSON arrays are atomic vectors when they hold two or more
#'   numbers or strings and lists otherwise (so `["zoom"]` is
#'   `list("zoom")`): `jsonlite::toJSON(layers, auto_unbox = TRUE)` — what
#'   htmlwidgets does — writes the engine's JSON back.
#' @section Errors:
#' A JSON text that is not a FeatureCollection raises an `rpic_geo_error`
#' with `e$info$kind == "invalid_geojson"`; a `text_scale` that is not a
#' single number in (0, 16] one with `e$info$kind == "invalid_options"`.
#' @seealso [add_rpic()]; the article
#'   [Interactive maps with mapgl](https://milkway.github.io/rpic-r/articles/mapgl.html).
#' @examples
#' layers <- pic('geo_lon = -34.8711; geo_lat = -8.0631
#' geo_scale = 1000
#' circle rad 2 at (0, 0)
#' "Recife" at (0, 0)') |>
#'   rpic_maplibre_layers()
#' vapply(layers, function(l) l$id, "")
#' layers[[2]]$paint$`line-width`[1:3]   # "interpolate", exponential 2, zoom
#'
#' # larger labels: the text-size factor of pic-text grows by 1.5
#' big <- rpic_maplibre_layers('geo_lon = -34.8711; geo_lat = -8.0631
#' geo_scale = 1000
#' "Recife" at (0, 0)', text_scale = 1.5)
#' @export
rpic_maplibre_layers <- function(x, ..., text_scale = 1) {
  opts <- .layer_options(text_scale, sys.call())
  gj <- .geo_text(x, ..., call = sys.call())
  .maplibre_layers(gj, opts, sys.call())
}

#' Draw a pic drawing on a mapgl map
#'
#' `add_rpic()` adds a georeferenced pic drawing to a
#' [mapgl](https://walker-data.com/mapgl/) map — [mapgl::maplibre()] or
#' [mapgl::mapboxgl()] — as mapgl's own `add_*()` verbs do, map first, so it
#' joins a pipe: `maplibre() |> add_rpic(pic(src))`. It adds a GeoJSON
#' source `"pic"`
#' holding the engine's FeatureCollection, the six layers of
#' [rpic_maplibre_layers()] (added with [mapgl::add_layer()]) and, when
#' `fit`, a [mapgl::fit_bounds()] on the drawing (48 px of padding, zoom 19
#' at most — the fit of the engine's JavaScript `attach()`).
#'
#' `before` decides where the drawing goes among the style's layers, by the
#' rule of the engine's JavaScript `attach(map, fc, { before })`: only the
#' geometry layers (`pic-fill`, `pic-stroke`, `pic-stroke-dashed`,
#' `pic-dot`) are inserted before the chosen layer; the drawing's own
#' labels (`pic-text`, `pic-title`) are always added on top, so a basemap
#' label never covers them.
#'
#' * `NULL` (the default): all six layers on top of the style.
#' * `"labels"`: under the basemap's labels — before the style's layer with
#'   the id `labels` if it has one, else at the start of its trailing label
#'   block: before the first layer that follows the last non-`symbol` layer
#'   (fill, line, ...), among the style's layers and those already added to
#'   `map` (the `pic-*` layers aside). Not simply the first `symbol` layer:
#'   CARTO's positron puts `waterway_label` before its roads, buildings and
#'   boundaries, and the drawing would go under all of them. When a
#'   geometry layer is the last one, there is no label block and the layers
#'   go on top. The style is read from `map$x$style`: a list is
#'   inspected as is (`layers` as a list of layers or, from
#'   `jsonlite::fromJSON()`, a data frame); a URL
#'   (`mapgl::carto_style("positron")`, ...) is fetched once per session
#'   (needs `jsonlite`; 10 s timeout). When the style cannot be read —
#'   offline, a `mapbox://` URL, `mapgl::mapboxgl()`'s default style, a list
#'   without `layers`, no `jsonlite` — and no layer added to `map` answers,
#'   a warning says so and the layers go on top (the added layers alone
#'   answer when they end in `symbol` layers).
#' * any other string: the id of a layer to insert before — of the style
#'   or one already added to `map`. When the style can be read and has no
#'   such layer, a warning says so and the layers go on top (MapLibre would
#'   otherwise drop them). When it cannot be read, the id is used as given,
#'   with a warning that it could not be checked.
#'
#' The source is the engine's GeoJSON text, handed to the widget verbatim.
#' (`mapgl::add_source()` takes only an `sf` object, which it re-serialises
#' with the `sf` column names — `geopic_kind` instead of the `geopic:kind`
#' the layers read — or a URL; so `add_rpic()` registers the source in the
#' widget itself, the way `add_source()` does.) A map holds one pic drawing:
#' the source id and the layer ids are fixed by the engine, so a map that
#' already has a source `"pic"` or one of the six layer ids is an error.
#'
#' `font` sets the `text-font` of the drawing's labels (`pic-text`,
#' `pic-title`). The font decides where a label sits: MapLibre places the
#' text box by the glyphs' vertical metrics, and a glyph server's
#' "Noto Sans Regular" (CARTO's, for one) is not the one the engine's
#' anchors were measured with, so a label meant to sit above a line can
#' land on it. With `"style"` (the default) the labels use the style's own
#' font: the most common `text-font` stack among its `symbol` layers,
#' upright `Regular`/`Medium` stacks preferred over bold and italic ones
#' (CARTO's positron: `Montserrat Medium, Open Sans Regular, ...`). The
#' style is read as for `before` (a URL is fetched once per session); when
#' it cannot be read or has no such stack, the engine's font is kept,
#' without a warning of its own. `"spec"` keeps the engine's
#' `"Noto Sans Regular"`; any other character vector is the font stack
#' itself (names the style's glyph server must serve).
#'
#' `rpic_mapgl()` is the same function under its first name (an alias kept
#' for code written against the development version).
#'
#' @param map a map from [mapgl::maplibre()] or [mapgl::mapboxgl()] (Shiny
#'   proxies are not supported).
#' @inheritParams rpic_maplibre_layers
#' @param before where the geometry layers go: `NULL` (on top), `"labels"`
#'   (under the basemap's labels) or a layer id; see Details.
#' @param font the labels' font stack: `"style"` (the style's own font),
#'   `"spec"` (the engine's) or a character vector of font names; see
#'   Details.
#' @param fit zoom the map to the drawing's bounding box.
#' @return `map`, with the source and the layers added (pipe-friendly).
#' @section Requirements:
#' Needs the `mapgl` package: `install.packages("mapgl")`.
#' @seealso [rpic_maplibre_layers()]; `vignette("maps")`; the article
#'   [Interactive maps with mapgl](https://milkway.github.io/rpic-r/articles/mapgl.html).
#' @examples
#' if (requireNamespace("mapgl", quietly = TRUE)) {
#'   src <- pic('geo_lon = -34.8711; geo_lat = -8.0631; geo_scale = 1000
#'   circle rad 2 at (0, 0) fill 0.9
#'   "Recife" at (0, 0)')
#'   m <- mapgl::maplibre(style = mapgl::carto_style("positron")) |>
#'     add_rpic(src)
#'   vapply(m$x$layers, function(l) l$id, "")
#'
#'   # shapes under the basemap's labels, larger labels; a style given as a
#'   # list is read without a download
#'   style <- list(version = 8, sources = list(), layers = list(
#'     list(id = "water", type = "fill"),
#'     list(id = "place-names", type = "symbol")
#'   ))
#'   m <- mapgl::maplibre(style = style) |>
#'     add_rpic(src, before = "labels", text_scale = 1.5)
#'   vapply(m$x$layers, function(l) if (is.null(l$before_id)) NA_character_ else l$before_id, "")
#' }
#' @export
add_rpic <- function(map, x, ..., before = NULL, text_scale = 1, font = "style",
                     fit = TRUE) {
  if (!.has_mapgl()) {
    stop("add_rpic() needs the 'mapgl' package: install.packages(\"mapgl\")", call. = FALSE)
  }
  if (inherits(map, c("maplibre_proxy", "mapboxgl_proxy"))) {
    stop("add_rpic() does not support mapgl proxies; build the map with it instead",
         call. = FALSE)
  }
  if (!inherits(map, c("maplibregl", "mapboxgl"))) {
    stop("`map` must be a map from mapgl::maplibre() or mapgl::mapboxgl()", call. = FALSE)
  }
  if (!is.null(before) && (!is.character(before) || length(before) != 1 ||
                            is.na(before) || !nzchar(before))) {
    stop("`before` must be NULL, \"labels\" or a layer id (a single string)", call. = FALSE)
  }
  if (!is.character(font) || !length(font) || anyNA(font) || !all(nzchar(font))) {
    stop("`font` must be \"style\", \"spec\" or a font stack (a character vector)",
         call. = FALSE)
  }
  opts <- .layer_options(text_scale, sys.call())
  gj <- .geo_text(x, ..., call = sys.call())
  layers <- .maplibre_layers(gj, opts, sys.call())
  source <- layers[[1]]$source
  # a map holds one pic drawing: a second "pic" source or duplicate layer ids
  # make mapgl's JavaScript throw at init (a blank map, no R error)
  have_sources <- vapply(map$x$sources, function(s) as.character(s$id)[1], "")
  have_layers <- vapply(map$x$layers, function(l) as.character(l$id)[1], "")
  ids <- vapply(layers, function(l) l$id, "")
  clash <- c(intersect(source, have_sources), intersect(ids, have_layers))
  if (length(clash)) {
    stop(sprintf(paste0(
      "this map already has %s; a map holds one pic drawing ",
      "(source \"%s\" and layers %s)"
    ), paste0("\"", clash, "\"", collapse = ", "), source,
    paste0("\"", ids, "\"", collapse = ", ")), call. = FALSE)
  }
  # what mapgl::add_source() stores for an sf, with the engine's text as the
  # data: a "json"-classed string is written verbatim by htmlwidgets
  data <- structure(as.character(gj), class = "json")
  map$x$sources <- c(map$x$sources, list(list(
    id = source, type = "geojson", data = data, generateId = TRUE
  )))
  # the style is read at most once per call (a failed download is not
  # cached, and would otherwise be retried for `before` and `font`)
  style <- NULL
  read_style <- function() {
    if (is.null(style)) style <<- .style_layers(map$x$style)
    style
  }
  # resolved before our layers join map$x$layers (so they are never a target)
  below <- .before_id(map, before, read_style)
  stack <- .text_font(font, read_style)
  for (l in layers) {
    if (!is.null(stack) && l$id %in% .pic_text_layers) {
      l$layout[["text-font"]] <- as.list(stack)
    }
    # the drawing's own labels always go on top (the JS attach() rule)
    b <- if (l$id %in% .pic_text_layers) NULL else below
    map <- mapgl::add_layer(map, id = l$id, type = l$type, source = l$source,
                            paint = l$paint, layout = l$layout, filter = l$filter,
                            before_id = b)
  }
  if (isTRUE(fit)) {
    bbox <- rpic_geojson_bbox_(as.character(gj))
    if (!is.null(bbox)) {
      # the engine's JS `attach()` fit: 48 px of padding, zoom 19 at most
      map <- mapgl::fit_bounds(map, bbox, padding = 48, maxZoom = 19)
    }
  }
  map
}

#' @rdname add_rpic
#' @export
rpic_mapgl <- add_rpic

.has_mapgl <- function() requireNamespace("mapgl", quietly = TRUE)

# The drawing as GeoJSON text (class "json"): an rpic_geojson() result as
# is, an rpic_sf() result's "geojson" attribute, pic source georeferenced.
.geo_text <- function(x, ..., call = NULL) {
  dots <- list(...)
  not_source <- function() {
    if (length(dots)) {
      stop("arguments in `...` apply only when `x` is pic source", call. = FALSE)
    }
  }
  if (inherits(x, "sf")) {
    not_source()
    gj <- attr(x, "geojson", exact = TRUE)
    if (!inherits(gj, "json")) {
      stop(paste0(
        "this sf data frame carries no engine GeoJSON (it was not made by rpic_sf(), ",
        "or an sf operation dropped its \"geojson\" attribute); pass rpic_geojson()'s result"
      ), call. = FALSE)
    }
    n <- attr(gj, "n_features", exact = TRUE)
    if (!is.null(n) && n != nrow(x)) {
      stop(sprintf(paste0(
        "this sf data frame has %d rows but the engine GeoJSON it was read from has %d ",
        "features: rpic_maplibre_layers() and add_rpic() use that GeoJSON, not the rows; ",
        "filter in the pic source (or pass rpic_geojson()'s result) instead"
      ), nrow(x), n), call. = FALSE)
    }
    attr(gj, "n_features") <- NULL
    return(gj)
  }
  # unclassed GeoJSON text (read from a file, or as.character() of a result)
  # starts with `{` (or `[`); pic source would only do so by opening with a
  # `{ ... }` group (documented: put any statement before it)
  if (is.character(x) && !inherits(x, c("json", "rpic_source")) && length(x) == 1 &&
      !is.na(x) &&
      grepl("^[{[]", trimws(x))) {
    x <- structure(x, class = "json")
  }
  if (inherits(x, "json")) {
    not_source()
    if (!is.character(x) || length(x) != 1 || is.na(x)) {
      stop("GeoJSON text must be a single string", call. = FALSE)
    }
    return(x)
  }
  if (is.character(x) && length(x) == 1 && !is.na(x)) {
    # report the caller's call (`rpic_maplibre_layers("box")`), not ours
    return(withCallingHandlers(
      rpic_geojson(x, ...),
      rpic_error = function(e) {
        if (!is.null(call)) e$call <- call
        stop(e)
      },
      rpic_geo_warning = function(w) {
        if (!is.null(call)) w$call <- call
        warning(w)
        invokeRestart("muffleWarning")
      }
    ))
  }
  stop(paste0(
    "`x` must be an rpic_geojson() result, an rpic_sf() result or pic source ",
    "(a pic() object or a single string)"
  ), call. = FALSE)
}

# The engine's layer options as JSON text (`{"text_scale": k}`), validated by
# the engine (`LayerOptions::from_json`); R only checks it can write a JSON
# number.
.layer_options <- function(text_scale, call) {
  if (!is.numeric(text_scale) || length(text_scale) != 1 || is.na(text_scale) ||
      !is.finite(text_scale)) {
    shown <- if (is.numeric(text_scale) && length(text_scale) == 1) {
      format(text_scale)
    } else {
      paste0("a ", class(text_scale)[1], " of length ", length(text_scale))
    }
    stop(.geo_condition(
      "invalid_options",
      sprintf("text_scale must be a finite number in (0, 16], got %s", shown),
      call = call
    ))
  }
  sprintf('{"text_scale": %s}', sprintf("%.17g", as.double(text_scale)))
}

# An `rpic_geo_error` condition shaped like the shim's geo errors: `info`
# holds `kind`, `message`, `hint`; the message is the engine's GeoError
# display, `<message> (<kind>)` and ` — <hint>` when there is one.
.geo_condition <- function(kind, message, hint = NA_character_, call = NULL) {
  text <- sprintf("%s (%s)", message, kind)
  if (length(hint) == 1 && !is.na(hint)) text <- paste0(text, " \u2014 ", hint)
  structure(
    class = c("rpic_geo_error", "rpic_error", "error", "condition"),
    list(message = text, call = call,
         info = list(kind = kind, message = message, hint = hint))
  )
}

.maplibre_layers <- function(gj, opts, call) {
  res <- rpic_maplibre_layers_(as.character(gj), opts)
  if (!is.null(res$error)) {
    stop(.geo_condition(res$info$kind, res$info$message, res$info$hint, call))
  }
  res$value
}

# The drawing's label layers: `before` never buries them (JS TEXT_LAYER_IDS).
.pic_text_layers <- c("pic-text", "pic-title")

# The layer id the geometry layers go before (NULL = on top), the rule of the
# engine's JS `attach()`: "labels" = a layer whose id is `labels`, else the
# start of the trailing label block (`.label_block_start()`); any other
# string = that layer, checked
# when the style can be read. The candidates are the style's layers, then the
# layers already added to the map (both precede ours at load); the added ones
# are consulted even when the style cannot be read.
.before_id <- function(map, before, read_style = function() .style_layers(map$x$style)) {
  if (is.null(before)) return(NULL)
  added <- .layer_table(map$x$layers)
  # the style is read only when the added layers do not settle it
  if (before == "labels" && "labels" %in% added$id) return("labels")
  if (before != "labels" && before %in% added$id) return(before)
  style <- read_style()
  if (!is.null(style$error)) {
    if (before == "labels") {
      # the added layers come after the (unknown) style: their trailing
      # symbol block, if any, is the end of the map's label block
      first <- .label_block_start(map$x$layers)
      if (!is.null(first)) return(first)
      warning(sprintf(
        "add_rpic(): could not read the map's style to find its labels (%s); the pic layers go on top",
        style$error), call. = FALSE)
      return(NULL)
    }
    # cannot check: trust the id, but say so (MapLibre drops the geometry
    # layers at runtime when the map has no such layer)
    warning(sprintf(paste0(
      "add_rpic(): could not read the map's style to check that it has a layer \"%s\" ",
      "(%s); using it as given; if the map has no such layer, MapLibre drops the pic ",
      "geometry layers"), before, style$error), call. = FALSE)
    return(before)
  }
  all <- .layer_table(c(style$layers, map$x$layers))
  if (before == "labels") {
    if ("labels" %in% all$id) return("labels")
    return(.label_block_start(c(style$layers, map$x$layers)))
  }
  if (before %in% all$id) return(before)
  warning(sprintf(
    "add_rpic(): the map's style has no layer \"%s\"; the pic layers go on top", before
  ), call. = FALSE)
  NULL
}

# The start of the trailing label block of `layers` (the style's, then the
# map's added ones): the first layer with an id after the last layer whose
# type is not `symbol`, the `pic-*` layers ignored; NULL when nothing follows
# that last geometry layer. Not the first `symbol` layer: styles such as
# CARTO's positron put `waterway_label` early, before 50+ road, building and
# boundary layers, and the drawing would go under all of them.
.label_block_start <- function(layers) {
  t <- .layer_table(layers, keep_unnamed = TRUE)
  own <- !is.na(t$id) & startsWith(t$id, "pic-")
  id <- t$id[!own]
  type <- t$type[!own]
  geo <- which(!(type %in% "symbol"))
  last_geo <- if (length(geo)) max(geo) else 0L
  after <- id[seq_along(id) > last_geo]
  after <- after[!is.na(after)]
  if (length(after)) after[1] else NULL
}

# The `text-font` stack for the drawing's label layers (NULL = keep the
# spec's): "spec" keeps it; "style" = the style's own font, the most common
# plain `text-font` array among its symbol layers, upright Regular/Medium
# stacks (first name) preferred over bold or italic ones, ties to the first
# in style order; an unreadable style or one without such stacks keeps the
# spec's, silently (`before` already warns when it needed the style). Any
# other vector is the stack itself.
.text_font <- function(font, read_style) {
  if (identical(font, "spec")) return(NULL)
  if (!identical(font, "style")) return(font)
  style <- read_style()
  if (!is.null(style$error)) return(NULL)
  stacks <- list()
  for (l in style$layers) {
    if (!is.list(l) || !identical(as.character(l$type)[1], "symbol")) next
    f <- if (is.list(l$layout)) l$layout[["text-font"]]
    if (is.list(f)) {
      if (!all(vapply(f, function(v) is.character(v) && length(v) == 1, NA))) next
      f <- unlist(f)
    }
    # an expression (`["literal", ...]`, `["step", ...]`) is not a stack
    if (is.character(f) && length(f) && !anyNA(f) && all(nzchar(f)) &&
        !grepl("^[a-z-]+$", f[1])) {
      stacks[[length(stacks) + 1]] <- f
    }
  }
  if (!length(stacks)) return(NULL)
  keys <- vapply(stacks, function(f) paste(f, collapse = "\u001f"), "")
  upright <- vapply(stacks, function(f) {
    grepl("Regular|Medium", f[1]) && !grepl("Italic", f[1])
  }, NA)
  pool <- if (any(upright)) which(upright) else seq_along(stacks)
  counts <- table(factor(keys[pool], levels = unique(keys[pool])))
  stacks[[pool[match(names(counts)[which.max(counts)], keys[pool])]]]
}

# Layers as a table of `id` and `type`, without the layers that have no id
# (never a `before_id`) unless `keep_unnamed` (they still count as geometry
# or symbol when finding the label block).
.layer_table <- function(layers, keep_unnamed = FALSE) {
  str1 <- function(v) {
    v <- if (is.null(v) || !length(v)) NA_character_ else as.character(v[[1]])
    if (!length(v) || is.na(v) || !nzchar(v)) NA_character_ else v
  }
  id <- vapply(layers, function(l) if (is.list(l)) str1(l$id) else NA_character_, "")
  type <- vapply(layers, function(l) if (is.list(l)) str1(l$type) else NA_character_, "")
  keep <- keep_unnamed | !is.na(id)
  list(id = unname(id[keep]), type = unname(type[keep]))
}

# The style's layers: list(layers =) or list(error =). A list style is read as
# is — also one parsed by `jsonlite::fromJSON()` with its default
# simplification, whose `layers` is a data frame; an http(s) URL is fetched
# (`.fetch_style()`, memoised, mocked in the tests).
.style_layers <- function(style) {
  if (is.null(style)) {
    return(list(error = "the map's default style cannot be read here"))
  }
  if (is.list(style)) return(.style_list_layers(style))
  if (!is.character(style) || length(style) != 1 || is.na(style)) {
    return(list(error = "the style is neither a list nor a URL"))
  }
  if (!grepl("^https?://", style)) {
    return(list(error = sprintf("cannot download a style from \"%s\"", style)))
  }
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    return(list(error = "reading a style URL needs the 'jsonlite' package"))
  }
  tryCatch(
    .style_list_layers(.fetch_style_cached(style)),
    error = function(e) list(error = conditionMessage(e))
  )
}

.style_list_layers <- function(js) {
  layers <- if (is.list(js)) js$layers
  if (is.data.frame(layers)) {
    # fromJSON(simplifyVector = TRUE): one row per layer; only `id`, `type`
    # and `layout$text-font` are read
    col <- function(k) if (k %in% names(layers)) as.character(layers[[k]]) else
      rep(NA_character_, nrow(layers))
    id <- col("id")
    type <- col("type")
    lay <- layers[["layout"]]
    fonts <- if (is.data.frame(lay) && "text-font" %in% names(lay)) lay[["text-font"]]
    layers <- lapply(seq_len(nrow(layers)), function(i) {
      l <- list(id = id[i], type = type[i])
      f <- if (is.list(fonts)) fonts[[i]]
      if (is.character(f)) l$layout <- list(`text-font` = f)
      l
    })
  }
  if (!is.list(layers)) return(list(error = "the style has no `layers` array"))
  list(layers = layers)
}

# One download per style URL per session: several maps in a document share it.
.style_cache <- new.env(parent = emptyenv())

.fetch_style_cached <- function(url) {
  if (!exists(url, envir = .style_cache, inherits = FALSE)) {
    assign(url, .fetch_style(url), envir = .style_cache)
  }
  get(url, envir = .style_cache, inherits = FALSE)
}

.fetch_style <- function(url, timeout = 10) {
  old <- options(timeout = timeout)
  on.exit(options(old), add = TRUE)
  con <- url(url, open = "rb")
  on.exit(close(con), add = TRUE)
  jsonlite::fromJSON(paste(readLines(con, warn = FALSE, encoding = "UTF-8"), collapse = "\n"),
                     simplifyVector = FALSE)
}

`%||%` <- function(a, b) if (is.null(a)) b else a
