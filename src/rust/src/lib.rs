use extendr_api::prelude::*;

// Low-level wrappers (no `@export`): they are package-internal and called by the
// user-facing R functions in R/rpic.R. Keeping them undocumented avoids R CMD
// check `\usage`/export warnings.
//
// Compile results cross into R as a list — `list(value =)` on success or
// `list(error =, info =)` on failure — so R/rpic.R can raise a classed
// `rpic_error` condition carrying the structured diagnostic (position, kind,
// did-you-mean hint) instead of a bare string.

/// `circuits`/`texlabels` are compile options (not text prepended to the
/// source), so diagnostic positions stay relative to the caller's own `src`.
fn opts(circuits: bool, texlabels: bool) -> rpic_core::CompileOptions {
    // `..Default::default()` keeps this resilient to additive CompileOptions
    // fields (0.6.2 grew `includes`; defaults = no base dir, unrestricted —
    // the local-CLI semantics, right for an R package on the user's machine).
    rpic_core::CompileOptions {
        circuits,
        texlabels,
        ..Default::default()
    }
}

fn info_list(d: &rpic_core::Diagnostic) -> List {
    list!(
        message = d.message.as_str(),
        line = d.line,
        col = d.col,
        end_col = d.end_col,
        file = d.file.as_deref(),
        kind = d.kind.as_str(),
        found = d.found.as_deref(),
        expected = d.expected.as_deref(),
        hint = d.hint.as_deref()
    )
}

fn ok(value: String) -> List {
    list!(value = value)
}

fn fail(message: &str, info: Option<&rpic_core::Diagnostic>) -> List {
    let info: Robj = match info {
        Some(d) => info_list(d).into(),
        None => r!(NULL),
    };
    list!(error = message, info = info)
}

/// Idempotent (process-wide `OnceLock`); wires the RaTeX renderer so
/// `texlabels` sources typeset `$…$` labels like the native CLI.
fn ensure_math_renderer() {
    rpic_core::set_math_renderer(rpic_render::math::render_math);
}

fn compile_svg(
    src: &str,
    circuits: bool,
    texlabels: bool,
) -> std::result::Result<String, rpic_core::CompileError> {
    ensure_math_renderer();
    rpic_core::compile_with_diagnostics(src, &opts(circuits, texlabels))
        .map(|d| rpic_core::to_svg(&d))
}

#[extendr]
fn rpic_svg_(src: &str, circuits: bool, texlabels: bool) -> List {
    match compile_svg(src, circuits, texlabels) {
        Ok(svg) => ok(svg),
        Err(e) => fail(&e.message, Some(&e.info)),
    }
}

#[extendr]
fn rpic_png_(src: &str, file: &str, scale: f64, circuits: bool, texlabels: bool) -> List {
    let svg = match compile_svg(src, circuits, texlabels) {
        Ok(svg) => svg,
        Err(e) => return fail(&e.message, Some(&e.info)),
    };
    let png = match rpic_render::to_png(&svg, scale as f32) {
        Ok(bytes) => bytes,
        Err(e) => return fail(&e, None),
    };
    match std::fs::write(file, png) {
        Ok(()) => ok(file.to_string()),
        Err(e) => fail(&e.to_string(), None),
    }
}

#[extendr]
fn rpic_pdf_(src: &str, file: &str, circuits: bool, texlabels: bool) -> List {
    let svg = match compile_svg(src, circuits, texlabels) {
        Ok(svg) => svg,
        Err(e) => return fail(&e.message, Some(&e.info)),
    };
    let pdf = match rpic_render::to_pdf(&svg) {
        Ok(bytes) => bytes,
        Err(e) => return fail(&e, None),
    };
    match std::fs::write(file, pdf) {
        Ok(()) => ok(file.to_string()),
        Err(e) => fail(&e.to_string(), None),
    }
}

#[extendr]
fn rpic_manifest_(src: &str, circuits: bool, texlabels: bool) -> String {
    ensure_math_renderer();
    rpic_core::compile_json_with_options(src, &opts(circuits, texlabels))
}

// Macro to generate exports.
extendr_module! {
    mod rpic;
    fn rpic_svg_;
    fn rpic_png_;
    fn rpic_pdf_;
    fn rpic_manifest_;
}
