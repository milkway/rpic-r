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
#' @param options knitr chunk options.
#' @return The chunk output produced by [knitr::engine_output()] (the rendered
#'   diagram as an included figure).
#' @export
rpic_knitr_engine <- function(options) {
  src <- paste(options$code, collapse = "\n")
  circuits <- isTRUE(options$circuits)
  texlabels <- isTRUE(options$texlabels)
  scale <- if (is.null(options$scale)) 2 else options$scale
  path <- knitr::fig_path(".png", options)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  rpic_png(src, path, scale = scale, circuits = circuits, texlabels = texlabels)
  knitr::engine_output(options, options$code, knitr::include_graphics(path))
}

#' Register the rpic knitr engine
#' @return No return value; called for its side effect of registering the
#'   `rpic` engine with [knitr::knit_engines].
#' @export
rpic_register_knitr <- function() {
  knitr::knit_engines$set(rpic = rpic_knitr_engine)
}
