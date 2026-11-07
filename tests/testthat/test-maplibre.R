read_pic <- function(name) {
  paste(readLines(test_path("fixtures", "geo", paste0(name, ".pic")), warn = FALSE),
        collapse = "\n")
}
read_geojson <- function(name) {
  structure(paste(readLines(test_path("fixtures", "geo", paste0(name, ".geojson")),
                            warn = FALSE), collapse = "\n"), class = "json")
}
# No test downloads a style: mapgl::maplibre()'s default is a CARTO URL,
# which add_rpic(font = "style") reads. Tests that need a style mock it.
local_mocked_bindings(.fetch_style = function(url, ...) stop("offline (tests)"))

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

test_that("engine 0.16.0 label layout: line height 1, a padded trailing blank row", {
  layers <- rpic_maplibre_layers(rpic_geojson(read_pic("callout")))
  for (l in layers[5:6]) {
    expect_identical(l$layout$`text-line-height`, 1)
    tf <- l$layout$`text-field`
    # a stack that ends in an empty row gets a trailing space, so MapLibre
    # keeps the row (its shaper only breaks before a following character)
    expect_identical(tf[[1]], "case")
    expect_identical(tf[[3]], list("concat", c("get", "geopic:text"), "\u00a0"))
    expect_identical(tf[[4]], c("get", "geopic:text"))
  }
})

test_that("text_scale: 1 is the snapshot, 1.5 is the CLI's --text-scale 1.5", {
  skip_if_not_installed("jsonlite")
  gj <- rpic_geojson(read_pic("callout"))
  expect_identical(rpic_maplibre_layers(gj, text_scale = 1), rpic_maplibre_layers(gj))
  expect_layers(round_trip(rpic_maplibre_layers(gj, text_scale = 1)), snapshot("callout"),
                "callout x1")
  # fixture: `rpic --geojson --maplibre --text-scale 1.5 callout.pic` (engine
  # v0.16.0), its "layers" array
  big <- rpic_maplibre_layers(gj, text_scale = 1.5)
  expect_layers(round_trip(big), snapshot("callout-1.5"), "callout x1.5")
  # only the text sizes move; strokes and dots keep their ground sizes
  one <- rpic_maplibre_layers(gj)
  expect_identical(big[1:4], one[1:4])
  expect_false(identical(big[[5]]$layout$`text-size`, one[[5]]$layout$`text-size`))
  # pic source and `...` with the option
  expect_identical(rpic_maplibre_layers(read_pic("callout"), text_scale = 1.5), big)
  expect_identical(rpic_maplibre_layers("box", anchor = c(-34.9, -8.1), text_scale = 2),
                   rpic_maplibre_layers(rpic_geojson("box", anchor = c(-34.9, -8.1)),
                                        text_scale = 2))
})

