#' @keywords internal
"_PACKAGE"

# Unwrap a low-level compile result: `list(value =)` on success, or
# `list(error =, info =)` on failure — raised as a classed `rpic_error`
# condition so callers can `tryCatch(..., rpic_error = function(e) e$info)`.
# `info` (NULL for I/O errors) is the structured diagnostic: message, line,
# col, end_col, file, kind, found, expected, hint (absent values are NA).
# Positions are relative to the caller's own `src` — `file` names a `copy`
# include when the problem is inside one (NA means your own input).
.rpic_value <- function(res, call = sys.call(-1)) {
  if (!is.null(res$error)) {
    stop(structure(
      class = c("rpic_error", "error", "condition"),
      list(message = res$error, call = call, info = res$info)
    ))
  }
  res$value
}

#' Render pic source to an SVG string
#'
#' @param src pic source code.
#' @param circuits load the native circuit-element library (or write
#'   `copy "circuits"` in the source itself).
#' @param texlabels typeset fully `$...$`-delimited labels as TeX math
#'   (initializer only — the source can still set `texlabels = 0`).
#' @return an SVG string.
#' @section Errors:
#' Compile errors are raised as a classed `rpic_error` condition whose
#' `info` field holds the structured diagnostic (`message`, `line`, `col`,
#' `end_col`, `file`, `kind`, `found`, `expected`, `hint`; absent values are
#' `NA`, and `file` names a `copy` include — `NA` means your own input).
#' Positions are relative to your own source, even with `circuits = TRUE`:
#'
#' ```r
#' tryCatch(
#'   rpic_svg("bxo", circuits = TRUE),
#'   rpic_error = function(e) e$info$hint  # "did you mean `box`?"
#' )
#' ```
#' @examples
#' rpic_svg('box "hi"; arrow; circle "x"')
#' tryCatch(rpic_svg("bxo"), rpic_error = function(e) e$info$line)
#' @export
rpic_svg <- function(src, circuits = FALSE, texlabels = FALSE) {
  .rpic_value(rpic_svg_(src, circuits, texlabels))
}

#' Render pic source to a PNG file
#' @param src pic source code.
#' @param file output path.
#' @param scale raster scale (1 = 96 dpi).
#' @param circuits load the native circuit-element library.
#' @param texlabels typeset `$...$` labels as TeX math.
#' @return the file path, invisibly.
#' @export
rpic_png <- function(src, file, scale = 2, circuits = FALSE, texlabels = FALSE) {
  invisible(.rpic_value(rpic_png_(src, file, scale, circuits, texlabels)))
}

#' Render pic source to a PDF file
#' @inheritParams rpic_png
#' @return the file path, invisibly.
#' @export
rpic_pdf <- function(src, file, circuits = FALSE, texlabels = FALSE) {
  invisible(.rpic_value(rpic_pdf_(src, file, circuits, texlabels)))
}

#' Compile to a JSON bundle (as a string)
#'
#' Returns `{svg, animations, diagnostics, warnings, objects}` — `warnings`
#' carries structured compiler warnings for accepted-but-ignored input (unknown
#' attribute words, unknown `animate` effects), each with the same fields as
#' the `rpic_error` diagnostic. `objects` lists every drawn object: its SVG
#' `id` (`"s0"`, `"s1"`, ...), `kind`, bounding box in viewBox units and
#' source position. An `interactions` array is added when the source marks
#' objects `draggable`. On a pic error the JSON is
#' `{error, error_info}` instead (no condition is raised — the error travels
#' in-band).
#' @inheritParams rpic_svg
#' @return a JSON string; parse with e.g. `jsonlite::fromJSON()`.
#' @examples
#' rpic_manifest('box; animate last box with "pop"')
#' @export
rpic_manifest <- function(src, circuits = FALSE, texlabels = FALSE) {
  rpic_manifest_(src, circuits, texlabels)
}

