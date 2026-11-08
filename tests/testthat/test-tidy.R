tmp_file <- function(ext) tempfile(fileext = ext)
with_opts <- function(opts, code) {
  old <- options(opts)
  on.exit(options(old))
  force(code)
}

test_that("pic() builds an rpic_source and detects its options", {
  p <- pic('box "a"')
  expect_s3_class(p, "rpic_source")
  expect_true(is.character(p))
  expect_false(attr(p, "circuits"))
  expect_false(attr(p, "texlabels"))
  expect_identical(as.character(p), 'box "a"')

  expect_true(attr(pic("A:(0,0); B:(2,0)\nresistor(A,B)"), "circuits"))
  expect_true(attr(pic("battery (SW, NW)"), "circuits"))
  expect_true(attr(pic('copy "circuits"\nbox'), "circuits"))
  expect_false(attr(pic('box "resistor(A,B)"'), "circuits"))
  expect_false(attr(pic("box # resistor(A,B)"), "circuits"))
  expect_false(attr(pic("wire = 3\nbox wid wire"), "circuits"))
  # bare macro names: the engine expands them without arguments
  expect_true(attr(pic("A: (0,0)\nground"), "circuits"))
  expect_true(attr(pic("move; vdd"), "circuits"))
  expect_false(attr(pic("ground: (0, 0)\nbox at ground"), "circuits"))
  expect_false(attr(pic("box; x = last box.ground"), "circuits"))
  expect_false(attr(pic("myground = 1; ground_wire = 2"), "circuits"))
  expect_false(attr(pic('box "ground"'), "circuits"))
  # comments first: a quote inside a comment opens no string
  expect_true(attr(pic('box # the "big" one\nresistor(A,B)'), "circuits"))
  expect_true(attr(pic('box # it\'s "\nresistor(A,B)\n# "'), "circuits"))
  expect_false(attr(pic('# copy "circuits"\nbox'), "circuits"))
  expect_true(attr(pic('box "a # b"; resistor(A,B)'), "circuits"))

  expect_true(attr(pic('box "$x^2$"'), "texlabels"))
  expect_true(attr(pic('circle " $\\alpha$ " rad 0.3'), "texlabels"))
  expect_false(attr(pic('box "costs $10"'), "texlabels"))
  expect_false(attr(pic("define node { circle $1 }"), "texlabels"))
  # a $...$ string inside a comment is not a label
  expect_false(attr(pic('box # was "$x^2$"'), "texlabels"))
  expect_true(attr(pic('box "$x$" # "costs $10"'), "texlabels"))
  expect_true(attr(pic('box "# $y$"; circle "$z$"'), "texlabels"))

  # explicit options win; a vector is lines; an rpic_source is updated
  expect_false(attr(pic("resistor(A,B)", circuits = FALSE), "circuits"))
  expect_true(attr(pic("box", texlabels = TRUE), "texlabels"))
  expect_identical(as.character(pic(c("box", "arrow"))), "box\narrow")
  q <- pic(pic("resistor(A,B)"), texlabels = TRUE)
  expect_true(attr(q, "circuits"))
  expect_true(attr(q, "texlabels"))
  expect_error(pic(1), "pic source")
  expect_error(pic("box", circuits = NA), "TRUE, FALSE or NULL")
})

