# ggplot2 layers for a georeferenced drawing (rpic_layers()) and the quick
# map built on them (autoplot()).

#' ggplot2 layers of a georeferenced pic drawing
#'
#' The layers that draw an [rpic_sf()] data frame as pic drew it, to add to a
#' `ggplot()` — alone or over a basemap. Shapes go through
#' [ggplot2::geom_sf()] with their `fill` and `stroke` columns (pic colours
#' are hex strings already, so the scales are identity scales); every text
#' (`geopic_kind` `"text"` and `"title"`) is a label at its point through
#' [ggplot2::geom_sf_text()], justified and turned as pic placed it — the
#' `geopic_anchor` compass becomes `hjust`/`vjust` (`above` puts the point at
#' the label's bottom, `ljust` at its left) and `geopic_rotation` becomes
#' `angle`; a label written `bold`, `italic` or `mono` keeps its face
#' (`geopic_font_weight`, `geopic_font_style`, `geopic_font_family` become
#' `fontface` and the `"mono"` family). [ggplot2::coord_sf()] with `clip = "off"` completes the list, so
#' labels at the drawing's edge are not cut.
#'
#' The result is a list of layers and scales: add it to a plot with `+`.
#' Layers added before it (a basemap) are drawn under the drawing, layers
#' added after it on top; axes and theme are the plot's own —
#' `vignette("maps")` shows the longitude/latitude grid with
#' `theme_minimal()`, [autoplot.rpic_source()] hides it with `theme_void()`.
#'
#' @param x a georeferenced drawing: an [rpic_sf()] data frame, or anything
#'   [rpic_sf()] takes — a [pic()] object or pic source (then `...` are its
#'   georeferencing arguments: `anchor`, `scale`, `bearing`, `frame`,
#'   `features`, ...).
#' @param ... passed to [rpic_sf()] when `x` is pic source; an error otherwise.
#' @param linewidth line width of the shapes, in `ggplot2` units (mm).
#'   `NULL` draws each shape at pic's own width (the `stroke_width` column,
#'   points, 0.8 by default).
#' @param text_size size of the labels, in `ggplot2` units (mm).
#' @return a list of `ggplot2` layers, scales and a `coord_sf()`.
#' @section Requirements:
#' Needs `ggplot2` and `sf`.
#' @seealso [autoplot.rpic_source()] for the one-call map; [rpic_sf()] for
#'   the data and its columns; [add_rpic()] for an interactive MapLibre map.
#' @examples
#' if (requireNamespace("ggplot2", quietly = TRUE) &&
#'     requireNamespace("sf", quietly = TRUE)) {
#'   radius <- pic('geo_lon = -34.8711; geo_lat = -8.0631; geo_scale = 1000
#'   C: circle rad 2 at (0, 0) dashed fill 0.97
#'   line from C.c to C.e thin
#'   "2 km" above at 0.5 <C.c, C.e>') |>
#'     rpic_sf()
#'   ggplot2::ggplot() + rpic_layers(radius) + ggplot2::theme_minimal()
#' }
#' @export
rpic_layers <- function(x, ..., linewidth = 0.4, text_size = 3) {
  for (pkg in c("ggplot2", "sf")) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      stop(sprintf("rpic_layers() needs the '%s' package: install.packages(\"%s\")",
                   pkg, pkg), call. = FALSE)
    }
  }
  if (inherits(x, "sf")) {
    if (length(list(...))) {
      stop("arguments in `...` apply only when `x` is pic source", call. = FALSE)
    }
    if (!"geopic_kind" %in% names(x)) {
      stop("`x` must be an rpic_sf() data frame (it has no `geopic_kind` column)",
           call. = FALSE)
    }
  } else {
    x <- rpic_sf(x, ...)
  }
  if (!is.null(linewidth) && (!is.numeric(linewidth) || length(linewidth) != 1 ||
                              !is.finite(linewidth) || linewidth < 0)) {
    stop("`linewidth` must be NULL or a single non-negative number", call. = FALSE)
  }
  if (!is.numeric(text_size) || length(text_size) != 1 || !is.finite(text_size) ||
      text_size <= 0) {
    stop("`text_size` must be a single positive number", call. = FALSE)
  }
  is_text <- x$geopic_kind %in% c("text", "title")
  shapes <- x[!is_text, ]
  labels <- x[is_text, ]
  # aes() of symbols built with do.call: no global-variable NOTEs
  aes <- function(...) do.call(ggplot2::aes, lapply(list(...), as.name))
  column <- function(d, name, default) if (name %in% names(d)) d[[name]] else default
  layers <- list()
  if (nrow(shapes)) {
    shapes$.fill <- column(shapes, "fill", NA_character_)
    shapes$.stroke <- column(shapes, "stroke", NA_character_)
    if (is.null(linewidth)) {
      # pic's stroke width is in points; ggplot2's linewidth in mm
      pt <- column(shapes, "stroke_width", NA_real_)
      shapes$.linewidth <- ifelse(is.na(pt), 0.8, pt) * 25.4 / 72.27
      layers <- c(layers, list(
        ggplot2::geom_sf(data = shapes,
                         mapping = aes(fill = ".fill", colour = ".stroke", linewidth = ".linewidth")),
        ggplot2::scale_linewidth_identity()
      ))
    } else {
      layers <- c(layers, list(
        ggplot2::geom_sf(data = shapes, mapping = aes(fill = ".fill", colour = ".stroke"),
                         linewidth = linewidth)
      ))
    }
  }
  if (nrow(labels)) {
    # pic's compass anchor -> ggplot2 justification: the anchor names where
    # the POINT is on the label ("s" = its bottom, so the text sits above)
    a <- column(labels, "geopic_anchor", NA_character_)
    a <- ifelse(is.na(a), "c", a)
    labels$.hjust <- ifelse(grepl("e", a), 1, ifelse(grepl("w", a), 0, 0.5))
    labels$.vjust <- ifelse(grepl("n", a), 1, ifelse(grepl("s", a), 0, 0.5))
    rot <- column(labels, "geopic_rotation", NA_real_)
    labels$.angle <- ifelse(is.na(rot), 0, rot)
    labels$.text <- column(labels, "geopic_text", NA_character_)
    # the label's face, as pic set it (bold / italic / mono)
    bold <- column(labels, "geopic_font_weight", NA_character_) %in% "bold"
    italic <- column(labels, "geopic_font_style", NA_character_) %in% "italic"
    labels$.face <- ifelse(bold & italic, "bold.italic",
                           ifelse(bold, "bold", ifelse(italic, "italic", "plain")))
    mono <- column(labels, "geopic_font_family", NA_character_) %in% "monospace"
    labels$.family <- ifelse(mono, "mono", "")
    # the labels are points already: skip geom_sf_text()'s default
    # st_point_on_surface(), which warns on lon/lat data
    layers <- c(layers, list(
      ggplot2::geom_sf_text(
        data = labels,
        mapping = aes(label = ".text", hjust = ".hjust", vjust = ".vjust", angle = ".angle",
                      fontface = ".face", family = ".family"),
        size = text_size, fun.geometry = function(g) g
      )
    ))
  }
  c(layers, list(
    ggplot2::scale_fill_identity(), ggplot2::scale_colour_identity(),
    ggplot2::coord_sf(clip = "off")
  ))
}

