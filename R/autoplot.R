# autoplot() for a georeferenced pic(): a quick ggplot2 map via rpic_sf().

#' A quick ggplot2 map of a georeferenced pic drawing
#'
#' `autoplot()` (from `ggplot2`) for a [pic()] object: georeferences the
#' drawing with [rpic_sf()] and draws it with [ggplot2::geom_sf()] as pic
#' drew it — fills and strokes from the `fill` and `stroke` columns (pic
#' colours are hex strings already, so the scales are identity scales) and
#' every text (`geopic_kind` `"text"` and `"title"`) placed as a label at its
#' point with [ggplot2::geom_sf_text()]. The result is an ordinary `ggplot`:
#' add scales, a theme or more layers with `+` (a layer added this way goes
#' on top of the drawing; for a basemap under it, build the plot from
#' [rpic_sf()] directly, as `vignette("maps")` does).
#'
#' Strokes are drawn at one width (`linewidth`), not pic's per-object
#' `stroke_width`; use [rpic_sf()] with your own `geom_sf()` layers for
#' anything finer.
#' @param object a [pic()] object whose source georeferences itself
#'   (`geo_lon`/`geo_lat`, control points) or is given `anchor`/`features`
#'   in `...`.
#' @param ... passed to [rpic_sf()] (`anchor`, `scale`, `bearing`, `frame`,
#'   `features`, ...).
#' @param linewidth line width of the shapes, in `ggplot2` units (mm).
#' @param text_size size of the labels, in `ggplot2` units (mm).
#' @return a `ggplot` object.
#' @section Requirements:
#' Needs `ggplot2` and `sf`.
#' @seealso [rpic_sf()]; `vignette("maps")`.
#' @examples
#' if (requireNamespace("ggplot2", quietly = TRUE) &&
#'     requireNamespace("sf", quietly = TRUE)) {
#'   p <- pic('geo_lon = -34.8711; geo_lat = -8.0631; geo_scale = 1000
#'   C: circle rad 2 at (0, 0) dashed fill 0.97
#'   dot at C.c rad 0.04
#'   "2 km" above at 0.5 <C.c, C.e>')
#'   ggplot2::autoplot(p)
#' }
#' @exportS3Method ggplot2::autoplot
autoplot.rpic_source <- function(object, ..., linewidth = 0.4, text_size = 3) {
  for (pkg in c("ggplot2", "sf")) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      stop(sprintf("autoplot() of a pic() needs the '%s' package: install.packages(\"%s\")",
                   pkg, pkg), call. = FALSE)
    }
  }
  x <- rpic_sf(object, ...)
  is_text <- x$geopic_kind %in% c("text", "title")
  shapes <- x[!is_text, ]
  labels <- x[is_text, ]
  # aes() of symbols built with do.call: no global-variable NOTEs
  aes <- function(...) do.call(ggplot2::aes, lapply(list(...), as.name))
  p <- ggplot2::ggplot()
  if (nrow(shapes)) {
    if (!"fill" %in% names(shapes)) shapes$fill <- NA_character_
    if (!"stroke" %in% names(shapes)) shapes$stroke <- NA_character_
    p <- p + ggplot2::geom_sf(data = shapes, mapping = aes(fill = "fill", colour = "stroke"),
                              linewidth = linewidth)
  }
  if (nrow(labels)) {
    # the labels are points already: skip geom_sf_text()'s default
    # st_point_on_surface(), which warns on lon/lat data
    p <- p + ggplot2::geom_sf_text(data = labels, mapping = aes(label = "geopic_text"),
                                   size = text_size, fun.geometry = function(g) g)
  }
  p + ggplot2::scale_fill_identity() + ggplot2::scale_colour_identity() +
    ggplot2::coord_sf(clip = "off") + ggplot2::labs(x = NULL, y = NULL) +
    ggplot2::theme_void()
}