test_that("an rpic_source's options are the rpic_*() defaults", {
  src <- "A:(0,0); B:(2,0)\nresistor(A,B)"
  with_lib <- rpic_svg(src, circuits = TRUE)
  expect_identical(rpic_svg(pic(src)), with_lib)
  expect_identical(pic(src) |> rpic_svg(), with_lib)
  # an explicit argument still wins
  expect_error(rpic_svg(pic(src), circuits = FALSE), class = "rpic_error")
  # a plain string keeps FALSE
  expect_error(rpic_svg(src), class = "rpic_error")
  tex <- 'box "$\\frac{T}{2}$" fit'
  expect_identical(rpic_svg(pic(tex)), rpic_svg(tex, texlabels = TRUE))
  expect_identical(rpic_manifest(pic(src)), rpic_manifest(src, circuits = TRUE))
  expect_identical(rpic_scene(pic(src)), rpic_scene(src, circuits = TRUE))
  expect_identical(rpic_compile(pic(src))$svg, with_lib)
  png <- tmp_file(".png")
  expect_identical(pic(src) |> rpic_png(png), png)
  expect_true(file.size(png) > 0)
  pdf <- tmp_file(".pdf")
  pic(src) |> rpic_pdf(pdf)
  expect_true(file.size(pdf) > 0)
  geo <- "geo_lon = 0; geo_lat = 0\nA:(0,0); B:(2,0)\nresistor(A,B)"
  expect_identical(as.character(rpic_geojson(pic(geo))),
                   as.character(rpic_geojson(geo, circuits = TRUE)))
  expect_error(rpic_svg(c("box", "arrow")), "single string")
  # explicit flags are validated, not read as FALSE
  expect_error(rpic_svg("box", circuits = NA), "`circuits` must be TRUE, FALSE or NULL")
  expect_error(rpic_svg(pic("box"), texlabels = "TRUE"), "`texlabels` must be")
  expect_error(rpic_compile("box", circuits = c(TRUE, FALSE)), "`circuits` must be")
  expect_error(rpic_geojson("geo_lon = 0; geo_lat = 0\nbox", circuits = 1), "`circuits` must be")
})

test_that("format() and print() summarise the source", {
  p <- pic(c("A: box", "arrow", "B: circle", "line", "line", "line", "line", "dot"))
  f <- format(p)
  expect_identical(f[1], "<pic source: 8 lines, 46 characters>")
  expect_identical(f[2], "  A: box")
  expect_identical(f[length(f)], "  ... 2 more lines")
  expect_length(format(p, n = 100), 9)
  expect_match(format(pic("resistor(A,B)"))[1], "; circuits>$")
  expect_output(print(p, view = FALSE), "<pic source: 8 lines")
  expect_output(expect_invisible(print(p, view = FALSE)))
})

test_that("print(view = TRUE) opens the drawing; errors become messages", {
  seen <- NULL
  with_opts(list(viewer = function(url) seen <<- url), {
    expect_output(print(pic("box"), view = TRUE))
  })
  expect_identical(normalizePath(seen), normalizePath(file.path(tempdir(), "rpic-view", "index.html")))
  expect_match(paste(readLines(seen), collapse = "\n"), "<svg")
  # one fixed file, overwritten
  first <- seen
  with_opts(list(viewer = function(url) seen <<- url), {
    expect_output(print(pic("circle"), view = TRUE))
  })
  expect_identical(seen, first)
  expect_match(paste(readLines(seen), collapse = "\n"), "<circle")
  with_opts(list(viewer = function(url) stop("not reached")), {
    expect_message(expect_output(print(pic("bxo"), view = TRUE)), "rpic: ")
  })
})

test_that("knit_print() draws an rpic_source as a figure", {
  skip_if_not_installed("knitr")
  dir <- tempfile("knit-")
  dir.create(dir)
  rmd <- file.path(dir, "doc.Rmd")
  writeLines(c(
    "```{r fig1}", "library(rpic)", "pic('box \"hi\"; arrow')", "```",
    # two pic()s and a base plot in one chunk: three distinct files
    "```{r fig2}", "pic('box')", "plot(1:3)", "pic('circle')", "```"
  ), rmd)
  # knit from the document's directory, so every figure lands under it
  old <- setwd(dir)
  on.exit(setwd(old), add = TRUE)
  knit <- function() {
    out <- knitr::knit(rmd, output = file.path(dir, "doc.md"), quiet = TRUE,
                       envir = new.env())
    paste(readLines(out), collapse = "\n")
  }
  md <- knit()
  imgs <- regmatches(md, gregexpr("figure/[^)\"]+\\.png", md))[[1]]
  expect_length(imgs, 4)
  expect_identical(anyDuplicated(imgs), 0L)
  expect_match(imgs[1], "^figure/fig1-rpic-[0-9a-f]{12}\\.png$")
  expect_true(all(file.exists(file.path(dir, imgs))))
  expect_identical(sum(grepl("^figure/fig2-[0-9]+\\.png$", imgs)), 1L)  # the base plot
  # deterministic: re-knitting names the same files
  md2 <- knit()
  expect_identical(regmatches(md2, gregexpr("figure/[^)\"]+\\.png", md2))[[1]], imgs)
})