#' Compile to the scene JSON (the resolved draw list)
#'
#' The scene is the engine's device-independent output (format 1, see
#' `docs/scene.md` in the engine repository): the fully resolved draw list —
#' final geometry in inches (y-up), curves as cubic Béziers, style as
#' descriptors with colors resolved to hex, text as text with baseline
#' anchor points, every variable's final value under `vars`, and items in
#' draw order carrying the same stable `s<N>` ids as the SVG. Use it to
#' build your own backend (maps, TikZ, editors) on top of rpic's layout.
#'
#' Anything the SVG paints that the scene cannot represent is reported as an
#' R `warning()` (engine kind `scene_unsupported`) — never silently dropped.
#' @inheritParams rpic_svg
#' @param flatten optional tolerance in inches: deliver every curve as a
#'   polyline within this distance of the exact cubics (`NULL` keeps the
#'   Béziers).
#' @param outline embed typeset TeX math as self-contained SVG glyph
#'   fragments (`outline` keys) instead of metrics-only entries.
#' @return a JSON string; parse with e.g. `jsonlite::fromJSON()`.
#' @section Errors:
#' Compile errors raise the same classed `rpic_error` condition as
#' [rpic_svg()].
#' @examples
#' scene <- rpic_scene('geo_lon = -34.88
#' B: box "hub"
#' arrow right from B.e')
#' if (requireNamespace("jsonlite", quietly = TRUE)) {
#'   s <- jsonlite::fromJSON(scene, simplifyVector = FALSE)
#'   s$vars$geo_lon      # -34.88
#'   s$items[[2]]$kind   # "arrow"
#' }
#' @export
rpic_scene <- function(src, flatten = NULL, outline = FALSE,
                       circuits = FALSE, texlabels = FALSE) {
  flat <- 0
  if (!is.null(flatten)) {
    if (!is.numeric(flatten) || length(flatten) != 1 || !is.finite(flatten) || flatten <= 0) {
      stop("`flatten` must be a single positive finite tolerance in inches")
    }
    flat <- as.numeric(flatten)
  }
  res <- rpic_scene_(src, circuits, texlabels, flat, isTRUE(outline))
  for (w in res$warnings) {
    warning(structure(
      class = c("rpic_warning", "warning", "condition"),
      list(message = w$message, call = sys.call(), info = w)
    ))
  }
  .rpic_value(res)
}

#' Compile to the full bundle (as an R list)
#'
#' The engine's compile bundle, converted to R: everything [rpic_manifest()]
#' returns as JSON text, plus the scene on request, without a JSON parser on
#' the R side. Use it to drive tools (editors, map front ends, checkers) from
#' one compile.
#'
#' The list always carries
#' * `svg` — the SVG string ([rpic_svg()]);
#' * `animations` — the `animate` timelines (a list, empty when unused);
#' * `diagnostics` — `print` lines and engine notices (a character vector);
#' * `warnings` — structured compiler warnings, each a list with the
#'   `rpic_error` diagnostic fields (with `scene = TRUE` the scene's own
#'   `scene_unsupported` warnings join them). They are returned, not raised;
#' * `objects` — every drawn object: SVG `id` (`"s0"`, ...), `kind`, `bbox`
#'   in viewBox units (`NA` when it has none) and source position;
#' * `places` — every `Label: position` statement as a named point (`label`,
#'   `x`, `y` in SVG user units, enclosing `block`, source span);
#' * `passthrough` — troff lines set aside (`text` and source position);
#'
#' plus `interactions` and `scroll` when the source uses `draggable` or
#' `animate scroll`, and `scene` (the scene document of [rpic_scene()] as a
#' nested list) when `scene = TRUE`.
#'
#' JSON objects become named lists, arrays of numbers/strings/logicals
#' atomic vectors, other arrays lists, `null` is `NA`; nested names are in
#' sorted order.
#' @inheritParams rpic_scene
#' @param scene also compile the scene (`scene` element).
#' @param flatten,outline scene options (see [rpic_scene()]); used only when
#'   `scene = TRUE`.
#' @return a named list (see Details).
#' @section Errors:
#' Compile errors raise the same classed `rpic_error` condition as
#' [rpic_svg()].
#' @examples
#' b <- rpic_compile('A: (0, 0)
#' box "hi" at A; arrow')
#' names(b)
#' b$objects[[1]]$kind   # "box"
#' b$places[[1]]$label   # "A"
#' s <- rpic_compile("circle", scene = TRUE)$scene
#' s$items[[1]]$kind     # "circle"
#' @export
rpic_compile <- function(src, circuits = FALSE, texlabels = FALSE, scene = FALSE,
                         flatten = NULL, outline = FALSE) {
  flat <- .rpic_flatten(flatten)
  res <- rpic_compile_(src, circuits, texlabels, isTRUE(scene), flat, isTRUE(outline))
  b <- .rpic_value(res)
  if (is.null(b$places)) b$places <- list()
  if (is.null(b$passthrough)) b$passthrough <- list()
  if (length(b$diagnostics) == 0) b$diagnostics <- character()
  first <- c("svg", "animations", "diagnostics", "warnings", "objects",
             "places", "passthrough", "interactions", "scroll", "scene")
  b[c(intersect(first, names(b)), setdiff(names(b), first))]
}

