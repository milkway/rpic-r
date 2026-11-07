# Drawing data as data frames: rpic_objects(), rpic_places(), rpic_warnings().

#' Drawing data as data frames
#'
#' The parts of the compile bundle ([rpic_compile()]) that are tables, as
#' plain `data.frame`s with one row per record — ready for `subset()`,
#' `merge()`, `dplyr` or `ggplot2`:
#'
#' * `rpic_objects()` — every drawn object: `id` (the SVG group id, `"s0"`,
#'   `"s1"`, ...), `kind` (`"box"`, `"circle"`, `"path"`, `"text"`, ...),
#'   the source span `line`, `col`, `end_col`, `file` (`NA` = your own
#'   source; else the `copy` include or `"circuits"`), the bounding box in
#'   SVG viewBox units (y down) as `bbox_x0`, `bbox_y0` (top-left corner) and
#'   `bbox_x1`, `bbox_y1` (bottom-right corner) — `NA` for an object with no
#'   extent — and `link` (the `link "<url>"` extension, else `NA`).
#' * `rpic_places()` — every `Label: position` statement: `label` (the
#'   resolved key, subscripts included: `"P[2]"`), `x`, `y` (SVG user units,
#'   the frame of the objects' bounding boxes), `block` (the enclosing block
#'   path when the engine reports one, else `NA`) and the source span `line`,
#'   `col`, `end_col`, `file`.
#' * `rpic_warnings()` — compiler warnings for accepted-but-ignored input:
#'   `kind`, `message`, `line`, `col`, `end_col`, `file`, `found`,
#'   `expected`, `hint` (the fields of the `rpic_error` diagnostic). For the
#'   result of [rpic_geojson()] or [rpic_sf()] it tabulates that result's
#'   `"warnings"` attribute instead: `kind`, `message`, `hint`, `id`, `line`,
#'   `col`, `end_col`, `file`.
#'
#' A drawing with nothing to report gives a data frame with the same columns
#' and zero rows. Line and column numbers are integers.
#' @param x the drawing: a [pic()] object or a string of pic source (compiled
#'   with [rpic_compile()]), or a list returned by [rpic_compile()]. For
#'   `rpic_warnings()` also an [rpic_geojson()] or [rpic_sf()] result.
#' @param ... passed to [rpic_compile()] when `x` is pic source (`circuits`,
#'   `texlabels`).
#' @return a `data.frame` (see Details).
#' @section Compile errors:
#' Source that does not compile raises the classed `rpic_error` of
#' [rpic_svg()] — an error is not a warning row.
#' @seealso [rpic_compile()] for the whole bundle.
#' @examples
#' p <- pic('A: (0, 0)
#' box "hi" at A link "https://rpic.dev"
#' arrow
#' circle "x"
#' box foo')
#' rpic_objects(p)
#' rpic_places(p)
#' rpic_warnings(p)[, c("kind", "line", "found", "hint")]
#'
#' # one compile, several tables
#' b <- rpic_compile(p)
#' rpic_objects(b)$kind
#' @name rpic_data
NULL

#' @rdname rpic_data
#' @export
rpic_objects <- function(x, ...) {
  recs <- .bundle(x, ...)$objects
  .records_df(lapply(recs, function(o) {
    bb <- o$bbox
    if (is.list(bb)) {
      o$bbox_x0 <- bb$x
      o$bbox_y0 <- bb$y
      o$bbox_x1 <- bb$x + bb$w
      o$bbox_y1 <- bb$y + bb$h
    }
    o
  }), .objects_cols)
}

#' @rdname rpic_data
#' @export
rpic_places <- function(x, ...) {
  .records_df(.bundle(x, ...)$places, .places_cols)
}

#' @rdname rpic_data
#' @export
rpic_warnings <- function(x, ...) {
  if (inherits(x, c("geojson", "sf"))) {
    if (...length()) {
      stop("arguments in `...` apply only when `x` is pic source", call. = FALSE)
    }
    w <- attr(x, "warnings", exact = TRUE)
    if (is.null(w) && !inherits(x, "geojson")) {
      stop("this sf data frame carries no \"warnings\" attribute (was it made by rpic_sf()?)",
           call. = FALSE)
    }
    return(.records_df(w, .geo_warning_cols))
  }
  .records_df(.bundle(x, ...)$warnings, .warning_cols)
}

.objects_cols <- c(id = "character", kind = "character", line = "integer",
                   col = "integer", end_col = "integer", file = "character",
                   bbox_x0 = "double", bbox_y0 = "double", bbox_x1 = "double",
                   bbox_y1 = "double", link = "character")
.places_cols <- c(label = "character", x = "double", y = "double", block = "character",
                  line = "integer", col = "integer", end_col = "integer",
                  file = "character")
.warning_cols <- c(kind = "character", message = "character", line = "integer",
                   col = "integer", end_col = "integer", file = "character",
                   found = "character", expected = "character", hint = "character")
.geo_warning_cols <- c(kind = "character", message = "character", hint = "character",
                       id = "character", line = "integer", col = "integer",
                       end_col = "integer", file = "character")

# The compile bundle of `x`: a rpic_compile() list as is, else compiled.
.bundle <- function(x, ...) {
  if (is.list(x) && !is.data.frame(x) && all(c("svg", "objects") %in% names(x))) {
    if (...length()) {
      stop("arguments in `...` apply only when `x` is pic source", call. = FALSE)
    }
    return(x)
  }
  if (!inherits(x, "rpic_source") && !(is.character(x) && length(x) == 1 && !is.na(x))) {
    stop("`x` must be a pic() object, a single string of pic source or an rpic_compile() result",
         call. = FALSE)
  }
  rpic_compile(x, ...)
}

# Records (named lists, as converted from the engine's JSON) to a data frame
# with exactly the columns `cols` (name = type); absent fields are NA.
.records_df <- function(records, cols) {
  out <- lapply(names(cols), function(nm) {
    type <- cols[[nm]]
    na <- switch(type, character = NA_character_, integer = NA_integer_, NA_real_)
    v <- lapply(records, function(r) {
      x <- r[[nm]]
      if (is.null(x) || length(x) != 1) na else x
    })
    v <- unlist(v, use.names = FALSE)
    if (is.null(v)) v <- vector(type, 0)
    switch(type, character = as.character(v), integer = as.integer(v), as.double(v))
  })
  names(out) <- names(cols)
  as.data.frame(out, stringsAsFactors = FALSE, optional = TRUE)
}