test_that("rpic_objects() is one row per object, bbox split in four", {
  p <- pic('box "hi" link "https://rpic.dev"\narrow\nline from (0,0) to (0,0) invis')
  o <- rpic_objects(p)
  expect_s3_class(o, "data.frame")
  expect_false(inherits(o, "tbl_df"))
  expect_named(o, c("id", "kind", "line", "col", "end_col", "file",
                    "bbox_x0", "bbox_y0", "bbox_x1", "bbox_y1", "link"))
  expect_identical(o$id, c("s0", "s1", "s2"))
  expect_identical(o$kind, c("box", "path", "path"))
  expect_type(o$line, "integer")
  expect_identical(o$link, c("https://rpic.dev", NA, NA))
  b <- rpic_compile(p)$objects[[1]]$bbox
  expect_equal(unlist(o[1, c("bbox_x0", "bbox_y0", "bbox_x1", "bbox_y1")], use.names = FALSE),
               c(b$x, b$y, b$x + b$w, b$y + b$h))
  expect_true(all(is.na(o[3, c("bbox_x0", "bbox_y0", "bbox_x1", "bbox_y1")])))
  expect_true(all(is.na(o$file)))
  # a string, an rpic_compile() result and ... all work
  expect_identical(rpic_objects(as.character(p)), o)
  expect_identical(rpic_objects(rpic_compile(p)), o)
  expect_identical(rpic_objects("A:(0,0); B:(2,0)\nresistor(A,B)", circuits = TRUE)$file[1],
                   "circuits")
  empty <- rpic_objects("x = 1")
  expect_identical(nrow(empty), 0L)
  expect_named(empty, names(o))
  expect_error(rpic_objects(rpic_compile(p), circuits = TRUE), "only when `x` is pic source")
  expect_error(rpic_objects(1), "pic\\(\\) object")
  expect_error(rpic_objects("bxo"), class = "rpic_error")
})

test_that("rpic_places() and rpic_warnings()", {
  p <- pic("A: (0, 0)\nfor i = 1 to 2 do { P[i]: (i, 0) }\nbox foo")
  pl <- rpic_places(p)
  expect_named(pl, c("label", "x", "y", "block", "line", "col", "end_col", "file"))
  expect_identical(pl$label, c("A", "P[1]", "P[2]"))
  b <- rpic_compile(p)
  expect_equal(pl$x, vapply(b$places, function(q) q$x, 0))
  expect_identical(pl$line, c(1L, 2L, 2L))
  expect_identical(nrow(rpic_places("box")), 0L)

  w <- rpic_warnings(p)
  expect_named(w, c("kind", "message", "line", "col", "end_col", "file",
                    "found", "expected", "hint"))
  expect_identical(w$kind, "ignored_attribute")
  expect_identical(w$found, "foo")
  expect_identical(w$line, 3L)
  expect_identical(nrow(rpic_warnings("box")), 0L)
  expect_named(rpic_warnings("box"), names(w))

  # geo results tabulate their own warnings
  gj <- suppressWarnings(rpic_geojson('geo_lon = 0; geo_lat = 0\nbox gradient "red" "blue"'))
  gw <- rpic_warnings(gj)
  expect_named(gw, c("kind", "message", "hint", "id", "line", "col", "end_col", "file"))
  expect_identical(gw$kind[1], "unsupported_style")
  skip_if_not_installed("sf")
  x <- suppressWarnings(rpic_sf('geo_lon = 0; geo_lat = 0\nbox gradient "red" "blue"'))
  expect_identical(rpic_warnings(x), gw)
  expect_error(rpic_warnings(gj, circuits = TRUE), "only when `x` is pic source")
  expect_identical(nrow(rpic_warnings(rpic_sf("geo_lon = 0; geo_lat = 0\nbox"))), 0L)
})

