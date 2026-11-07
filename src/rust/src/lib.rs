use extendr_api::prelude::*;

mod geo;
mod value;

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

// The scene export (engine docs/scene.md): the resolved draw list as
// versioned, device-independent JSON. `flatten <= 0` keeps the cubic
// Béziers (the C-ABI convention); `> 0` delivers polylines within that
// tolerance in inches. Success = `list(value = <json>, warnings = <list>)`
// — the scene's own `scene_unsupported` diagnostics ride `warnings` so the
// R wrapper can surface them (never silent). (Plain `//` on purpose: `///`
// would become roxygen on the generated wrapper and document an internal.)
#[extendr]
fn rpic_scene_(src: &str, circuits: bool, texlabels: bool, flatten: f64, outline: bool) -> List {
    ensure_math_renderer();
    let sopts = rpic_core::SceneOptions {
        flatten: Some(flatten).filter(|f| f.is_finite() && *f > 0.0),
        outline,
        source: None,
    };
    match rpic_core::compile_scene_with_options(src, &opts(circuits, texlabels), &sopts) {
        Ok(out) => {
            let warnings: Vec<Robj> = out.warnings.iter().map(|w| info_list(w).into()).collect();
            list!(value = out.json, warnings = List::from_values(warnings))
        }
        Err(e) => fail(&e.message, Some(&e.info)),
    }
}

// The full compile bundle (engine `compile_json_with_options`, or
// `compile_json_all_with_options` with the scene) converted to an R list:
// `svg`, `animations`, `diagnostics`, `warnings`, `objects`, plus `places`,
// `passthrough`, `interactions`, `scroll` when the source has them and
// `scene` when asked. A pic error comes back as `list(error =, info =)`
// like every other shim function.
#[extendr]
fn rpic_compile_(
    src: &str,
    circuits: bool,
    texlabels: bool,
    scene: bool,
    flatten: f64,
    outline: bool,
) -> List {
    ensure_math_renderer();
    let copts = opts(circuits, texlabels);
    let json = if scene {
        let sopts = rpic_core::SceneOptions {
            flatten: Some(flatten).filter(|f| f.is_finite() && *f > 0.0),
            outline,
            source: None,
        };
        rpic_core::compile_json_all_with_options(src, &copts, &sopts)
    } else {
        rpic_core::compile_json_with_options(src, &copts)
    };
    let v: serde_json::Value = match serde_json::from_str(&json) {
        Ok(v) => v,
        Err(e) => return fail(&format!("internal: bundle JSON does not parse: {e}"), None),
    };
    if let Some(msg) = v.get("error") {
        let info: Robj = match v.get("error_info") {
            Some(i) => info_from_value(i).into(),
            None => r!(NULL),
        };
        return list!(error = msg.as_str().unwrap_or("compile error"), info = info);
    }
    list!(value = value::to_robj(&v))
}

// The bundle's `error_info` with the field types of `info_list` (integer
// positions, `NA` when absent) so `e$info` looks the same on every path.
fn info_from_value(v: &serde_json::Value) -> List {
    let s = |k: &str| v.get(k).and_then(|x| x.as_str());
    let n = |k: &str| v.get(k).and_then(|x| x.as_u64()).map(|x| x as u32);
    list!(
        message = s("message").unwrap_or(""),
        line = n("line"),
        col = n("col"),
        end_col = n("end_col"),
        file = s("file"),
        kind = s("kind").unwrap_or(""),
        found = s("found"),
        expected = s("expected"),
        hint = s("hint")
    )
}

fn warn_list(w: &geo::Warn) -> Robj {
    list!(
        kind = w.kind.as_str(),
        message = w.message.as_str(),
        hint = w.hint.as_deref(),
        id = w.id.as_deref(),
        line = w.line,
        col = w.col,
        end_col = w.end_col,
        file = w.file.as_deref()
    )
    .into()
}

// pic source → GeoJSON (engine docs/geopic.md). `options_json` carries the
// GeoOptions R/geo.R validated: frame, anchor, scale, bearing, features
// (`[{name, lon, lat, bbox?}]`), flatten, view_scale, screen_classes.
// Success = `list(value = list(geojson = <FeatureCollection text>, warnings
// = <list of kind/message/hint/id/line/col/end_col/file>, registration =
// <named list>))`; failure = `list(error =, info =, geo =)` where `geo`
// says whether it is a georeferencing error (info: kind, message, hint) or
// a pic compile error (info: the usual diagnostic).
#[extendr]
fn rpic_geojson_(src: &str, circuits: bool, texlabels: bool, options_json: &str) -> List {
    ensure_math_renderer();
    match geo::run(src, &opts(circuits, texlabels), options_json) {
        Ok(out) => {
            let warnings: Vec<Robj> = out.warnings.iter().map(warn_list).collect();
            let reg = serde_json::to_value(&out.registration).unwrap_or(serde_json::Value::Null);
            list!(
                value = list!(
                    geojson = out.geojson,
                    warnings = List::from_values(warnings),
                    registration = value::to_robj(&reg)
                )
            )
        }
        Err(geo::Failure::Compile(e)) => {
            list!(
                error = e.message.as_str(),
                info = info_list(&e.info),
                geo = false
            )
        }
        Err(geo::Failure::Geo(e)) => list!(
            error = e.to_string(),
            info = list!(
                kind = e.kind.as_str(),
                message = e.message.as_str(),
                hint = e.hint.as_deref()
            ),
            geo = true
        ),
    }
}

