fixture <- function(name, ext) {
  test_path("fixtures", "geo", paste0(name, ".", ext))
}
read_text <- function(path) paste(readLines(path, warn = FALSE), collapse = "\n")

# Same structure and values, numbers within `tol` (the engine's own guard:
# coordinates to 1e-8 degrees, other numbers to 1e-6).
expect_close <- function(a, b, path = "") {
  if (is.list(a) && is.list(b)) {
    expect_identical(names(a), names(b), label = paste0(path, " names"))
    expect_identical(length(a), length(b), label = paste0(path, " length"))
    for (i in seq_along(a)) {
      key <- if (is.null(names(a))) i else names(a)[i]
      sub <- if (is.null(names(a))) paste0(path, "[", i, "]") else paste0(path, "$", key)
      expect_close(a[[i]], b[[i]], sub)
    }
  } else if (is.numeric(a) && is.numeric(b)) {
    tol <- if (grepl("coordinates", path)) 1e-8 else 1e-6
    expect_true(abs(a - b) <= tol, label = sprintf("%s: %s vs %s", path, a, b))
  } else {
    expect_identical(a, b, label = path)
  }
}

test_that("B3: the engine's geo examples come out as the engine's GeoJSON", {
  skip_if_not_installed("jsonlite")
  for (name in c("arrow-between-features", "callout", "radius", "two-control-points")) {
    gj <- rpic_geojson(read_text(fixture(name, "pic")))
    expect_s3_class(gj, c("geojson", "json"))
    got <- jsonlite::fromJSON(gj, simplifyVector = FALSE)
    want <- jsonlite::fromJSON(read_text(fixture(name, "geojson")), simplifyVector = FALSE)
    expect_close(got, want, name)
  }
})

test_that("registration and warnings ride as attributes", {
  gj <- rpic_geojson(read_text(fixture("two-control-points", "pic")))
  reg <- attr(gj, "registration")
  expect_identical(reg$method, "two_points")
  expect_identical(reg$frame, "enu")
  expect_equal(reg$control_points, 2)
  expect_true(is.numeric(reg$scale_m_per_in) && reg$scale_m_per_in > 0)
  expect_identical(attr(gj, "warnings"), list())
})

test_that("arguments override the source's variables", {
  src <- "geo_lon = 10; geo_lat = 20; geo_scale = 100\nbox"
  reg <- attr(rpic_geojson(src, anchor = c(-34.9, -8.1), scale = 500, bearing = 30,
                           frame = "mercator"), "registration")
  expect_equal(reg$anchor$lon, -34.9)
  expect_equal(reg$anchor$lat, -8.1)
  expect_equal(reg$scale_m_per_in, 500)
  expect_equal(reg$bearing_deg, 30)
  expect_identical(reg$frame, "mercator")
  # an omitted frame leaves the source's geo_frame in force
  reg <- attr(rpic_geojson(paste0(src, "\ngeo_frame = 1")), "registration")
  expect_identical(reg$frame, "mercator")
})

