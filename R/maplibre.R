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
#' `geopic.kind`, ...). [rpic_mapgl()] takes care of that.
#'
#' @param x the drawing: the result of [rpic_geojson()] (any GeoJSON
#'   FeatureCollection text of class `"json"` will do), an `sf` data frame
#'   from [rpic_sf()] (its `"geojson"` attribute, the engine's own text, is
#'   used — not its rows, so an `sf` that has lost rows since is an error and
#'   edited columns are not seen), or pic source code, which is
#'   georeferenced with `rpic_geojson(x, ...)`.
#' @param ... arguments passed to [rpic_geojson()] when `x` is pic source.
#' @return a list of six layer specs, each a named list with `id`, `type`,
#'   `source` (`"pic"`), `filter`, `paint` and (for some) `layout`, in draw
#'   order. JSON arrays are atomic vectors when they hold two or more
#'   numbers or strings and lists otherwise (so `["zoom"]` is
#'   `list("zoom")`): `jsonlite::toJSON(layers, auto_unbox = TRUE)` — what
#'   htmlwidgets does — writes the engine's JSON back.
#' @section Errors:
#' A JSON text that is not a FeatureCollection raises an `rpic_geo_error`
#' with `e$info$kind == "invalid_geojson"`.
#' @seealso [rpic_mapgl()]; `vignette("mapgl")`.
#' @examples
#' layers <- rpic_maplibre_layers('geo_lon = -34.8711; geo_lat = -8.0631
#' geo_scale = 1000
#' circle rad 2 at (0, 0)
#' "Recife" at (0, 0)')
#' vapply(layers, function(l) l$id, "")
#' layers[[2]]$paint$`line-width`[1:3]   # "interpolate", exponential 2, zoom
#' @export
rpic_maplibre_layers <- function(x, ...) {
  gj <- .geo_text(x, ..., call = sys.call())
  .maplibre_layers(gj, sys.call())
}

#' Draw a pic drawing on a mapgl map
#'
#' Adds a georeferenced pic drawing to a [mapgl](https://walker-data.com/mapgl/)
#' map — [mapgl::maplibre()] or [mapgl::mapboxgl()]: a GeoJSON source `"pic"`
#' holding the engine's FeatureCollection, the six layers of
#' [rpic_maplibre_layers()] (added with [mapgl::add_layer()]) and, when
#' `fit`, a [mapgl::fit_bounds()] on the drawing (48 px of padding, zoom 19
#' at most — the fit of the engine's JavaScript `attach()`).
#'
#' The source is the engine's GeoJSON text, handed to the widget verbatim.
#' (`mapgl::add_source()` takes only an `sf` object, which it re-serialises
#' with the `sf` column names — `geopic.kind` instead of the `geopic:kind`
#' the layers read — or a URL; so `rpic_mapgl()` registers the source in the
#' widget itself, the way `add_source()` does.) A map holds one pic drawing:
#' the source id and the layer ids are fixed by the engine, so a map that
#' already has a source `"pic"` or one of the six layer ids is an error.
#'
#' @param map a map from [mapgl::maplibre()] or [mapgl::mapboxgl()] (Shiny
#'   proxies are not supported).
#' @inheritParams rpic_maplibre_layers
#' @param fit zoom the map to the drawing's bounding box.
#' @return `map`, with the source and the layers added (pipe-friendly).
#' @section Requirements:
#' Needs the `mapgl` package: `install.packages("mapgl")`.
#' @seealso `vignette("mapgl")`.
#' @examples
#' if (requireNamespace("mapgl", quietly = TRUE)) {
#'   src <- 'geo_lon = -34.8711; geo_lat = -8.0631; geo_scale = 1000
#'   circle rad 2 at (0, 0) fill 0.9
#'   "Recife" at (0, 0)'
#'   m <- rpic_mapgl(mapgl::maplibre(style = mapgl::carto_style("positron")), src)
#'   vapply(m$x$layers, function(l) l$id, "")
#' }
#' @export
rpic_mapgl <- function(map, x, ..., fit = TRUE) {
  if (!.has_mapgl()) {
    stop("rpic_mapgl() needs the 'mapgl' package: install.packages(\"mapgl\")", call. = FALSE)
  }
  if (inherits(map, c("maplibre_proxy", "mapboxgl_proxy"))) {
    stop("rpic_mapgl() does not support mapgl proxies; build the map with it instead",
         call. = FALSE)
  }
  if (!inherits(map, c("maplibregl", "mapboxgl"))) {
    stop("`map` must be a map from mapgl::maplibre() or mapgl::mapboxgl()", call. = FALSE)
  }
  gj <- .geo_text(x, ..., call = sys.call())
  layers <- .maplibre_layers(gj, sys.call())
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
  for (l in layers) {
    map <- mapgl::add_layer(map, id = l$id, type = l$type, source = l$source,
                            paint = l$paint, layout = l$layout, filter = l$filter)
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
        "features: rpic_maplibre_layers() and rpic_mapgl() use that GeoJSON, not the rows; ",
        "filter in the pic source (or pass rpic_geojson()'s result) instead"
      ), nrow(x), n), call. = FALSE)
    }
    attr(gj, "n_features") <- NULL
    return(gj)
  }
  if (inherits(x, "json")) {
    not_source()
    if (!is.character(x) || length(x) != 1 || is.na(x)) {
      stop("GeoJSON text must be a single string", call. = FALSE)
    }
    return(x)
  }
  if (is.character(x) && length(x) == 1 && !is.na(x)) {
    return(rpic_geojson(x, ...))
  }
  stop(paste0(
    "`x` must be an rpic_geojson() result, an rpic_sf() result or pic source ",
    "(a single string)"
  ), call. = FALSE)
}

.maplibre_layers <- function(gj, call) {
  res <- rpic_maplibre_layers_(as.character(gj))
  if (!is.null(res$error)) {
    stop(structure(
      class = c("rpic_geo_error", "rpic_error", "error", "condition"),
      list(message = res$error, call = call, info = res$info)
    ))
  }
  res$value
}
