# geopic: pic drawings as GeoJSON / sf (engine docs/geopic.md).

#' Georeference a pic drawing as GeoJSON
#'
#' Places a pic drawing on the Earth and returns it as a GeoJSON
#' `FeatureCollection` (RFC 7946, WGS84 longitude/latitude), through the
#' engine's `geopic-core`. The drawing is registered by a similarity —
#' declared in the source with the variables `geo_lon`, `geo_lat` (the
#' position of the pic origin), `geo_scale` (metres per inch, default 100),
#' `geo_bearing` (azimuth of the drawing's +y axis, degrees clockwise from
#' north) and `geo_frame` (`0` = `enu`, `1` = `mercator`) — or recovered from
#' control points: a place `A: (x, y)` with `A_lon`/`A_lat` (one point
#' anchors, two fix scale and bearing exactly, three or more are fitted by
#' least squares). Every argument here overrides the corresponding source
#' variable (the caller wins, like `-D` in troff).
#'
#' Straight segments are densified in the plane before they are carried to
#' longitude/latitude (no step longer than 100 m), so a circle of radius
#' 2 km is a geodesic circle, not a circle in degree space. Each drawn object
#' becomes one or more features (boxes and circles polygons, lines line
#' strings, dots and text points, arrowheads separate features, and a shape
#' with text an extra `title` point at the text's centre) whose
#' properties are the simplestyle keys (`stroke`, `stroke-width`, `fill`,
#' `stroke-opacity`, `fill-opacity`, `title`) and the `geopic:` namespace
#' (`geopic:id`, `geopic:kind`, `geopic:text`, `geopic:placement`, ...);
#' the full vocabulary is in the engine's `docs/geopic.md`.
#'
#' @section Features:
#' `features` names places the source may use without defining them
#' (`arrow from Recife to Olinda`). Give it as
#' * a named list of `c(lon, lat)` (or `c(lon, lat, west, south, east, north)`
#'   for a feature with extent);
#' * a `data.frame` with columns `name`, `lon`, `lat`;
#' * an `sf` object: the name comes from column `name_col`, the point is the
#'   geometry's centroid ([sf::st_centroid()]) and the extent its bounding
#'   box ([sf::st_bbox()]); data in another CRS is transformed to EPSG:4326.
#'
#' Features the source itself defines (a place or a labelled object) act as
#' control points of its own geometry. The others are placed by a first
#' pass's registration and injected before the source — as places, or as
#' invisible boxes spanning their extent so `Name.n`/`Name.e` follow it — and
#' the drawing is georeferenced again with all of them. Names must be pic
#' labels (an uppercase letter, then letters, digits or underscores); any
#' other name is an error, never written into the source. Diagnostic
#' positions stay relative to your `src` (a position inside the injected
#' lines has `file = "features"`).
#'
#' @section Warnings and errors:
#' Anything that cannot be represented exactly (a gradient fill, an
#' animation, a control point that names no label, ...) is reported, never
#' dropped silently: one R warning per distinct kind, of class
#' `rpic_geo_warning` (which inherits `rpic_warning`), whose `info` field
#' lists the warnings of that kind; all of them are also in the `"warnings"`
#' attribute of the result (each a list of `kind`, `message`, `hint`, `id`,
#' `line`, `col`, `end_col`, `file`; absent values are `NA`).
#'
#' A drawing that cannot be registered (no anchor and no control points,
#' a scale out of range, coincident control points, ...) raises an
#' `rpic_geo_error` condition (inheriting `rpic_error`) whose `info` holds
#' `kind` (`"no_registration"`, `"invalid_scale"`, `"invalid_anchor"`,
#' `"invalid_flatten"`, `"view_scale_required"`,
#' `"degenerate_control_points"`, `"invalid_options"`), `message` and `hint`.
#' pic errors raise the usual `rpic_error`.
#'
#' @inheritParams rpic_svg
#' @param frame projection frame: `"enu"` (local tangent plane at the anchor:
#'   true distances, geodesic straight lines) or `"mercator"` (Web Mercator:
#'   lines stay straight on a web map). When omitted the source's
#'   `geo_frame` decides (default `enu`).
#' @param anchor `c(lon, lat)` of the pic origin `(0, 0)`, overriding
#'   `geo_lon`/`geo_lat`.
#' @param scale metres per inch of the drawing as authored, overriding
#'   `geo_scale`.
#' @param bearing azimuth of the drawing's +y axis in degrees clockwise from
#'   north, overriding `geo_bearing`.
#' @param features host-provided named features (see the Features section).
#' @param flatten curve tolerance in inches (cubic curves are flattened to
#'   within this distance before densification).
#' @param view_scale pixels per inch, needed when the source sets
#'   `geo_px = 1` (lengths in pixels, `geo_scale` in metres per pixel).
#' @param name_col for an `sf` `features`, the column holding the names.
#' @return a JSON string of class `c("geojson", "json")` with attributes
#'   `"warnings"` (see above) and `"registration"` — the similarity that
#'   placed the drawing: `frame`, `anchor` (`lon`, `lat`), `origin` (the
#'   canvas point at the anchor, inches), `scale_m_per_in`, `bearing_deg`,
#'   `method` (`"anchor"`, `"two_points"`, `"helmert"`), `control_points`
#'   and, for fits, `rms_m`. The same registration rides inside the GeoJSON
#'   as the foreign member `geopic`.
#' @seealso [rpic_sf()] for an `sf` data frame; `vignette("maps")`.
#' @examples
#' gj <- rpic_geojson('geo_lon = -34.8711; geo_lat = -8.0631
#' geo_scale = 1000     # one inch is one kilometre
#' circle rad 2 at (0, 0)
#' "Recife" at (0, 0)')
#' attr(gj, "registration")$method   # "anchor"
#' substr(gj, 1, 60)
#'
#' # an arrow between two places the source does not define
#' gj <- rpic_geojson("arrow from Recife to Olinda",
#'   features = list(Recife = c(-34.8711, -8.0631), Olinda = c(-34.8553, -8.0089)))
#' attr(gj, "registration")$method   # "two_points"
#'
#' # no anchor and no control points: a classed error with a hint
#' tryCatch(rpic_geojson("box"), rpic_geo_error = function(e) e$info$kind)
#' @export
rpic_geojson <- function(src, frame = c("enu", "mercator"), anchor = NULL, scale = NULL,
                         bearing = NULL, features = NULL, flatten = 1e-3, view_scale = NULL,
                         circuits = FALSE, texlabels = FALSE, name_col = "name") {
  frame <- if (missing(frame)) NULL else match.arg(frame)
  feats <- .geo_features(features, name_col)
  opts <- .geo_options_json(frame, anchor, scale, bearing, feats, flatten, view_scale)
  res <- rpic_geojson_(src, isTRUE(circuits), isTRUE(texlabels), opts)
  if (!is.null(res$error)) {
    cls <- if (isTRUE(res$geo)) c("rpic_geo_error", "rpic_error") else "rpic_error"
    stop(structure(
      class = c(cls, "error", "condition"),
      list(message = res$error, call = sys.call(), info = res$info)
    ))
  }
  out <- res$value
  .geo_warn(out$warnings, sys.call())
  structure(out$geojson,
    class = c("geojson", "json"),
    warnings = out$warnings,
    registration = out$registration
  )
}