test_that("features: list and data.frame forms, injected and own", {
  feats <- list(Recife = c(-34.8711, -8.0631), Olinda = c(-34.8553, -8.0089))
  gj <- rpic_geojson("geo_lon = -34.8711; geo_lat = -8.0631; geo_scale = 1000
line from Recife to Olinda", features = feats)
  expect_identical(attr(gj, "registration")$method, "two_points")
  expect_identical(attr(gj, "warnings"), list())
  skip_if_not_installed("jsonlite")
  fc <- jsonlite::fromJSON(gj, simplifyVector = FALSE)
  line <- fc$features[[1]]$geometry$coordinates
  expect_equal(unlist(line[[1]]), c(-34.8711, -8.0631), tolerance = 1e-8)
  expect_equal(unlist(line[[length(line)]]), c(-34.8553, -8.0089), tolerance = 1e-8)

  df <- data.frame(name = c("Recife", "Olinda"), lon = c(-34.8711, -34.8553),
                   lat = c(-8.0631, -8.0089))
  gj2 <- rpic_geojson("line from Recife to Olinda", features = df)
  fc2 <- jsonlite::fromJSON(gj2, simplifyVector = FALSE)
  line <- fc2$features[[1]]$geometry$coordinates
  expect_equal(unlist(line[[1]]), c(-34.8711, -8.0631), tolerance = 1e-8)
  expect_equal(unlist(line[[length(line)]]), c(-34.8553, -8.0089), tolerance = 1e-8)

  # a feature the source defines is a control point of its own geometry
  gj3 <- rpic_geojson("A: (0, 0)\nB: (1, 0)\nline from A to B",
                      features = list(A = c(0, 0), B = c(0.01, 0)))
  expect_identical(attr(gj3, "registration")$method, "two_points")
})

test_that("feature names must be pic labels and are never interpolated", {
  expect_error(rpic_geojson("box", features = list(recife = c(0, 0))), "not a pic label")
  expect_error(rpic_geojson("box", features = list(`A: box; B` = c(0, 0))), "not a pic label")
  expect_error(rpic_geojson("box", features = list(A = c(0, NA))), "finite")
  expect_error(rpic_geojson("box", features = "Recife"), "features")
})

test_that("diagnostic positions stay relative to the caller's source", {
  e <- tryCatch(rpic_geojson("box\nbox bad bad(", features = list(Recife = c(0, 0)),
                             anchor = c(0, 0)),
                rpic_error = function(e) e)
  expect_s3_class(e, "rpic_error")
  expect_false(inherits(e, "rpic_geo_error"))
  expect_equal(e$info$line, 2)
  expect_match(conditionMessage(e), "^2:")
})

test_that("B8: a gradient raises an rpic_geo_warning, grouped by kind", {
  src <- 'geo_lon = 0; geo_lat = 0
box gradient "red" "blue"
box gradient "red" "blue"'
  caught <- list()
  gj <- withCallingHandlers(rpic_geojson(src), rpic_geo_warning = function(w) {
    caught[[length(caught) + 1]] <<- w
    invokeRestart("muffleWarning")
  })
  expect_length(caught, 1)
  w <- caught[[1]]
  expect_s3_class(w, "rpic_geo_warning")
  expect_s3_class(w, "rpic_warning")
  expect_identical(w$kind, "unsupported_style")
  expect_identical(w$count, 2L)
  expect_length(attr(gj, "warnings"), 2)
  expect_identical(attr(gj, "warnings")[[1]]$kind, "unsupported_style")
  expect_identical(attr(gj, "warnings")[[1]]$id, "s0")
})

test_that("no registration is an rpic_geo_error with kind and hint", {
  e <- tryCatch(rpic_geojson("box"), rpic_geo_error = function(e) e)
  expect_s3_class(e, "rpic_geo_error")
  expect_s3_class(e, "rpic_error")
  expect_identical(e$info$kind, "no_registration")
  expect_true(is.character(e$info$hint) && nzchar(e$info$hint))
  e <- tryCatch(rpic_geojson("geo_lon = 0; geo_lat = 0\nbox", flatten = -1),
                rpic_geo_error = function(e) e)
  expect_identical(e$info$kind, "invalid_flatten")
})

test_that("a label inside a block does not claim a host feature of the same name", {
  src <- "X: [ B: box ]\narrow from Recife to B"
  # both host features are injected (the block-inner B does not count), so
  # the two of them register the drawing
  gj <- rpic_geojson(src, features = list(Recife = c(-34.8711, -8.0631), B = c(-34.8553, -8.0089)))
  reg <- attr(gj, "registration")
  expect_equal(reg$method, "two_points")
  expect_match(gj, "arrow")
})

test_that("a feature that does not project finitely is a geo error, not a parse error", {
  src <- "geo_lon = 0; geo_lat = 0; geo_scale = 1000\nbox at Pole"
  err <- tryCatch(
    rpic_geojson(src, frame = "mercator",
                 features = data.frame(name = "Pole", lon = 0, lat = 90)),
    rpic_geo_error = function(e) e
  )
  expect_s3_class(err, "rpic_geo_error")
  # the engine refuses the pole itself (invalid_anchor); the shim's own finite
  # check (invalid_feature) is the backstop for anything that slips past
  expect_true(err$info$kind %in% c("invalid_anchor", "invalid_feature"))
})
