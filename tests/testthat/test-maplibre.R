read_pic <- function(name) {
  paste(readLines(test_path("fixtures", "geo", paste0(name, ".pic")), warn = FALSE),
        collapse = "\n")
}
read_geojson <- function(name) {
  structure(paste(readLines(test_path("fixtures", "geo", paste0(name, ".geojson")),
                            warn = FALSE), collapse = "\n"), class = "json")
}
snapshot <- function(name) {
  jsonlite::fromJSON(test_path("fixtures", "geo", "maplibre", paste0(name, ".layers.json")),
                     simplifyVector = FALSE)
}
# What htmlwidgets does to the specs (auto_unbox), read back as plain lists.
round_trip <- function(x) {
  jsonlite::fromJSON(jsonlite::toJSON(x, auto_unbox = TRUE, digits = NA),
                     simplifyVector = FALSE)
}
# Deep equality with object keys in any order, numbers within a relative 1e-9
# (px per metre comes from cos(lat): last-bit libm noise only).
expect_layers <- function(a, b, path = "") {
  if (is.list(a) && is.list(b)) {
    if (!is.null(names(a)) || !is.null(names(b))) {
      expect_setequal(names(a), names(b))
      for (k in names(b)) expect_layers(a[[k]], b[[k]], paste0(path, "$", k))
    } else {
      expect_identical(length(a), length(b), label = paste0(path, " length"))
      for (i in seq_along(b)) expect_layers(a[[i]], b[[i]], paste0(path, "[", i, "]"))
    }
  } else if (is.numeric(a) && is.numeric(b)) {
    expect_true(abs(a - b) <= 1e-9 * max(1, abs(b)), label = sprintf("%s: %s vs %s", path, a, b))
  } else {
    expect_identical(a, b, label = path)
  }
}

ids <- c("pic-fill", "pic-stroke", "pic-stroke-dashed", "pic-dot", "pic-text", "pic-title")

test_that("the layers are the engine's snapshots, through a JSON round trip", {
  skip_if_not_installed("jsonlite")
  for (name in c("arrow-between-features", "callout", "radius", "two-control-points")) {
    layers <- rpic_maplibre_layers(rpic_geojson(read_pic(name)))
    expect_identical(vapply(layers, function(l) l$id, ""), ids)
    expect_true(all(vapply(layers, function(l) identical(l$source, "pic"), NA)))
    expect_layers(round_trip(layers), snapshot(name), name)
  }
  # the engine's committed collections, read as JSON text, give the same layers
  expect_layers(round_trip(rpic_maplibre_layers(read_geojson("callout"))),
                snapshot("callout"), "callout.geojson")
  # mercator: cos(lat) drops out; an empty collection takes the defaults
  merc <- sub('"frame":"enu"', '"frame":"mercator"', read_geojson("callout"), fixed = TRUE)
  expect_false(identical(merc, unclass(read_geojson("callout"))))
  expect_layers(round_trip(rpic_maplibre_layers(structure(merc, class = "json"))),
                snapshot("callout-mercator"), "callout-mercator")
  empty <- structure('{"type":"FeatureCollection","features":[]}', class = "json")
  expect_layers(round_trip(rpic_maplibre_layers(empty)), snapshot("empty"), "empty")
})

test_that("one-element arrays stay lists; keys come in reading order", {
  layers <- rpic_maplibre_layers(rpic_geojson(read_pic("callout")))
  lw <- layers[[2]]$paint$`line-width`
  expect_identical(lw[[1]], "interpolate")
  expect_identical(lw[[2]], list("exponential", 2))
  expect_identical(lw[[3]], list("zoom"))
  expect_identical(layers[[1]]$filter, list("==", list("geometry-type"), "Polygon"))
  expect_identical(names(layers[[1]])[1:3], c("id", "type", "source"))
  # engine 0.15.1: pic-title draws the `title` point features
  expect_identical(layers[[6]]$filter, list("==", c("get", "geopic:kind"), "title"))
})

test_that("pic source and rpic_sf() input give the same layers", {
  src <- read_pic("arrow-between-features")
  want <- rpic_maplibre_layers(rpic_geojson(src))
  expect_identical(rpic_maplibre_layers(src), want)
  # `...` reaches rpic_geojson()
  expect_identical(rpic_maplibre_layers("box", anchor = c(-34.9, -8.1), scale = 400),
                   rpic_maplibre_layers(rpic_geojson("box", anchor = c(-34.9, -8.1), scale = 400)))
  # unclassed GeoJSON text is the collection, not pic source
  expect_identical(rpic_maplibre_layers(as.character(rpic_geojson(src))), want)
  expect_identical(rpic_maplibre_layers(paste0("\n  ", as.character(rpic_geojson(src)))), want)
  expect_error(rpic_maplibre_layers('{"type":"Feature"}'), class = "rpic_geo_error")
  skip_if_not_installed("sf")
  x <- rpic_sf(src)
  expect_identical(rpic_maplibre_layers(x), want)
  # the stored GeoJSON is the engine's own text
  expect_identical(as.character(attr(x, "geojson")), as.character(rpic_geojson(src)))
})