#' A quick ggplot2 map of a georeferenced pic drawing
#'
#' `autoplot()` (from `ggplot2`) for a [pic()] object: georeferences the
#' drawing with [rpic_sf()] and draws it with [rpic_layers()] — fills,
#' strokes and labels as pic drew and placed them — on a blank theme. The
#' result is an ordinary `ggplot`: add scales, a theme or more layers with
#' `+` (a layer added this way goes on top of the drawing; for a basemap
#' under it, build the plot from [rpic_layers()] directly, as
#' `vignette("maps")` does).
#' @param object a [pic()] object whose source georeferences itself
#'   (`geo_lon`/`geo_lat`, control points) or is given `anchor`/`features`
#'   in `...`.
#' @param ... passed to [rpic_sf()] (`anchor`, `scale`, `bearing`, `frame`,
#'   `features`, ...).
#' @inheritParams rpic_layers
#' @return a `ggplot` object.
#' @section Requirements:
#' Needs `ggplot2` and `sf`.
#' @seealso [rpic_layers()]; [rpic_sf()]; `vignette("maps")`.
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
  ggplot2::ggplot() +
    rpic_layers(object, ..., linewidth = linewidth, text_size = text_size) +
    ggplot2::labs(x = NULL, y = NULL) +
    ggplot2::theme_void()
}