test_that("an invalid text_scale is an invalid_options geo error", {
  gj <- rpic_geojson(read_pic("callout"))
  for (k in list(0, -1, 16.5, 20, Inf, NaN, NA_real_, "big", c(1, 2), numeric(0), NULL)) {
    err <- tryCatch(rpic_maplibre_layers(gj, text_scale = k), rpic_geo_error = function(e) e)
    expect_s3_class(err, "rpic_error")
    expect_identical(err$info$kind, "invalid_options")
    expect_match(conditionMessage(err), "text_scale must be a finite number in \\(0, 16\\]")
    expect_identical(err$call[[1]], quote(rpic_maplibre_layers))
  }
  expect_length(rpic_maplibre_layers(gj, text_scale = 16), 6)
  expect_length(rpic_maplibre_layers(gj, text_scale = 1L), 6)
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

test_that("add_rpic adds the pic source, the six layers and the bounds", {
  skip_if_not_installed("mapgl")
  src <- read_pic("radius")
  gj <- rpic_geojson(src)
  m <- add_rpic(mapgl::maplibre(), src)
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
  m2 <- add_rpic(mapgl::mapboxgl(access_token = "pk.test"), gj, fit = FALSE)
  expect_s3_class(m2, "mapboxgl")
  expect_null(m2$x$fitBounds)
  expect_identical(vapply(m2$x$layers, function(l) l$id, ""), ids)
  skip_if_not_installed("sf")
  m3 <- add_rpic(mapgl::maplibre(), rpic_sf(src))
  expect_identical(m3$x$sources, m$x$sources)
  expect_identical(m3$x$layers, m$x$layers)
})

test_that("add_rpic refuses a second drawing on the same map", {
  skip_if_not_installed("mapgl")
  src <- read_pic("radius")
  m <- add_rpic(mapgl::maplibre(), src)
  expect_error(add_rpic(m, src), "already has \"pic\".*one pic drawing")
  # a foreign "pic" source, or a layer with one of the ids, clashes too
  m2 <- mapgl::maplibre()
  m2$x$sources <- list(list(id = "pic", type = "geojson", data = "x"))
  expect_error(add_rpic(m2, src), "one pic drawing")
  m3 <- mapgl::add_layer(mapgl::maplibre(), "pic-dot", "circle", source = "other")
  expect_error(add_rpic(m3, src), "already has \"pic-dot\"")
})

geometry_ids <- ids[1:4]
before_ids <- function(m) {
  vapply(m$x$layers, function(l) if (is.null(l$before_id)) NA_character_ else l$before_id, "")
}
style_list <- function(...) {
  list(version = 8, sources = list(), layers = list(...))
}
# Style URLs are memoised per session: each test that mocks the download
# starts from an empty cache (the URLs are example.org ones, used only here).
clear_style_cache <- function() {
  cache <- get(".style_cache", envir = asNamespace("rpic"))
  rm(list = ls(cache, all.names = TRUE), envir = cache)
}

test_that("add_rpic before = NULL appends all six layers", {
  skip_if_not_installed("mapgl")
  m <- add_rpic(mapgl::maplibre(style = style_list(list(id = "names", type = "symbol"))),
                  read_pic("radius"))
  expect_identical(before_ids(m), rep(NA_character_, 6))
})

test_that("add_rpic before = \"labels\": geometry under the label block, labels on top", {
  skip_if_not_installed("mapgl")
  src <- read_pic("radius")
  st <- style_list(list(id = "bg", type = "background"), list(id = "water", type = "fill"),
                   list(id = "road-names", type = "symbol"),
                   list(id = "place-names", type = "symbol"))
  m <- add_rpic(mapgl::maplibre(style = st), src, before = "labels")
  expect_identical(vapply(m$x$layers, function(l) l$id, ""), ids)
  expect_identical(before_ids(m), c(rep("road-names", 4), NA, NA))
  # a layer literally named `labels` wins over the label block
  st2 <- style_list(list(id = "road-names", type = "symbol"), list(id = "labels", type = "fill"))
  m2 <- add_rpic(mapgl::maplibre(style = st2), src, before = "labels")
  expect_identical(before_ids(m2), c(rep("labels", 4), NA, NA))
  # a style without symbol layers: on top, silently
  st3 <- style_list(list(id = "water", type = "fill"))
  expect_no_warning(m3 <- add_rpic(mapgl::maplibre(style = st3), src, before = "labels"))
  expect_identical(before_ids(m3), rep(NA_character_, 6))
  # a symbol layer the user added to the map counts too
  m4 <- mapgl::add_layer(mapgl::maplibre(style = st3), "my-names", "symbol", source = "x")
  m4 <- add_rpic(m4, src, before = "labels")
  expect_identical(before_ids(m4)[-1], c(rep("my-names", 4), NA, NA))
})

test_that("add_rpic before = \"labels\": the start of the trailing label block, not the first symbol", {
  skip_if_not_installed("mapgl")
  src <- read_pic("radius")
  # (a) CARTO positron's shape: an early symbol layer before roads and buildings
  st <- style_list(list(id = "bg", type = "background"), list(id = "water", type = "fill"),
                   list(id = "waterway_label", type = "symbol"),
                   list(id = "road", type = "line"), list(id = "building", type = "fill"),
                   list(id = "road_shield", type = "symbol"),
                   list(id = "place_city", type = "symbol"))
  m <- add_rpic(mapgl::maplibre(style = st), src, before = "labels")
  expect_identical(before_ids(m), c(rep("road_shield", 4), NA, NA))
  # (b) one trailing symbol layer after the last geometry
  st_b <- style_list(list(id = "water", type = "fill"), list(id = "names", type = "symbol"),
                     list(id = "building", type = "fill"),
                     list(id = "place_city", type = "symbol"))
  m_b <- add_rpic(mapgl::maplibre(style = st_b), src, before = "labels")
  expect_identical(before_ids(m_b), c(rep("place_city", 4), NA, NA))
  # (c) no trailing symbols: appended, silently
  st_c <- style_list(list(id = "names", type = "symbol"), list(id = "building", type = "fill"))
  expect_no_warning(m_c <- add_rpic(mapgl::maplibre(style = st_c), src, before = "labels"))
  expect_identical(before_ids(m_c), rep(NA_character_, 6))
  # (d) a layer literally named `labels` still wins
  st_d <- style_list(list(id = "water", type = "fill"), list(id = "labels", type = "symbol"),
                     list(id = "road", type = "line"), list(id = "place_city", type = "symbol"))
  m_d <- add_rpic(mapgl::maplibre(style = st_d), src, before = "labels")
  expect_identical(before_ids(m_d), c(rep("labels", 4), NA, NA))
  # an added geometry layer after the style's labels closes the block: on top
  m_g <- mapgl::add_layer(mapgl::maplibre(style = st_b), "mine", "fill", source = "x")
  m_g <- add_rpic(m_g, src, before = "labels")
  expect_identical(before_ids(m_g)[-1], rep(NA_character_, 6))
  # an id-less geometry layer still counts as geometry
  st_n <- style_list(list(id = "a", type = "symbol"), list(type = "fill"),
                     list(id = "b", type = "symbol"))
  m_n <- add_rpic(mapgl::maplibre(style = st_n), src, before = "labels")
  expect_identical(before_ids(m_n), c(rep("b", 4), NA, NA))
})

test_that("add_rpic before = \"labels\" finds the trailing block of a fetched style", {
  skip_if_not_installed("mapgl")
  skip_if_not_installed("jsonlite")
  clear_style_cache()
  local_mocked_bindings(.fetch_style = function(url, ...) {
    style_list(list(id = "water", type = "fill"), list(id = "waterway_label", type = "symbol"),
               list(id = "road", type = "line"), list(id = "place_city", type = "symbol"),
               list(id = "place_town", type = "symbol"))
  })
  m <- add_rpic(mapgl::maplibre(style = "https://example.org/trailing.json"),
                read_pic("radius"), before = "labels")
  expect_identical(before_ids(m), c(rep("place_city", 4), NA, NA))
})

test_that("add_rpic before = \"labels\" fetches a style URL once", {
  skip_if_not_installed("mapgl")
  skip_if_not_installed("jsonlite")
  clear_style_cache()
  fetched <- character()
  local_mocked_bindings(.fetch_style = function(url, ...) {
    fetched <<- c(fetched, url)
    style_list(list(id = "water", type = "fill"), list(id = "place_city", type = "symbol"))
  })
  url <- "https://example.org/style.json"
  m <- add_rpic(mapgl::maplibre(style = url), read_pic("radius"), before = "labels")
  expect_identical(fetched, url)
  expect_identical(before_ids(m), c(rep("place_city", 4), NA, NA))
  # a second map with the same style: no second download
  m2 <- add_rpic(mapgl::maplibre(style = url), read_pic("callout"), before = "labels")
  expect_identical(fetched, url)
  expect_identical(before_ids(m2), c(rep("place_city", 4), NA, NA))
  # a failed download is not cached
  clear_style_cache()
  n <- 0
  local_mocked_bindings(.fetch_style = function(url, ...) {
    n <<- n + 1
    stop("offline")
  })
  for (i in 1:2) {
    expect_warning(add_rpic(mapgl::maplibre(style = url), read_pic("radius"),
                              before = "labels"), "offline")
  }
  expect_identical(n, 2)
})

test_that("add_rpic reads a style list from jsonlite's default simplification", {
  skip_if_not_installed("mapgl")
  skip_if_not_installed("jsonlite")
  json <- jsonlite::toJSON(style_list(
    list(id = "bg", type = "background", paint = list(`background-color` = "#fff")),
    list(id = "water", type = "fill", source = "osm"),
    list(id = "place_city", type = "symbol", source = "osm")
  ), auto_unbox = TRUE)
  st <- jsonlite::fromJSON(json)            # simplifyVector = TRUE
  expect_s3_class(st$layers, "data.frame")
  m <- add_rpic(mapgl::maplibre(style = st), read_pic("radius"), before = "labels")
  expect_identical(before_ids(m), c(rep("place_city", 4), NA, NA))
  m2 <- add_rpic(mapgl::maplibre(style = st), read_pic("radius"), before = "water")
  expect_identical(before_ids(m2), c(rep("water", 4), NA, NA))
  # the same through a URL whose download simplifies
  clear_style_cache()
  local_mocked_bindings(.fetch_style = function(url, ...) jsonlite::fromJSON(json))
  m3 <- add_rpic(mapgl::maplibre(style = "https://example.org/df.json"),
                   read_pic("radius"), before = "labels")
  expect_identical(before_ids(m3), c(rep("place_city", 4), NA, NA))
})

test_that("add_rpic: a list style without layers warns; layers without an id are skipped", {
  skip_if_not_installed("mapgl")
  src <- read_pic("radius")
  expect_warning(m <- add_rpic(mapgl::maplibre(style = list(version = 8, sources = list())),
                                 src, before = "labels"),
                 "could not read the map's style.*no `layers` array")
  expect_identical(before_ids(m), rep(NA_character_, 6))
  # a symbol layer without an id is never a target: the next one is
  st <- style_list(list(type = "symbol"), list(id = NA, type = "symbol"),
                   list(id = "names", type = "symbol"))
  m2 <- add_rpic(mapgl::maplibre(style = st), src, before = "labels")
  expect_identical(before_ids(m2), c(rep("names", 4), NA, NA))
  # only id-less symbol layers: on top, no NA before_id
  st2 <- style_list(list(type = "symbol"))
  m3 <- add_rpic(mapgl::maplibre(style = st2), src, before = "labels")
  expect_identical(before_ids(m3), rep(NA_character_, 6))
})

test_that("add_rpic before = \"labels\" consults the map's added layers when the style is unreadable", {
  skip_if_not_installed("mapgl")
  src <- read_pic("radius")
  # mapboxgl()'s default style is NULL
  mb <- mapgl::mapboxgl(access_token = "pk.test")
  expect_null(mb$x$style)
  expect_warning(m <- add_rpic(mb, src, before = "labels"),
                 "the map's default style cannot be read here")
  expect_identical(before_ids(m), rep(NA_character_, 6))
  # an added symbol layer answers without the style
  mb2 <- mapgl::add_layer(mapgl::mapboxgl(access_token = "pk.test"), "my-names", "symbol",
                          source = "x")
  expect_no_warning(m2 <- add_rpic(mb2, src, before = "labels"))
  expect_identical(before_ids(m2)[-1], c(rep("my-names", 4), NA, NA))
  # an added layer literally named `labels` wins
  mb3 <- mapgl::add_layer(mapgl::mapboxgl(access_token = "pk.test"), "names", "symbol",
                          source = "x")
  mb3 <- mapgl::add_layer(mb3, "labels", "fill", source = "x")
  m3 <- add_rpic(mb3, src, before = "labels")
  expect_identical(before_ids(m3)[-(1:2)], c(rep("labels", 4), NA, NA))
})

test_that("add_rpic before = \"labels\" warns and appends when the style cannot be read", {
  skip_if_not_installed("mapgl")
  skip_if_not_installed("jsonlite")
  src <- read_pic("radius")
  clear_style_cache()
  local_mocked_bindings(.fetch_style = function(url, ...) stop("cannot open the connection"))
  expect_warning(m <- add_rpic(mapgl::maplibre(style = "https://example.org/s.json"), src,
                                 before = "labels"),
                 "could not read the map's style.*cannot open the connection.*on top")
  expect_identical(before_ids(m), rep(NA_character_, 6))
  # not a downloadable URL (a mapbox:// style): no fetch, a warning
  local_mocked_bindings(.fetch_style = function(url, ...) stop("must not be called"))
  expect_warning(m2 <- add_rpic(mapgl::mapboxgl(style = "mapbox://styles/mapbox/light-v11",
                                                  access_token = "pk.test"),
                                  src, before = "labels"),
                 "cannot download a style from \"mapbox://")
  expect_identical(before_ids(m2), rep(NA_character_, 6))
})

test_that("add_rpic before = <layer id>", {
  skip_if_not_installed("mapgl")
  src <- read_pic("radius")
  st <- style_list(list(id = "water", type = "fill"), list(id = "roads", type = "line"))
  m <- add_rpic(mapgl::maplibre(style = st), src, before = "roads")
  expect_identical(before_ids(m), c(rep("roads", 4), NA, NA))
  # a layer added to the map before is a target too (no style needed)
  clear_style_cache()
  local_mocked_bindings(.fetch_style = function(url, ...) stop("must not be called"))
  m2 <- mapgl::add_layer(mapgl::maplibre(style = "https://example.org/s.json"),
                         "mine", "fill", source = "x")
  m2 <- add_rpic(m2, src, before = "mine", font = "spec")  # font = "style" reads the style
  expect_identical(before_ids(m2)[-1], c(rep("mine", 4), NA, NA))
  # an id the style does not have: a warning, on top
  expect_warning(m3 <- add_rpic(mapgl::maplibre(style = st), src, before = "nope"),
                 "no layer \"nope\"")
  expect_identical(before_ids(m3), rep(NA_character_, 6))
  # a style that cannot be read: the id is used, with a warning that it is unchecked
  clear_style_cache()
  local_mocked_bindings(.fetch_style = function(url, ...) stop("offline"))
  expect_warning(
    m4 <- add_rpic(mapgl::maplibre(style = "https://example.org/s.json"), src,
                     before = "roads"),
    "could not read the map's style to check that it has a layer \"roads\".*offline.*drops"
  )
  expect_identical(before_ids(m4), c(rep("roads", 4), NA, NA))
  expect_warning(m5 <- add_rpic(mapgl::mapboxgl(access_token = "pk.test"), src,
                                  before = "roads"), "default style cannot be read")
  expect_identical(before_ids(m5), c(rep("roads", 4), NA, NA))
  # bad values
  expect_error(add_rpic(mapgl::maplibre(), src, before = c("a", "b")), "`before` must be")
  expect_error(add_rpic(mapgl::maplibre(), src, before = 1), "`before` must be")
  expect_error(add_rpic(mapgl::maplibre(), src, before = ""), "`before` must be")
})

test_that("add_rpic text_scale reaches the layers", {
  skip_if_not_installed("mapgl")
  src <- read_pic("callout")
  m <- add_rpic(mapgl::maplibre(), src, text_scale = 1.5, fit = FALSE)
  big <- rpic_maplibre_layers(src, text_scale = 1.5)
  expect_identical(m$x$layers[[5]]$layout, big[[5]]$layout)
  expect_identical(m$x$layers[[6]]$layout, big[[6]]$layout)
  expect_error(add_rpic(mapgl::maplibre(), src, text_scale = 0), class = "rpic_geo_error")
})

test_that("add_rpic refuses what is not a mapgl map", {
  skip_if_not_installed("mapgl")
  expect_error(add_rpic(list(), "box"), "must be a map")
  expect_error(add_rpic(structure(list(), class = "maplibre_proxy"), "box"), "proxies")
})

test_that("add_rpic without mapgl says how to install it", {
  local_mocked_bindings(.has_mapgl = function() FALSE)
  expect_error(add_rpic(NULL, "box"), "install.packages\\(\"mapgl\"\\)")
})

# A CARTO-positron-shaped style: SemiBold stacks are the most common, the
# upright Medium/Regular one is the body font.
carto_like <- function() {
  stk <- function(...) list(...)
  style_list(
    list(id = "water", type = "fill"),
    list(id = "waterway_label", type = "symbol",
         layout = list(`text-font` = stk("Montserrat Regular Italic", "Open Sans Italic",
                                         "Noto Sans Regular"))),
    list(id = "road", type = "line"),
    list(id = "place_suburbs", type = "symbol",
         layout = list(`text-font` = stk("Montserrat Medium", "Open Sans Regular",
                                         "Noto Sans Regular"))),
    list(id = "place_town", type = "symbol",
         layout = list(`text-font` = stk("Montserrat Medium", "Open Sans Regular",
                                         "Noto Sans Regular"))),
    list(id = "place_city", type = "symbol",
         layout = list(`text-font` = stk("Montserrat SemiBold", "Open Sans Bold",
                                         "Noto Sans Regular"))),
    list(id = "place_country", type = "symbol",
         layout = list(`text-font` = stk("Montserrat SemiBold", "Open Sans Bold",
                                         "Noto Sans Regular"))),
    list(id = "place_state", type = "symbol",
         layout = list(`text-font` = stk("Montserrat SemiBold", "Open Sans Bold",
                                         "Noto Sans Regular"))),
    # an expression is not a stack
    list(id = "poi", type = "symbol",
         layout = list(`text-font` = list("literal", list("X Regular"))))
  )
}
text_fonts <- function(m) {
  lapply(Filter(function(l) l$id %in% c("pic-text", "pic-title"), m$x$layers),
         function(l) l$layout[["text-font"]])
}
body_stack <- list("Montserrat Medium", "Open Sans Regular", "Noto Sans Regular")

test_that("add_rpic font = \"style\" uses the style's upright body font", {
  skip_if_not_installed("mapgl")
  src <- read_pic("radius")
  m <- add_rpic(mapgl::maplibre(style = carto_like()), src)
  expect_identical(text_fonts(m), list(body_stack, body_stack))
  # geometry layers untouched; the rest of the label layout is the spec's
  spec <- rpic_maplibre_layers(rpic_geojson(src))
  lay <- m$x$layers[[5]]$layout
  lay[["text-font"]] <- spec[[5]]$layout[["text-font"]]
  expect_identical(lay, spec[[5]]$layout)
  expect_identical(m$x$layers[[1]], add_rpic(mapgl::maplibre(style = carto_like()), src,
                                             font = "spec")$x$layers[[1]])
  # ties among the most common go to the first in style order; without an
  # upright Regular/Medium stack, the most common of all
  st <- style_list(
    list(id = "a", type = "symbol", layout = list(`text-font` = list("A Bold"))),
    list(id = "b", type = "symbol", layout = list(`text-font` = list("B Black"))),
    list(id = "c", type = "symbol", layout = list(`text-font` = list("B Black"))))
  expect_identical(text_fonts(add_rpic(mapgl::maplibre(style = st), src))[[1]], list("B Black"))
  st2 <- style_list(
    list(id = "a", type = "symbol", layout = list(`text-font` = list("A Regular"))),
    list(id = "b", type = "symbol", layout = list(`text-font` = list("B Medium"))))
  expect_identical(text_fonts(add_rpic(mapgl::maplibre(style = st2), src))[[1]], list("A Regular"))
})

test_that("add_rpic font: \"spec\", an explicit stack, styles without fonts", {
  skip_if_not_installed("mapgl")
  src <- read_pic("radius")
  spec <- rpic_maplibre_layers(rpic_geojson(src))
  noto <- spec[[5]]$layout[["text-font"]]
  m <- add_rpic(mapgl::maplibre(style = carto_like()), src, font = "spec")
  expect_identical(text_fonts(m), list(noto, noto))
  m2 <- add_rpic(mapgl::maplibre(style = carto_like()), src,
                 font = c("Open Sans Regular", "Arial Unicode MS Regular"))
  expect_identical(text_fonts(m2)[[1]], list("Open Sans Regular", "Arial Unicode MS Regular"))
  # a one-name stack stays a JSON array
  m3 <- add_rpic(mapgl::maplibre(style = carto_like()), src, font = "Open Sans Regular")
  skip_if_not_installed("jsonlite")
  expect_match(as.character(jsonlite::toJSON(m3$x$layers[[5]]$layout["text-font"],
                                             auto_unbox = TRUE)),
               "\\[\"Open Sans Regular\"\\]", fixed = FALSE)
  # no symbol layers / no stacks: the spec's font, silently
  st <- style_list(list(id = "water", type = "fill"))
  expect_no_warning(m4 <- add_rpic(mapgl::maplibre(style = st), src))
  expect_identical(text_fonts(m4), list(noto, noto))
  # an unreadable style: the spec's font, no warning of its own
  expect_no_warning(m5 <- add_rpic(mapgl::mapboxgl(access_token = "pk.test"), src))
  expect_identical(text_fonts(m5), list(noto, noto))
  expect_error(add_rpic(mapgl::maplibre(style = st), src, font = NA_character_), "`font` must be")
  expect_error(add_rpic(mapgl::maplibre(style = st), src, font = character()), "`font` must be")
  expect_error(add_rpic(mapgl::maplibre(style = st), src, font = 1), "`font` must be")
})

test_that("add_rpic font = \"style\" reads a fetched style once, data-frame layers too", {
  skip_if_not_installed("mapgl")
  skip_if_not_installed("jsonlite")
  clear_style_cache()
  n <- 0
  json <- jsonlite::toJSON(carto_like(), auto_unbox = TRUE)
  local_mocked_bindings(.fetch_style = function(url, ...) {
    n <<- n + 1
    jsonlite::fromJSON(json)           # layers as a data frame
  })
  m <- add_rpic(mapgl::maplibre(style = "https://example.org/carto.json"), read_pic("radius"),
                before = "labels")
  expect_identical(n, 1)
  expect_identical(lapply(text_fonts(m), unlist), list(unlist(body_stack), unlist(body_stack)))
  expect_identical(before_ids(m), c(rep("place_suburbs", 4), NA, NA))
  # an unreadable URL is tried once per call, for `before` and `font` alike
  clear_style_cache()
  n <- 0
  local_mocked_bindings(.fetch_style = function(url, ...) {
    n <<- n + 1
    stop("offline")
  })
  expect_warning(add_rpic(mapgl::maplibre(style = "https://example.org/carto.json"),
                          read_pic("radius"), before = "labels"), "offline")
  expect_identical(n, 1)
})