test_that("conditions from pic source report the caller's call", {
  err <- tryCatch(rpic_maplibre_layers("box"), rpic_geo_error = function(e) e)
  expect_identical(err$call, quote(rpic_maplibre_layers("box")))
  err <- tryCatch(rpic_maplibre_layers("geo_lon = 0; geo_lat = 0\nbox wid"),
                  rpic_error = function(e) e)
  expect_identical(err$call[[1]], quote(rpic_maplibre_layers))
  src <- "geo_lon = 0; geo_lat = 0\nbox gradient \"red\" \"blue\""
  w <- tryCatch(rpic_maplibre_layers(src), rpic_geo_warning = function(w) w)
  expect_s3_class(w, "rpic_warning")
  expect_identical(w$call[[1]], quote(rpic_maplibre_layers))
  # the warning is raised once and the layers still come back
  ws <- list()
  layers <- withCallingHandlers(rpic_maplibre_layers(src), rpic_geo_warning = function(w) {
    ws[[length(ws) + 1]] <<- w
    invokeRestart("muffleWarning")
  })
  expect_length(layers, 6)
  expect_length(ws, 1)
})

test_that("invalid input errors", {
  bad <- structure('{"type":"Feature"}', class = "json")
  err <- tryCatch(rpic_maplibre_layers(bad), rpic_geo_error = function(e) e)
  expect_s3_class(err, "rpic_error")
  expect_identical(err$info$kind, "invalid_geojson")
  expect_error(rpic_maplibre_layers(structure("nope", class = "json")), class = "rpic_geo_error")
  expect_error(rpic_maplibre_layers(42), "must be an rpic_geojson")
  expect_error(rpic_maplibre_layers(c("box", "circle")), "must be an rpic_geojson")
  expect_error(rpic_maplibre_layers("box"), class = "rpic_geo_error")   # no registration
  expect_error(rpic_maplibre_layers(read_geojson("callout"), scale = 2), "apply only")
  skip_if_not_installed("sf")
  x <- rpic_sf(read_pic("callout"))
  expect_error(rpic_maplibre_layers(x[1:2, ]), "has 2 rows")
  attr(x, "geojson") <- NULL
  expect_error(rpic_maplibre_layers(x), "carries no engine GeoJSON")
})

test_that("rpic_mapgl adds the pic source, the six layers and the bounds", {
  skip_if_not_installed("mapgl")
  src <- read_pic("radius")
  gj <- rpic_geojson(src)
  m <- rpic_mapgl(mapgl::maplibre(), src)
  expect_s3_class(m, "maplibregl")
  expect_identical(vapply(m$x$sources, function(s) s$id, ""), "pic")
  expect_identical(m$x$sources[[1]]$type, "geojson")
  expect_identical(as.character(m$x$sources[[1]]$data), as.character(gj))
  expect_identical(vapply(m$x$layers, function(l) l$id, ""), ids)
  expect_true(all(vapply(m$x$layers, function(l) identical(l$source, "pic"), NA)))
  layers <- rpic_maplibre_layers(gj)
  expect_identical(m$x$layers[[2]]$paint, layers[[2]]$paint)
  expect_identical(m$x$layers[[5]]$layout, layers[[5]]$layout)
  expect_identical(m$x$layers[[1]]$filter, layers[[1]]$filter)
  bb <- m$x$fitBounds$bounds
  expect_identical(m$x$fitBounds$options$padding, 48)
  expect_length(bb, 4)
  expect_true(bb[1] < bb[3] && bb[2] < bb[4])
  expect_true(bb[1] < -34.8711 && bb[3] > -34.8711)
  # the widget's JSON carries the collection verbatim and the arrays intact
  skip_if_not_installed("jsonlite")
  # (htmlwidgets' own serialiser options)
  json <- jsonlite::fromJSON(jsonlite::toJSON(m$x, auto_unbox = TRUE, json_verbatim = TRUE,
                                              null = "null", na = "null", force = TRUE,
                                              digits = 16, use_signif = TRUE),
                             simplifyVector = FALSE)
  expect_identical(json$sources[[1]]$data$type, "FeatureCollection")
  expect_identical(json$layers[[2]]$paint$`line-width`[[3]], list("zoom"))

  # no fit, and a mapboxgl map, and the sf input
  m2 <- rpic_mapgl(mapgl::mapboxgl(access_token = "pk.test"), gj, fit = FALSE)
  expect_s3_class(m2, "mapboxgl")
  expect_null(m2$x$fitBounds)
  expect_identical(vapply(m2$x$layers, function(l) l$id, ""), ids)
  skip_if_not_installed("sf")
  m3 <- rpic_mapgl(mapgl::maplibre(), rpic_sf(src))
  expect_identical(m3$x$sources, m$x$sources)
  expect_identical(m3$x$layers, m$x$layers)
})

test_that("rpic_mapgl refuses a second drawing on the same map", {
  skip_if_not_installed("mapgl")
  src <- read_pic("radius")
  m <- rpic_mapgl(mapgl::maplibre(), src)
  expect_error(rpic_mapgl(m, src), "already has \"pic\".*one pic drawing")
  # a foreign "pic" source, or a layer with one of the ids, clashes too
  m2 <- mapgl::maplibre()
  m2$x$sources <- list(list(id = "pic", type = "geojson", data = "x"))
  expect_error(rpic_mapgl(m2, src), "one pic drawing")
  m3 <- mapgl::add_layer(mapgl::maplibre(), "pic-dot", "circle", source = "other")
  expect_error(rpic_mapgl(m3, src), "already has \"pic-dot\"")
})

test_that("rpic_mapgl refuses what is not a mapgl map", {
  skip_if_not_installed("mapgl")
  expect_error(rpic_mapgl(list(), "box"), "must be a map")
  expect_error(rpic_mapgl(structure(list(), class = "maplibre_proxy"), "box"), "proxies")
})

test_that("rpic_mapgl without mapgl says how to install it", {
  local_mocked_bindings(.has_mapgl = function() FALSE)
  expect_error(rpic_mapgl(NULL, "box"), "install.packages\\(\"mapgl\"\\)")
})