#' Georeference a pic drawing as an sf data frame
#'
#' [rpic_geojson()] read into an `sf` data frame (EPSG:4326), one row per
#' feature, ready for [ggplot2::geom_sf()], `mapgl` or any other `sf`
#' consumer.
#'
#' Columns are the feature properties. The simplestyle keys keep their names
#' (`stroke`, `stroke-width`, `fill`, `stroke-opacity`, `fill-opacity`,
#' `title`; use backticks for the hyphenated ones), and every `geopic:<name>`
#' property becomes `geopic.<name>` (`geopic.id`, `geopic.kind`,
#' `geopic.text`, `geopic.placement`, `geopic.font_size`, ...) — the colon
#' is awkward in R column names. A property no feature carries is absent;
#' one only some features carry is `NA` elsewhere. The geometry column is
#' `geometry`, of mixed type (polygons for boxes and circles, line strings
#' for lines and arrows, points for dots and text).
#'
#' A shape with text (`box "Marco Zero"`) is followed by a `title` row: a
#' point at the centre of its text, `geopic.kind == "title"`, `geopic.id`
#' `"<id>:title"` and `geopic.for` naming the shape's `geopic.id`, carrying
#' the text in `title` and `geopic.text` (engine 0.15.1; MapLibre's
#' `pic-title` layer draws these). Filter them out
#' (`x[x$geopic.kind != "title", ]`) to keep one row per shape.
#'
#' The `"warnings"` and `"registration"` attributes of [rpic_geojson()] are
#' carried over (as attributes of the data frame; `sf` operations may drop
#' them), and warnings are raised the same way. The `"geojson"` attribute
#' keeps the engine's own GeoJSON text (the [rpic_geojson()] result the data
#' frame was read from), which [rpic_maplibre_layers()] and [rpic_mapgl()]
#' use instead of re-serialising the data frame.
#' @param src pic source code.
#' @param ... arguments passed to [rpic_geojson()] (`frame`, `anchor`,
#'   `scale`, `bearing`, `features`, `flatten`, `view_scale`, `circuits`,
#'   `texlabels`, `name_col`).
#' @return an `sf` data frame with CRS EPSG:4326.
#' @section Requirements:
#' Needs the `sf` package: `install.packages("sf")`.
#' @seealso `vignette("maps")`.
#' @examples
#' if (requireNamespace("sf", quietly = TRUE)) {
#'   x <- rpic_sf('geo_lon = -34.8711; geo_lat = -8.0631; geo_scale = 400
#'   B: box "Marco Zero" at (1, 1) fill 0.95
#'   arrow from B.sw to (0, 0)')
#'   x[, c("geopic.kind", "fill")]
#' }
#' @export
rpic_sf <- function(src, ...) {
  if (!.has_sf()) {
    stop("rpic_sf() needs the 'sf' package: install.packages(\"sf\")", call. = FALSE)
  }
  gj <- rpic_geojson(src, ...)
  x <- sf::st_read(as.character(gj), quiet = TRUE, stringsAsFactors = FALSE)
  # sf's reader makes the names syntactic ("stroke-width" -> "stroke.width",
  # "geopic:kind" -> "geopic.kind"); put the simplestyle names back. Rebuild
  # the sf object after renaming so its `agr` attribute follows the new names.
  nm <- names(x)
  simplestyle <- c("stroke-width", "stroke-opacity", "fill-opacity",
                   "marker-size", "marker-symbol", "marker-color")
  hit <- match(nm, make.names(simplestyle))
  nm[!is.na(hit)] <- simplestyle[hit[!is.na(hit)]]
  geom_col <- attr(x, "sf_column")
  x <- sf::st_as_sf(stats::setNames(as.data.frame(x), nm), sf_column_name = nm[match(geom_col, names(x))])
  if (attr(x, "sf_column") != "geometry") {
    sf::st_geometry(x) <- "geometry"
  }
  x <- sf::st_set_crs(x, 4326)
  attr(x, "warnings") <- attr(gj, "warnings")
  attr(x, "registration") <- attr(gj, "registration")
  # the engine's own text, for rpic_maplibre_layers()/rpic_mapgl(); the row
  # count lets them notice an sf that lost rows since
  attr(x, "geojson") <- structure(gj, n_features = nrow(x))
  x
}

