test_that("rpic_compile returns the bundle as a list", {
  b <- rpic_compile('A: (0, 0)
box "hi" at A; arrow')
  expect_named(b, c("svg", "animations", "diagnostics", "warnings", "objects",
                    "places", "passthrough"))
  expect_identical(b$svg, rpic_svg('A: (0, 0)
box "hi" at A; arrow'))
  expect_length(b$objects, 2)
  expect_identical(b$objects[[1]]$kind, "box")
  expect_identical(b$objects[[1]]$id, "s0")
  expect_identical(b$places[[1]]$label, "A")
  expect_identical(b$passthrough, list())
  expect_null(b$scene)
})

test_that("rpic_compile carries passthrough, animations and the scene", {
  b <- rpic_compile('.ft B\nbox; animate last box with "pop"', scene = TRUE)
  expect_identical(b$passthrough[[1]]$text, ".ft B")
  expect_length(b$animations, 1)
  expect_identical(b$scene$scene, 1)
  expect_identical(b$scene$items[[1]]$kind, "box")
  spline <- "spline from (0,0) to (1,1) to (2,0)"
  flat <- rpic_compile(spline, scene = TRUE, flatten = 0.01)$scene$items[[1]]
  cubic <- rpic_compile(spline, scene = TRUE)$scene$items[[1]]
  expect_false(is.null(flat$paths[[1]]$points))
  expect_false(is.null(cubic$paths[[1]]$cubics))
})

test_that("scene text carries rows (engine 0.16.0) and blocks the raw call arguments", {
  it <- rpic_compile('box "" "below"', scene = TRUE)$scene$items[[1]]
  expect_identical(it$text_rows, 2)
  expect_length(it$text, 1)
  expect_identical(it$text[[1]]$text, "below")
  expect_identical(it$text[[1]]$row, 1)
  expect_length(it$text_center, 2)
  sc <- rpic_compile('define m { [ box ] }\nm(1e-9,  "x")', scene = TRUE)$scene
  blk <- Filter(function(i) identical(i$kind, "block"), sc$items)[[1]]
  expect_identical(blk$call$name, "m")
  expect_identical(blk$call$args, c("0.000000001", '"x"'))
  expect_identical(vapply(blk$call$raw_args, function(a) a$text, ""), c("1e-9", '"x"'))
  expect_identical(blk$call$raw_args[[1]]$line, 2)
})

test_that("rpic_compile errors are rpic_error with a structured info", {
  e <- tryCatch(rpic_compile("bxo"), rpic_error = function(e) e)
  expect_s3_class(e, "rpic_error")
  expect_identical(e$info$hint, "did you mean `box`?")
  expect_equal(e$info$line, 1)
  expect_true(is.na(e$info$file))
  expect_error(rpic_compile("box", scene = TRUE, flatten = -1), "flatten")
})

test_that("the existing functions are unchanged", {
  expect_match(rpic_svg("box"), "^<svg")
  expect_match(rpic_manifest("box"), '^\\{"svg"')
  expect_match(rpic_scene("box"), '"scene":1')
  e <- tryCatch(rpic_svg("bxo"), rpic_error = function(e) e)
  expect_s3_class(e, "rpic_error")
})
