# pic(): pic source as a first-class object (`rpic_source`), and the
# argument resolution every rpic_*() function shares.

#' pic source as an object
#'
#' `pic()` wraps pic source code in an `rpic_source` object: the source
#' string together with the options it needs, `circuits` and `texlabels`.
#' Every `rpic_*()` function takes an `rpic_source` (or a plain string) as
#' its first argument, so a drawing reads as a pipe:
#' `pic(src) |> rpic_png("a.png")`, `pic(src) |> rpic_sf()`,
#' `pic(src) |> rpic_objects()`. When an `rpic_*()` function is given an
#' `rpic_source`, its `circuits` and `texlabels` are the defaults for those
#' arguments (an explicit argument still wins); a plain string defaults to
#' `FALSE` for both, as before.
#'
#' @section Detection:
#' With `circuits = NULL` or `texlabels = NULL` (the default), the option is
#' detected from the source, the way the rpic Studio does — outside string
#' literals and `#` comments:
#' * `circuits` is `TRUE` when the source calls a macro of the native
#'   circuit-element library (`resistor(`, `and_gate (`, ... — the public
#'   macros of the engine's `circuits.pic`) or loads it itself with
#'   `copy "circuits"` (loading it twice is harmless: the library only
#'   defines macros). A macro of your own with a library name counts too.
#' * `texlabels` is `TRUE` when some string literal is entirely one `$...$`
#'   (after trimming spaces): `"$x^2$"` is math, `"costs $10"` is not.
#'
#' Pass `TRUE` or `FALSE` to override either guess.
#'
#' @section Printing:
#' `print()` shows a summary (lines, characters, options) and the first
#' lines of the source; in an interactive session it also renders the
#' drawing to a temporary SVG file and opens it in the viewer
#' (`getOption("viewer")`, as in RStudio and Positron) or else the browser
#' ([utils::browseURL()]); a compile error is then reported as a message,
#' not raised. In a knitr document (R Markdown, Quarto) an `rpic_source`
#' left visible at the end of a chunk is drawn as the chunk's figure (a PNG,
#' like the `rpic` engine's; chunk option `scale`, default 2). `format()`
#' returns the summary line followed by the source lines.
#'
#' @param src pic source code: a string, a character vector (its elements
#'   are the lines, joined with newlines — e.g. from [readLines()]) or an
#'   `rpic_source` (whose options are then updated).
#' @param circuits load the native circuit-element library: `TRUE`, `FALSE`
#'   or `NULL` to detect it (see Detection).
#' @param texlabels typeset fully `$...$`-delimited labels as TeX math:
#'   `TRUE`, `FALSE` or `NULL` to detect it (see Detection).
#' @param x an `rpic_source`.
#' @param n how many source lines `format()` and `print()` show.
#' @param view render and open the drawing (see Printing).
#' @param options knitr chunk options (supplied by knitr).
#' @param ... unused.
#' @return `pic()`: an object of class `rpic_source` — the source as a
#'   character scalar with the attributes `circuits` and `texlabels`
#'   (logicals). `format()`: a character vector. `print()`: `x`, invisibly.
#'   `knit_print()`: knitr output.
#' @seealso [rpic_svg()], [rpic_compile()], [rpic_objects()], [rpic_sf()].
#' @examples
#' p <- pic('box "in"; arrow; box "out"')
#' p
#' rpic_svg(p) |> substr(1, 40)
#'
#' # detected options
#' attr(pic("A:(0,0); B:(2,0)\nresistor(A,B)"), "circuits")   # TRUE
#' attr(pic('box "$\\frac{T}{2}$" fit'), "texlabels")         # TRUE
#' attr(pic('box "costs $10"'), "texlabels")                  # FALSE
#'
#' # pipe-first
#' pic('A: box "A"; arrow; B: circle "B"') |> rpic_objects()
#' @export
pic <- function(src, circuits = NULL, texlabels = NULL) {
  if (inherits(src, "rpic_source")) {
    text <- .source_text(src)
    if (is.null(circuits)) circuits <- attr(src, "circuits")
    if (is.null(texlabels)) texlabels <- attr(src, "texlabels")
  } else {
    if (!is.character(src) || anyNA(src)) {
      stop("`src` must be pic source: a string or a character vector of lines", call. = FALSE)
    }
    text <- paste(src, collapse = "\n")
  }
  structure(
    text,
    class = "rpic_source",
    circuits = .flag(circuits, "circuits", .detect_circuits(text)),
    texlabels = .flag(texlabels, "texlabels", .detect_texlabels(text))
  )
}

