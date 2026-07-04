# Pre-generate the vignette figures with the installed package.
# Rerun after engine upgrades:  Rscript data-raw/vignette-figures.R
# Vignettes embed these SVGs (chunks are eval=FALSE), so vignette builds are
# instant and deterministic on CRAN.

library(rpic)

fig_dir <- "vignettes/figures"
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

gen <- function(name, src, ...) {
  svg <- rpic_svg(src, ...)
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

manifest <- rpic_manifest('
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
writeLines(manifest, file.path(fig_dir, "animate.json"))
cat("wrote animate.json\n")