// A geopic FeatureCollection (JSON text) → the MapLibre style-spec layers
// that draw it (geopic-core `maplibre::layers_json`, docs/geopic.md § 6), as
// an R list of named lists in draw order. One-element arrays stay lists so
// the specs serialise back to the engine's JSON (value.rs). Failure =
// `list(error =, info = list(kind, message, hint))`, a geo error.
#[extendr]
fn rpic_maplibre_layers_(fc_json: &str) -> List {
    let parsed = geopic_core::maplibre::layers_json(fc_json).and_then(|text| {
        serde_json::from_str::<serde_json::Value>(&text).map_err(|e| {
            geopic_core::GeoError::new("internal", format!("layers JSON does not parse: {e}"))
        })
    });
    match parsed {
        Ok(serde_json::Value::Array(layers)) => {
            list!(value = List::from_values(layers.iter().map(layer_robj)))
        }
        Ok(v) => list!(value = value::to_robj_arrays(&v)),
        Err(e) => list!(
            error = e.to_string(),
            info = list!(
                kind = e.kind.as_str(),
                message = e.message.as_str(),
                hint = e.hint.as_deref()
            )
        ),
    }
}

// One layer spec with its keys in the style spec's reading order (`id`,
// `type`, `source`, `filter`, `layout`, `paint`, then any other, sorted)
// rather than serde_json's alphabetical order.
fn layer_robj(v: &serde_json::Value) -> Robj {
    let Some(m) = v.as_object() else {
        return value::to_robj_arrays(v);
    };
    const FIRST: [&str; 6] = ["id", "type", "source", "filter", "layout", "paint"];
    let keys: Vec<&str> = FIRST
        .iter()
        .copied()
        .filter(|k| m.contains_key(*k))
        .chain(m.keys().map(String::as_str).filter(|k| !FIRST.contains(k)))
        .collect();
    let values: Vec<Robj> = keys.iter().map(|k| value::to_robj_arrays(&m[*k])).collect();
    match List::from_names_and_values(keys, values) {
        Ok(l) => l.into(),
        Err(_) => r!(NULL),
    }
}

// The bounding box `c(west, south, east, north)` of every position in a
// GeoJSON FeatureCollection's geometries (for `mapgl::fit_bounds()`), or
// `NULL` when it has none or does not parse. The geometries are the engine's
// own output: plain lon/lat arrays, no antimeridian handling needed.
#[extendr]
fn rpic_geojson_bbox_(fc_json: &str) -> Robj {
    fn walk(v: &serde_json::Value, b: &mut [f64; 4]) {
        if let Some(a) = v.as_array() {
            if a.len() >= 2 && a[0].is_number() && a[1].is_number() {
                let (x, y) = (
                    a[0].as_f64().unwrap_or(f64::NAN),
                    a[1].as_f64().unwrap_or(f64::NAN),
                );
                if x.is_finite() && y.is_finite() {
                    b[0] = b[0].min(x);
                    b[1] = b[1].min(y);
                    b[2] = b[2].max(x);
                    b[3] = b[3].max(y);
                }
            } else {
                a.iter().for_each(|x| walk(x, b));
            }
        }
    }
    let Ok(v) = serde_json::from_str::<serde_json::Value>(fc_json) else {
        return r!(NULL);
    };
    let mut b = [
        f64::INFINITY,
        f64::INFINITY,
        f64::NEG_INFINITY,
        f64::NEG_INFINITY,
    ];
    for f in v
        .get("features")
        .and_then(|f| f.as_array())
        .into_iter()
        .flatten()
    {
        if let Some(c) = f.get("geometry").and_then(|g| g.get("coordinates")) {
            walk(c, &mut b);
        }
    }
    if b[0] <= b[2] && b[1] <= b[3] {
        r!(b.to_vec())
    } else {
        r!(NULL)
    }
}

// Macro to generate exports.
extendr_module! {
    mod rpic;
    fn rpic_svg_;
    fn rpic_png_;
    fn rpic_pdf_;
    fn rpic_manifest_;
    fn rpic_scene_;
    fn rpic_compile_;
    fn rpic_geojson_;
    fn rpic_maplibre_layers_;
    fn rpic_geojson_bbox_;
}