test_that("rpic_sf_names() is the column rule of rpic_sf()", {
  expect_identical(rpic_sf_names(c("geopic:kind", "stroke-width", "fill-opacity", "title")),
                   c("geopic_kind", "stroke_width", "fill_opacity", "title"))
  expect_error(rpic_sf_names(1), "character")
  skip_if_not_installed("sf")
  skip_if_not_installed("jsonlite")
  src <- paste(readLines(test_path("fixtures", "geo", "callout.pic")), collapse = "\n")
  gj <- rpic_geojson(src)
  props <- unique(unlist(lapply(
    jsonlite::fromJSON(gj, simplifyVector = FALSE)$features,
    function(f) names(f$properties))))
  x <- rpic_sf(pic(src))
  expect_setequal(setdiff(names(x), "geometry"), rpic_sf_names(props))
})

test_that("rpic_sf() column names come from the real property names", {
  # sf mangles with make.names() (+ make.unique()); the columns are
  # rpic_sf_names() of the real names, whatever the mangling
  props <- c("geopic:kind", "stroke-width", "1st:x", "a-b", "a.b", "fill")
  sf_names <- c(make.unique(make.names(props)), "geometry")
  expect_identical(rpic:::.sf_columns(sf_names, props, "geometry"),
                   c("geopic_kind", "stroke_width", "1st_x", "a_b", "a.b", "fill", "geometry"))
  # snake_case clashes are made unique
  expect_identical(rpic:::.sf_columns(c("a.b", "a.b.1", "geometry"), c("a-b", "a:b"), "geometry"),
                   c("a_b", "a_b_1", "geometry"))
})

test_that("add_rpic() is the mapgl adder; rpic_mapgl() its alias", {
  expect_identical(rpic_mapgl, add_rpic)
  skip_if_not_installed("mapgl")
  src <- pic("geo_lon = 0; geo_lat = 0; geo_scale = 1000\ncircle rad 1")
  local_mocked_bindings(.fetch_style = function(url, ...) stop("offline (tests)"))
  m <- mapgl::maplibre() |> add_rpic(src, fit = FALSE)
  expect_identical(vapply(m$x$layers, function(l) l$id, ""),
                   c("pic-fill", "pic-stroke", "pic-stroke-dashed", "pic-dot", "pic-text",
                     "pic-title"))
  # an rpic_source opening with a brace group is pic, not GeoJSON
  brace <- pic("geo_lon = 0; geo_lat = 0\n{ box }")
  expect_length(rpic_maplibre_layers(brace), 6)
})

test_that("autoplot() of a georeferenced pic() is a ggplot", {
  skip_if_not_installed("ggplot2")
  skip_if_not_installed("sf")
  p <- pic('geo_lon = 0; geo_lat = 0; geo_scale = 1000\nbox "a" fill 0.9\n"b" at (1, 1)')
  g <- ggplot2::autoplot(p)
  expect_s3_class(g, "ggplot")
  expect_length(g$layers, 2)
  expect_no_warning(ggplot2::ggplot_build(g))
  expect_error(ggplot2::autoplot(pic("box")), class = "rpic_geo_error")
})

test_that("autoplot() places labels by pic's anchor and rotation", {
  skip_if_not_installed("ggplot2")
  skip_if_not_installed("sf")
  p <- pic('geo_lon = 0; geo_lat = 0; geo_scale = 1000; geo_bearing = 30
box wid 1 ht 0.5 at (0.5, -0.5)
"up" above at (0, 0)
"left" ljust at (1, 0)')
  g <- ggplot2::autoplot(p)
  labels <- ggplot2::layer_data(g, 2)
  # "above": the point is at the text's bottom -> vjust 0; ljust -> hjust 0
  expect_equal(labels$vjust[labels$label == "up"], 0)
  expect_equal(labels$hjust[labels$label == "up"], 0.5)
  expect_equal(labels$hjust[labels$label == "left"], 0)
  expect_equal(labels$vjust[labels$label == "left"], 0.5)
  # the drawing's bearing turns the texts the other way (counter-clockwise from east)
  expect_equal(unique(labels$angle), -30)
})