.flag <- function(value, what, detected) {
  if (is.null(value)) return(detected)
  if (!is.logical(value) || length(value) != 1 || is.na(value)) {
    stop(sprintf("`%s` must be TRUE, FALSE or NULL", what), call. = FALSE)
  }
  value
}

# The public macros of the engine's crates/core/src/std/circuits.pic (80 at
# engine 0.16.0; the Studio's apps/web/src/lib/detect.ts list).
.circuit_macros <- c(
  "ac_source", "ammeter", "and_gate", "antenna", "battery", "bell", "buffer",
  "bus", "capacitor", "chassis_ground", "clabel", "crystal", "current",
  "current_source", "diode", "ebox", "fuse", "generator", "ground", "hop",
  "ic_block", "iec_resistor", "iecgate", "ieee_and", "ieee_buf", "ieee_or",
  "ieee_xor", "inductor", "isource", "isource_ctrl", "lamp", "ldr", "led",
  "meter", "microphone", "motor", "mux", "nand_gate", "njfet", "nmos",
  "nor_gate", "not_gate", "npn", "ohmmeter", "opamp", "or_gate", "photodiode",
  "phototransistor", "pjfet", "pmos", "pnp", "polcap", "potentiometer",
  "pushbutton", "relay", "resistor", "schottky", "signal_ground", "solar_cell",
  "spark_gap", "spdt", "speaker", "switch", "terminal", "thermistor",
  "thermocouple", "tline", "transformer", "varcap", "varind", "varistor", "vdd",
  "voltage", "voltage_source", "voltmeter", "vsource_ctrl", "wire", "xnor_gate",
  "xor_gate", "zener"
)

.string_re <- '"(\\\\.|[^"\\\\])*"'

# Source without its string literals (kept as "") and comments.
.strip_strings <- function(text) {
  text <- gsub(.string_re, '""', text, perl = TRUE)
  gsub("#[^\n]*", "", text, perl = TRUE)
}

.detect_circuits <- function(text) {
  if (grepl('(^|[\n;])[ \t]*copy[ \t]+"circuits"', text, perl = TRUE)) return(TRUE)
  call <- sprintf("\\b(%s)\\s*\\(", paste(.circuit_macros, collapse = "|"))
  grepl(call, .strip_strings(text), perl = TRUE)
}

.detect_texlabels <- function(text) {
  m <- regmatches(text, gregexpr(.string_re, text, perl = TRUE))[[1]]
  if (!length(m)) return(FALSE)
  inner <- trimws(substr(m, 2, nchar(m) - 1))
  any(grepl("^\\$[^$]+\\$$", inner, perl = TRUE))
}

.source_text <- function(x) {
  attributes(x) <- NULL
  x
}

# The arguments every rpic_*() function starts from: the source text and the
# circuits/texlabels flags — an explicit argument wins, then the
# rpic_source's options, then FALSE.
.src <- function(src, circuits = NULL, texlabels = NULL) {
  if (inherits(src, "rpic_source")) {
    if (is.null(circuits)) circuits <- attr(src, "circuits")
    if (is.null(texlabels)) texlabels <- attr(src, "texlabels")
    src <- .source_text(src)
  } else if (!is.character(src) || length(src) != 1 || is.na(src)) {
    stop("`src` must be pic source: a pic() object or a single string", call. = FALSE)
  }
  list(src = src, circuits = .flag(circuits, "circuits", FALSE),
       texlabels = .flag(texlabels, "texlabels", FALSE))
}

