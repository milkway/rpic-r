test_that("B4: rpic_sf is EPSG:4326 with the documented columns", {
  skip_if_not_installed("sf")
  src <- paste(readLines(test_path("fixtures", "geo", "callout.pic")), collapse = "\n")
  x <- rpic_sf(src)
  expect_s3_class(x, "sf")
  expect_equal(sf::st_crs(x)$epsg, 4326L)
  expect_true(all(c("stroke", "stroke_width", "fill", "geopic_id", "geopic_kind",
                    "geopic_placement", "geopic_schema") %in% names(x)))
  expect_false(any(grepl("[:.-]", names(x))))
  expect_identical(names(x), make.names(names(x)))
  expect_identical(attr(x, "sf_column"), "geometry")
  # engine 0.15.1: a shape with text gains a `title` point feature
  expect_identical(x$geopic_kind, c("dot", "box", "title", "arrow", "arrowhead"))
  t <- x[x$geopic_kind == "title", ]
  expect_identical(t$geopic_for, "s1")
  expect_identical(t$geopic_id, "s1:title")
  expect_identical(t$title, "Marco Zero\nRecife")
  expect_identical(as.character(sf::st_geometry_type(t)), "POINT")
  # arrowheads no longer carry the shape's text
  expect_true(is.na(x$title[x$geopic_kind == "arrowhead"]))
  expect_identical(attr(x, "registration")$method, "anchor")
})

test_that("B4: sf features are placed at their centroids, with their extent", {
  skip_if_not_installed("sf")
  square <- function(x0, y0, d) {
    sf::st_polygon(list(rbind(c(x0, y0), c(x0 + d, y0), c(x0 + d, y0 + d),
                              c(x0, y0 + d), c(x0, y0))))
  }
  polys <- sf::st_sf(
    name = c("West", "East"),
    geometry = sf::st_sfc(square(-35.00, -8.10, 0.02), square(-34.90, -8.05, 0.02),
                          crs = 4326)
  )
  cent <- sf::st_coordinates(sf::st_centroid(sf::st_geometry(polys)))
  x <- rpic_sf("line from West to East\nbox at West.n wid 0.1 ht 0.1",
               features = polys)
  expect_identical(attr(x, "registration")$method, "two_points")
  line <- sf::st_coordinates(sf::st_geometry(x)[x$geopic_kind == "line"][[1]])
  expect_equal(unname(line[1, 1:2]), unname(cent[1, ]), tolerance = 1e-7)
  expect_equal(unname(line[nrow(line), 1:2]), unname(cent[2, ]), tolerance = 1e-7)
  # West.n is the top of the injected invisible box spanning the polygon
  box <- sf::st_coordinates(sf::st_centroid(sf::st_geometry(x)[x$geopic_kind == "box"][[1]]))
  expect_equal(unname(box[1, "Y"]), -8.08, tolerance = 1e-4)

  # name_col and a projected CRS
  names(polys)[1] <- "county"
  utm <- sf::st_transform(polys, 32725)
  y <- rpic_sf("line from West to East", features = utm, name_col = "county")
  line <- sf::st_coordinates(sf::st_geometry(y)[y$geopic_kind == "line"][[1]])
  expect_equal(unname(line[1, 1:2]), unname(cent[1, ]), tolerance = 1e-5)
  expect_error(rpic_sf("box", features = utm), "name_col")
})

test_that("without sf: rpic_sf says how to install it", {
  local_mocked_bindings(.has_sf = function() FALSE)
  expect_error(rpic_sf("geo_lon = 0; geo_lat = 0\nbox"), 'install.packages\\("sf"\\)')
})

test_that("knitr geo = TRUE assigns into knit_global (sf or GeoJSON)", {
  skip_if_not_installed("knitr")
  env <- knitr::knit_global()
  on.exit(rm(list = intersect(c("my_map", "radius_1"), ls(env)), envir = env))
  opts <- list(code = c("geo_lon = 0; geo_lat = 0", "box"), geo = TRUE,
               geo.var = "my_map", engine = "rpic", echo = TRUE, results = "markup")
  local_mocked_bindings(.has_sf = function() FALSE)
  out <- rpic_knitr_engine(opts)
  expect_s3_class(get("my_map", envir = env), "geojson")
  opts$geo.var <- NULL
  opts$label <- "radius-1"
  opts$geo.scale <- 1000
  rpic_knitr_engine(opts)
  expect_equal(attr(get("radius_1", envir = env), "registration")$scale_m_per_in, 1000)
})