# Is sf available? (a function so tests can exercise the sf-less paths)
.has_sf <- function() requireNamespace("sf", quietly = TRUE)

# One R warning per distinct kind (with its count), class rpic_geo_warning.
.geo_warn <- function(warnings, call) {
  if (length(warnings) == 0) return(invisible())
  kinds <- vapply(warnings, function(w) w$kind, "")
  for (k in unique(kinds)) {
    these <- warnings[kinds == k]
    n <- length(these)
    msg <- if (n == 1) {
      sprintf("%s: %s", k, these[[1]]$message)
    } else {
      sprintf("%s (%d warnings), first: %s", k, n, these[[1]]$message)
    }
    warning(structure(
      class = c("rpic_geo_warning", "rpic_warning", "warning", "condition"),
      list(message = msg, call = call, kind = k, count = n, info = these)
    ))
  }
  invisible()
}

.geo_label_ok <- function(x) grepl("^[A-Z][A-Za-z0-9_]*$", x)

.geo_num <- function(x, what, n = 1) {
  if (!is.numeric(x) || length(x) != n || any(!is.finite(x))) {
    stop(sprintf("`%s` must be %s", what,
      if (n == 1) "a single finite number" else sprintf("%d finite numbers", n)),
      call. = FALSE)
  }
  as.numeric(x)
}