#' @rdname pic
#' @export
format.rpic_source <- function(x, n = 6, ...) {
  text <- .source_text(x)
  lines <- strsplit(text, "\n", fixed = TRUE)[[1]]
  if (!length(lines)) lines <- ""
  opts <- c(if (isTRUE(attr(x, "circuits"))) "circuits",
            if (isTRUE(attr(x, "texlabels"))) "texlabels")
  head <- sprintf("<pic source: %d line%s, %d character%s%s>",
                  length(lines), if (length(lines) == 1) "" else "s",
                  nchar(text), if (nchar(text) == 1) "" else "s",
                  if (length(opts)) paste0("; ", paste(opts, collapse = ", ")) else "")
  shown <- lines[seq_len(min(n, length(lines)))]
  more <- length(lines) - length(shown)
  c(head, paste0("  ", shown), if (more > 0) sprintf("  ... %d more line%s", more,
                                                    if (more == 1) "" else "s"))
}

#' @rdname pic
#' @export
print.rpic_source <- function(x, n = 6, view = interactive(), ...) {
  cat(format(x, n = n), sep = "\n")
  if (isTRUE(view)) .view_source(x)
  invisible(x)
}

# Render to a temporary SVG and open it in the IDE viewer or the browser.
.view_source <- function(x) {
  svg <- tryCatch(rpic_svg(x), rpic_error = function(e) {
    message("rpic: ", conditionMessage(e))
    NULL
  })
  if (is.null(svg)) return(invisible(NULL))
  # one fixed place, overwritten by each print
  dir <- file.path(tempdir(), "rpic-view")
  dir.create(dir, showWarnings = FALSE)
  viewer <- getOption("viewer")
  if (is.function(viewer)) {
    # IDE viewers want an HTML page under tempdir()
    path <- file.path(dir, "index.html")
    writeLines(c("<!DOCTYPE html>", "<html><head><meta charset=\"utf-8\"></head>",
                 "<body style=\"margin:1em;background:#fff\">", svg, "</body></html>"),
               path, useBytes = TRUE)
    viewer(path)
  } else {
    path <- file.path(dir, "pic.svg")
    writeLines(svg, path, useBytes = TRUE)
    utils::browseURL(path)
  }
  invisible(path)
}

#' @rdname pic
#' @exportS3Method knitr::knit_print
knit_print.rpic_source <- function(x, options = list(), ...) {
  # several pic()s in one chunk, or a pic() after a base plot (whose files
  # are <label>-1.png, <label>-2.png, ...), must not share a file: name each
  # by its content, <label>-rpic-<md5 prefix>.png — deterministic across
  # re-knits, and the same drawing twice is the same file
  path <- .knit_png(x, options, by_content = TRUE)
  knitr::knit_print(knitr::include_graphics(path), options = options, ...)
}

# Render `x` (a pic() or source; `...` = circuits/texlabels) to a PNG under
# the chunk's fig.path (chunk option `scale`, default 2) and return the path.
# `by_content` names the file <label>-rpic-<md5 prefix>.png (knit_print);
# otherwise it is knitr's default fig_path() (the engine's one figure).
.knit_png <- function(x, options, by_content = FALSE, ...) {
  scale <- if (is.null(options$scale)) 2 else options$scale
  if (by_content) {
    tmp <- tempfile(fileext = ".png")
    on.exit(unlink(tmp), add = TRUE)
    rpic_png(x, tmp, scale = scale, ...)
    number <- paste0("rpic-", substr(unname(tools::md5sum(tmp)), 1, 12))
    path <- knitr::fig_path(".png", options, number = number)
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    file.copy(tmp, path, overwrite = TRUE)
    return(path)
  }
  path <- knitr::fig_path(".png", options)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  rpic_png(x, path, scale = scale, ...)
  path
}
