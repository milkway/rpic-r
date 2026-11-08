# Pre-generate the vignette figures with the installed package.
# Rerun after engine upgrades:  Rscript data-raw/vignette-figures.R
# Vignettes embed these SVGs (chunks are eval=FALSE), so vignette builds are
# instant and deterministic on CRAN.

library(rpic)

fig_dir <- "vignettes/figures"
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

# pic() detects circuits/texlabels; the explicit flags below win
gen <- function(name, src, ...) {
  svg <- pic(src, ...) |> rpic_svg()
  writeLines(svg, file.path(fig_dir, paste0(name, ".svg")))
  cat("wrote", name, "\n")
}

# ---- getting started ---------------------------------------------------

gen("flow", '
boxht = 0.35; boxwid = 0.8
A: box "input"
arrow
box "process" fill 0.9
arrow
E: ellipse "output"
arc cw -> from A.n to E.n
')

gen("positioning", '
margin = 0.05
A: box "A" wid 0.6 ht 0.4
B: box "B" wid 0.6 ht 0.4 at A + (1.6, 0)
line dashed from A.e to B.w
circle rad 0.06 fill 0 at 1/2 between A.e and B.w
"midpoint" at last circle.s below
arrow from A.n up 0.3 then right 1.6 then down 0.3 to B.n
"the long way" at 1/2 between A.n and B.n + (0, 0.42)
')

gen("loop", '
for i = 0 to 5 do {
  circle rad 0.12 fill i/6 at (i * 0.4, 0)
}
')

gen("math", '
margin = 0.06
box "$\\frac{1}{2\\pi}\\int_{-\\infty}^{\\infty} f(t)\\,e^{-i\\omega t}\\,dt$" fit
', texlabels = TRUE)

gen("extensions", '
margin = 0.06
B: box wid 0.9 ht 0.55 gradient "steelblue" "white"
"gradient" at B.c
C: circle rad 0.3 hatch hatchangle 45 at B.e + (1.0, 0)
"hatch" at C.s below
brace from B.nw + (0, 0.15) to C.ne + (0, 0.15) up "extensions"
')

# ---- circuits ----------------------------------------------------------

gen("rlc", '
SW:(0,0); NW:(0,1.2); NE:(2.4,1.2); SE:(2.4,0)
battery(SW,NW); resistor(NW,NE); capacitor(NE,SE); inductor(SE,SW)
dot at NW; dot at NE; dot at SE; dot at SW
', circuits = TRUE)

gen("elements", '
margin = 0.08
A:(0,0); B:(1.4,0); C:(2.8,0)
resistor(A,B); "$R_1$" at 0.5 between A and B + (0, 0.35)
diode(B,C);   "$D_1$" at 0.5 between B and C + (0, 0.35)
', circuits = TRUE, texlabels = TRUE)

gen("gates", '
P:(0.5,0); and_gate(P)
Q:(1.9,0); nand_gate(Q)
R:(3.3,0); xor_gate(R)
"AND" at (0.5,-0.55); "NAND" at (1.9,-0.55); "XOR" at (3.3,-0.55)
', circuits = TRUE)

gen("npn", '
margin = 0.08
npn((0,0))
line left 0.3 from (gBase_x, gBase_y); "B" rjust at last line.end - (0.04, 0)
line up 0.25 from (gColl_x, gColl_y); "C" above at last line.end
line down 0.25 from (gEmit_x, gEmit_y); "E" below at last line.end
', circuits = TRUE)

# in-source library loading — same output as circuits = TRUE
stopifnot(identical(
  rpic_svg('copy "circuits"\nA:(0,0); B:(2,0)\nresistor(A,B)'),
  rpic_svg('A:(0,0); B:(2,0)\nresistor(A,B)', circuits = TRUE)
))

# ---- class + animate ---------------------------------------------------

gen("class", '
boxht = 0.4; boxwid = 0.9
box class "service" "api"
arrow
box class "service hot" "billing"
arrow
box class "storage" "database"
class last arrow "dataflow"
')

gen("animate", '
boxht = 0.35; boxwid = 0.8
A: box "build"
arrow
box "test"
arrow
box "ship"
animate A with "pop"
animate 2nd box with "fade"
animate 3rd box with "draw" for 0.8
')

manifest <- pic('
boxht = 0.35; boxwid = 0.8
A: box "build"
arrow
box "test"
arrow
box "ship"
animate A with "pop"
animate 2nd box with "fade"
animate 3rd box with "draw" for 0.8
') |>
  rpic_manifest()
writeLines(manifest, file.path(fig_dir, "animate.json"))
cat("wrote animate.json\n")

# ---- maps (vignette "maps") ----------------------------------------------
# ggplot2 + sf figures of rpic_sf(); the pic sources are the engine's
# examples/geo, copied as the test fixtures.

if (requireNamespace("sf", quietly = TRUE) && requireNamespace("ggplot2", quietly = TRUE)) {
  library(ggplot2)
  geo_src <- function(name) {
    paste(readLines(file.path("tests/testthat/fixtures/geo", paste0(name, ".pic"))),
          collapse = "\n")
  }
  # every pic colour is already a hex string: identity scales draw the
  # drawing as drawn; text features are labels, not markers
  # rpic_layers() + the lon/lat grid, as the vignette shows
  pic_layers <- function(x, x_breaks = NULL) {
    c(rpic_layers(x), list(
      if (is.null(x_breaks)) scale_x_continuous(n.breaks = 4) else scale_x_continuous(breaks = x_breaks),
      labs(x = NULL, y = NULL),
      theme_minimal(base_size = 8),
      theme(panel.grid = element_line(colour = "grey88", linewidth = 0.25),
            axis.text = element_text(colour = "grey45"),
            plot.margin = margin(8, 16, 8, 16))
    ))
  }
  save_map <- function(name, p, width = 5, height = 3.6) {
    path <- file.path(fig_dir, paste0(name, ".png"))
    # geom_sf_text's st_point_on_surface() warns on lon/lat data; the
    # labels are points already
    suppressWarnings(ggsave(path, p, width = width, height = height, dpi = 110, bg = "white"))
    cat("wrote", basename(path), "\n")
  }

  for (name in c("callout", "radius", "two-control-points", "arrow-between-features")) {
    x <- pic(geo_src(name)) |> rpic_sf()
    # the Recife-Olinda arrow is tall and narrow: three longitude ticks fit
    br <- if (name == "arrow-between-features") seq(-34.87, -34.85, by = 0.01) else NULL
    save_map(paste0("geo-", name), ggplot() + pic_layers(x, x_breaks = br))
  }

  # geo_bearing: a pitch drawn in metres, laid at 55 degrees
  pitch <- pic('
geo_lon = -34.8947
geo_lat = -8.0636
geo_scale = 20           # one inch is 20 m
geo_bearing = 55         # the +y axis points 55 degrees east of north
scale = 20               # so pic units are metres
margin = 3

Field: box wid 105 ht 68 shaded "#e4efe4" outlined "#2e7d32"
line from Field.n to Field.s outlined "#2e7d32"
circle rad 9.15 at Field.c outlined "#2e7d32"
box wid 16.5 ht 40.3 with .w at Field.w outlined "#2e7d32"
box wid 16.5 ht 40.3 with .e at Field.e outlined "#2e7d32"
dot at Field.c rad 0.3
"105 m" below at Field.s + (0, -2)
"68 m" ljust at Field.e + (2, 0)
') |>
    rpic_sf()
  save_map("geo-bearing", ggplot() + pic_layers(pitch))

  nc <- sf::st_read(system.file("shape/nc.shp", package = "sf"), quiet = TRUE)
  two <- nc[nc$NAME %in% c("Mecklenburg", "Wake"), ]
  route <- pic('
geo_scale = 50000        # one inch is 50 km
arrowht = 0.3; arrowwid = 0.18
arrow from Mecklenburg to Wake thick 1.5 color "firebrick"
"Wake" above at Wake.n
"Mecklenburg" below at Mecklenburg.s
') |>
    rpic_sf(features = two, name_col = "NAME")
  save_map("geo-nc", ggplot() +
    geom_sf(data = nc, fill = "grey95", colour = "grey70", linewidth = 0.2) +
    geom_sf(data = two, fill = "#cfe3d6", colour = "#2f5d43", linewidth = 0.3) +
    pic_layers(route) + theme_void(base_size = 9) + theme(plot.margin = margin(4, 4, 4, 4)),
    width = 6.5, height = 3)
}
