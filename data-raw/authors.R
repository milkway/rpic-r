# Regenerate inst/AUTHORS from the locked Rust dependency graph.
# Rerun after any change to src/rust/Cargo.lock:  Rscript data-raw/authors.R
# CRAN's Rust policy asks for the authors/licenses of the vendored crates.

meta <- jsonlite::fromJSON(
  system2(
    "cargo",
    c("metadata", "--format-version", "1", "--manifest-path", "src/rust/Cargo.toml"),
    stdout = TRUE
  ),
  simplifyVector = FALSE
)

pkgs <- Filter(function(p) !is.null(p$source), meta$packages) # drop the shim itself
pkgs <- pkgs[order(
  vapply(pkgs, function(p) p$name, ""),
  vapply(pkgs, function(p) p$version, "")
)]

row <- function(p) {
  authors <- if (length(p$authors)) paste(unlist(p$authors), collapse = "; ") else "(not stated)"
  license <- if (is.null(p$license)) "(see license file)" else p$license
  sprintf("%-28s %-10s %-26s %s", p$name, p$version, license, authors)
}

header <- c(
  "The rpic package statically links compiled Rust code. The Rust",
  "dependencies ('crates') below are vendored into src/rust/vendor.tar.xz",
  "at build time; their authors are copyright holders of the compiled",
  "code. Each crate's full license text ships inside the vendored sources.",
  "",
  sprintf("%-28s %-10s %-26s %s", "crate", "version", "license", "authors"),
  strrep("-", 100)
)

writeLines(c(header, vapply(pkgs, row, "")), "inst/AUTHORS", useBytes = TRUE)
cat("wrote inst/AUTHORS:", length(pkgs), "crates\n")