# `features` as a list of list(name, lon, lat, bbox = NULL | c(w, s, e, n)).
.geo_features <- function(features, name_col = "name") {
  if (is.null(features)) return(list())
  forms <- paste0(
    "`features` must be a named list of c(lon, lat) (or c(lon, lat, west, south, east, north)), ",
    "a data.frame with columns name, lon, lat, or an sf object with a name column"
  )
  one <- function(name, lon, lat, bbox = NULL) {
    name <- as.character(name)
    if (length(name) != 1 || is.na(name) || !.geo_label_ok(name)) {
      stop(sprintf(
        "feature name %s is not a pic label (an uppercase letter followed by letters, digits or underscores)",
        encodeString(as.character(name)[1], quote = '"')
      ), call. = FALSE)
    }
    list(
      name = name,
      lon = .geo_num(lon, paste0(name, " lon")),
      lat = .geo_num(lat, paste0(name, " lat")),
      bbox = if (is.null(bbox)) NULL else .geo_num(bbox, paste0(name, " bbox"), 4)
    )
  }
  if (inherits(features, "sf")) {
    if (!.has_sf()) {
      stop("sf features need the 'sf' package: install.packages(\"sf\")", call. = FALSE)
    }
    if (!name_col %in% names(features)) {
      stop(sprintf("`features` has no column `%s` (set `name_col`)", name_col), call. = FALSE)
    }
    crs <- sf::st_crs(features)
    if (!is.na(crs) && !isTRUE(crs == sf::st_crs(4326))) {
      features <- sf::st_transform(features, 4326)
    }
    geom <- sf::st_geometry(features)
    names_ <- as.character(features[[name_col]])
    out <- vector("list", length(geom))
    for (i in seq_along(geom)) {
      g <- geom[i]
      if (sf::st_is_empty(g)) {
        stop(sprintf("feature %s has no geometry", encodeString(names_[i], quote = '"')),
             call. = FALSE)
      }
      c0 <- sf::st_coordinates(suppressWarnings(sf::st_centroid(g)))
      bb <- sf::st_bbox(g)
      has_extent <- bb[["xmax"]] > bb[["xmin"]] || bb[["ymax"]] > bb[["ymin"]]
      out[[i]] <- one(names_[i], c0[1, "X"], c0[1, "Y"],
        if (has_extent) unname(c(bb[["xmin"]], bb[["ymin"]], bb[["xmax"]], bb[["ymax"]])))
    }
    return(out)
  }
  if (is.data.frame(features)) {
    if (!all(c("name", "lon", "lat") %in% names(features))) stop(forms, call. = FALSE)
    return(lapply(seq_len(nrow(features)), function(i) {
      one(features$name[i], features$lon[i], features$lat[i])
    }))
  }
  if (is.list(features) && length(features) > 0 && !is.null(names(features)) &&
      all(nzchar(names(features)))) {
    return(lapply(names(features), function(nm) {
      v <- features[[nm]]
      if (!is.numeric(v) || !length(v) %in% c(2, 6)) stop(forms, call. = FALSE)
      one(nm, v[1], v[2], if (length(v) == 6) v[3:6])
    }))
  }
  stop(forms, call. = FALSE)
}

# A finite double as JSON text (17 significant digits round-trip).
.geo_json_num <- function(x) formatC(x, digits = 17, format = "g")

# The options JSON for the shim. Every value has been validated: numbers are
# finite, names are pic labels and `frame` is one of two words, so nothing
# here needs escaping.
.geo_options_json <- function(frame, anchor, scale, bearing, feats, flatten, view_scale) {
  parts <- character()
  add <- function(key, json) parts <<- c(parts, sprintf('"%s":%s', key, json))
  if (!is.null(frame)) add("frame", sprintf('"%s"', frame))
  if (!is.null(anchor)) {
    a <- .geo_num(anchor, "anchor", 2)
    add("anchor", sprintf("[%s,%s]", .geo_json_num(a[1]), .geo_json_num(a[2])))
  }
  if (!is.null(scale)) add("scale", .geo_json_num(.geo_num(scale, "scale")))
  if (!is.null(bearing)) add("bearing", .geo_json_num(.geo_num(bearing, "bearing")))
  if (!is.null(flatten)) add("flatten", .geo_json_num(.geo_num(flatten, "flatten")))
  if (!is.null(view_scale)) add("view_scale", .geo_json_num(.geo_num(view_scale, "view_scale")))
  if (length(feats)) {
    fs <- vapply(feats, function(f) {
      bbox <- if (is.null(f$bbox)) "" else
        sprintf(',"bbox":[%s]', paste(.geo_json_num(f$bbox), collapse = ","))
      sprintf('{"name":"%s","lon":%s,"lat":%s%s}', f$name,
              .geo_json_num(f$lon), .geo_json_num(f$lat), bbox)
    }, "")
    add("features", sprintf("[%s]", paste(fs, collapse = ",")))
  }
  sprintf("{%s}", paste(parts, collapse = ","))
}