# `flatten` for the scene paths: NULL keeps the cubics (0 to the shim).
.rpic_flatten <- function(flatten) {
  if (is.null(flatten)) return(0)
  if (!is.numeric(flatten) || length(flatten) != 1 || !is.finite(flatten) || flatten <= 0) {
    stop("`flatten` must be a single positive finite tolerance in inches", call. = FALSE)
  }
  as.numeric(flatten)
}

#' knitr engine for ```{rpic}``` chunks
#'
#' Register with [rpic_register_knitr()], then write pic code in a chunk:
#' ````
#' ```{rpic, circuits=TRUE}
#' A:(0,0); B:(2,0)
#' resistor(A,B)
#' ```
#' ````
#' Chunk options: `circuits`, `texlabels`, `scale`.
#'
#' @section Maps (`geo = TRUE`):
#' With the chunk option `geo = TRUE` the chunk is georeferenced instead of
#' drawn: the engine runs [rpic_sf()] (or [rpic_geojson()] when `sf` is not
#' installed) and **assigns** the result to a variable in
#' [knitr::knit_global()] — named by the chunk option `geo.var`, by default
#' the chunk label made syntactic ([make.names()], `-` read as `_`). The
#' chunk emits no figure; its source is echoed as usual. The georeferencing
#' options ride as `geo.frame`, `geo.anchor`, `geo.scale`, `geo.bearing`,
#' `geo.features`, `geo.flatten`, `geo.view_scale` and `geo.name_col` (the
#' `geo.` prefix keeps `scale` for the PNG raster scale); chunk options are R
#' expressions, so `geo.features = my_sf` works. Plot the result in a later R
#' chunk:
#' ````
#' ```{rpic, geo=TRUE}
#' geo_lon = -34.8711; geo_lat = -8.0631; geo_scale = 1000
#' circle rad 2 at (0, 0)
#' ```
#'
#' ```{r}
#' ggplot2::ggplot(radius) + ggplot2::geom_sf(ggplot2::aes(fill = fill))
#' ```
#' ````
#' (the first chunk being labelled `radius`).
#' @param options knitr chunk options.
#' @return The chunk output produced by [knitr::engine_output()] (the rendered
#'   diagram as an included figure; with `geo = TRUE`, the source only).
#' @export
rpic_knitr_engine <- function(options) {
  src <- paste(options$code, collapse = "\n")
  circuits <- isTRUE(options$circuits)
  texlabels <- isTRUE(options$texlabels)
  if (isTRUE(options$geo)) {
    return(.rpic_knitr_geo(options, src, circuits, texlabels))
  }
  scale <- if (is.null(options$scale)) 2 else options$scale
  path <- knitr::fig_path(".png", options)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  rpic_png(src, path, scale = scale, circuits = circuits, texlabels = texlabels)
  # a list `out` goes through knitr's output hooks as-is, so the figure is
  # included as a figure (a character `out` would print its path as text)
  out <- list(knitr::include_graphics(path))
  if (!isFALSE(options$echo)) {
    out <- c(list(structure(list(src = options$code), class = "source")), out)
  }
  knitr::engine_output(options, out = out)
}

# `geo = TRUE` chunks: georeference, assign into knit_global(), echo only.
.rpic_knitr_geo <- function(options, src, circuits, texlabels) {
  var <- options$geo.var
  if (is.null(var)) {
    label <- if (is.null(options$label)) "rpic_geo" else options$label
    var <- make.names(gsub("-", "_", label, fixed = TRUE))
  }
  if (!is.character(var) || length(var) != 1 || !nzchar(var)) {
    stop("chunk option `geo.var` must be a single variable name", call. = FALSE)
  }
  args <- list(src = src, circuits = circuits, texlabels = texlabels)
  for (o in c("frame", "anchor", "scale", "bearing", "features", "flatten",
              "view_scale", "name_col")) {
    v <- options[[paste0("geo.", o)]]
    if (!is.null(v)) args[[o]] <- v
  }
  fun <- if (.has_sf()) rpic_sf else rpic_geojson
  value <- do.call(fun, args)
  # the knitting environment (as knitr's own sql engine does for
  # `output.var`); the user named the variable with this chunk
  env <- knitr::knit_global()
  assign(var, value, envir = env)
  knitr::engine_output(options, options$code, "")
}

#' Register the rpic knitr engine
#' @return No return value; called for its side effect of registering the
#'   `rpic` engine with [knitr::knit_engines].
#' @export
rpic_register_knitr <- function() {
  knitr::knit_engines$set(rpic = rpic_knitr_engine)
}
