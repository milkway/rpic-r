// geopic for R: pic source → GeoJSON FeatureCollection (engine
// docs/geopic.md), with the host-feature injection the Python and JS
// bindings do (two passes). Everything here is plain Rust; lib.rs turns the
// result into R objects. (Plain `//` comments throughout: see lib.rs.)

use std::sync::Arc;

use serde::Deserialize;

// A host feature as the options JSON carries it.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct FeatureOpt {
    name: String,
    lon: f64,
    lat: f64,
    #[serde(default)]
    bbox: Option<[f64; 4]>,
}

// The options JSON written by R/geo.R; every key optional (the same keys as
// the wasm `compile_geo`).
#[derive(Deserialize, Default)]
#[serde(default, deny_unknown_fields)]
struct GeoOpts {
    frame: Option<String>,
    anchor: Option<[f64; 2]>,
    scale: Option<f64>,
    bearing: Option<f64>,
    features: Vec<FeatureOpt>,
    flatten: Option<f64>,
    view_scale: Option<f64>,
    screen_classes: Option<Vec<String>>,
}

pub enum Failure {
    Compile(rpic_core::CompileError),
    Geo(geopic_core::GeoError),
}

impl From<geopic_core::GeoError> for Failure {
    fn from(e: geopic_core::GeoError) -> Self {
        Failure::Geo(e)
    }
}

// One warning, engine or geopic, flattened to the fields R reports.
pub struct Warn {
    pub kind: String,
    pub message: String,
    pub hint: Option<String>,
    pub id: Option<String>,
    pub line: Option<u32>,
    pub col: Option<u32>,
    pub end_col: Option<u32>,
    pub file: Option<String>,
}

pub struct GeoOut {
    pub geojson: String,
    pub warnings: Vec<Warn>,
    pub registration: geopic_core::Registration,
    // pic `scale` units per emitted inch and the whole-picture rescale: what
    // the injection needs to write canvas positions back as source text
    scale: f64,
    rescale: f64,
}

// pic labels: an uppercase letter, then letters, digits or underscores.
// Feature names are written into pic source, so anything else is refused
// (R validates first; this is the second fence).
fn is_label(name: &str) -> bool {
    let mut cs = name.chars();
    matches!(cs.next(), Some(c) if c.is_ascii_uppercase())
        && cs.all(|c| c.is_ascii_alphanumeric() || c == '_')
}

// A position inside the `k` lines the host prepended is not the caller's:
// it is tagged `file = "features"`; one after them is shifted back.
fn rebase(line: &mut Option<u32>, file: &mut Option<String>, k: u32) {
    if k == 0 || file.is_some() {
        return;
    }
    if let Some(l) = *line {
        if l > k {
            *line = Some(l - k);
        } else if l >= 1 {
            *file = Some("features".to_string());
        }
    }
}

fn rebase_diag(d: &mut rpic_core::Diagnostic, k: u32) {
    let mut file = d.file.as_deref().map(str::to_string);
    let had = file.is_some();
    rebase(&mut d.line, &mut file, k);
    if !had && let Some(f) = file {
        d.file = Some(Arc::from(f.as_str()));
    }
}

fn from_diag(d: &rpic_core::Diagnostic, k: u32) -> Warn {
    let mut w = Warn {
        kind: d.kind.clone(),
        message: d.message.clone(),
        hint: d.hint.clone(),
        id: None,
        line: d.line,
        col: d.col,
        end_col: d.end_col,
        file: d.file.as_deref().map(str::to_string),
    };
    rebase(&mut w.line, &mut w.file, k);
    w
}

fn from_geo(g: &geopic_core::Warning, k: u32) -> Warn {
    let mut w = Warn {
        kind: g.kind.clone(),
        message: g.message.clone(),
        hint: None,
        id: g.id.clone(),
        line: g.span.as_ref().map(|s| s.line),
        col: g.span.as_ref().map(|s| s.col),
        end_col: g.span.as_ref().map(|s| s.end_col),
        file: g.span.as_ref().and_then(|s| s.file.clone()),
    };
    rebase(&mut w.line, &mut w.file, k);
    w
}

struct Pass {
    d: rpic_core::Drawing,
    scene: rpic_core::SceneOutput,
}

fn compile_pass(text: &str, k: u32, opts: &rpic_core::CompileOptions) -> Result<Pass, Failure> {
    match rpic_core::compile_with_diagnostics(text, opts) {
        Ok(d) => {
            let scene = rpic_core::scene_json(&d, &rpic_core::SceneOptions::default());
            Ok(Pass { d, scene })
        }
        Err(mut e) => {
            let (line, file) = (e.info.line, e.info.file.clone());
            rebase_diag(&mut e.info, k);
            // the readable message leads with `line:col:` of the text that
            // was compiled; say it in the caller's terms too
            if let Some(old) = line
                && file.is_none()
                && let Some(rest) = e.message.strip_prefix(&format!("{old}:"))
            {
                e.message = match (e.info.line, e.info.file.as_deref()) {
                    (Some(l), None) => format!("{l}:{rest}"),
                    (_, Some(f)) => format!("{f}:{old}:{rest}"),
                    _ => e.message.clone(),
                };
            }
            Err(Failure::Compile(e))
        }
    }
}

fn georef_pass(p: &Pass, k: u32, gopts: &geopic_core::GeoOptions) -> Result<GeoOut, Failure> {
    let mut g = geopic_core::georeference(&p.scene.json, gopts)?;
    if !p.d.anims.is_empty() {
        g.warnings
            .push(geopic_core::Warning::animations_ignored(p.d.anims.len()));
    }
    // engine warnings first, then the scene's, then geopic's (the order of
    // the engine's own bindings)
    let mut warnings: Vec<Warn> =
        p.d.warnings
            .iter()
            .chain(p.scene.warnings.iter())
            .map(|d| from_diag(d, k))
            .collect();
    warnings.extend(g.warnings.iter().map(|w| from_geo(w, k)));
    let scale =
        p.d.vars
            .iter()
            .find(|(name, _)| name == "scale")
            .map_or(1.0, |(_, v)| *v);
    Ok(GeoOut {
        geojson: g.features.to_json(),
        warnings,
        registration: g.registration,
        scale,
        rescale: p.d.rescale,
    })
}

fn parse_options(
    json: &str,
) -> Result<(geopic_core::GeoOptions, Vec<geopic_core::NamedFeature>), Failure> {
    let o: GeoOpts = if json.trim().is_empty() {
        GeoOpts::default()
    } else {
        serde_json::from_str(json).map_err(|e| {
            geopic_core::GeoError::new("invalid_options", format!("geo options do not parse: {e}"))
        })?
    };
    let defaults = geopic_core::GeoOptions::default();
    let frame = match o.frame {
        None => None,
        Some(f) => Some(f.parse::<geopic_core::Frame>()?),
    };
    let mut features = Vec::with_capacity(o.features.len());
    for f in o.features {
        if !is_label(&f.name) {
            return Err(Failure::Geo(geopic_core::GeoError::new(
                "invalid_options",
                format!("feature name {:?} is not a pic label", f.name),
            )));
        }
        features.push(geopic_core::NamedFeature {
            name: f.name,
            lon: f.lon,
            lat: f.lat,
            bbox: f.bbox,
        });
    }
    let gopts = geopic_core::GeoOptions {
        frame,
        anchor: o.anchor.map(|[lon, lat]| geopic_core::LonLat { lon, lat }),
        scale: o.scale,
        bearing: o.bearing,
        features: Vec::new(),
        flatten: o.flatten.unwrap_or(defaults.flatten),
        view_scale: o.view_scale,
        screen_classes: o.screen_classes.unwrap_or(defaults.screen_classes),
    };
    Ok((gopts, features))
}

// pic statements defining every injected feature at its position, in the
// source's own units (pic `scale`, before the whole-picture `rescale`). A
// feature with a bbox becomes an invisible labelled box spanning the
// axis-aligned canvas extent of its four corners (so it covers the feature
// under any bearing); a point feature a plain place. Numbers print in Rust's
// shortest round-trip form (never exponent notation).
fn prelude(first: &GeoOut, feats: &[&geopic_core::NamedFeature]) -> Result<String, Failure> {
    let units = first.scale / first.rescale;
    let canvas = |lon: f64, lat: f64| {
        first
            .registration
            .to_canvas(geopic_core::LonLat { lon, lat })
    };
    // a non-finite projection (a bbox reaching the pole under `mercator`, a
    // feature far from an ENU anchor) must be a geo error, not `inf`/`NaN`
    // tokens that fail the final pass as an opaque pic parse error
    let finite = |name: &str, vals: &[f64]| {
        if vals.iter().all(|v| v.is_finite()) {
            Ok(())
        } else {
            Err(Failure::Geo(geopic_core::GeoError::new(
                "invalid_feature",
                format!(
                    "feature `{name}` does not project to a finite canvas position in this frame"
                ),
            )))
        }
    };
    let mut out = String::new();
    for f in feats {
        let [x, y] = canvas(f.lon, f.lat);
        let (x, y) = (x * units, y * units);
        finite(&f.name, &[x, y])?;
        match f.bbox {
            None => out.push_str(&format!("{}: ({x}, {y})\n", f.name)),
            Some([w, s, e, n]) => {
                let corners = [canvas(w, s), canvas(e, s), canvas(e, n), canvas(w, n)];
                let xs = corners.iter().map(|c| c[0]);
                let ys = corners.iter().map(|c| c[1]);
                let wid =
                    (xs.clone().fold(f64::MIN, f64::max) - xs.fold(f64::MAX, f64::min)) * units;
                let ht =
                    (ys.clone().fold(f64::MIN, f64::max) - ys.fold(f64::MAX, f64::min)) * units;
                finite(&f.name, &[wid, ht])?;
                out.push_str(&format!(
                    "{}: box invis wid {wid} ht {ht} at ({x}, {y})\n",
                    f.name
                ));
            }
        }
    }
    Ok(out)
}

// Labels the caller's source itself defines at top level (places or labelled
// objects after the `k` placeholder lines, or inside a `copy` include). A
// label inside a block (`X: [ B: box ]`) does not count: it is not what
// `<B>_lon/_lat` or `arrow to B` reach, so a host feature named `B` is still
// injected.
fn defined_by_source(scene_json: &str, names: &[&str], k: u32) -> Result<Vec<String>, Failure> {
    let scene = geopic_core::parse_scene(scene_json)?;
    let own = |label: &str, span: Option<&geopic_core::Span>| {
        names.contains(&label) && span.is_some_and(|s| s.file.is_some() || s.line > k)
    };
    let mut out: Vec<String> = Vec::new();
    for p in &scene.places {
        if p.block.is_none() && own(&p.label, p.span.as_ref()) && !out.contains(&p.label) {
            out.push(p.label.clone());
        }
    }
    for it in &scene.items {
        if let Some(l) = &it.label
            && it.block.is_none()
            && own(l, it.span.as_ref())
            && !out.contains(l)
        {
            out.push(l.clone());
        }
    }
    Ok(out)
}

// Georeference `src`. Host features the source defines are control points
// of its own geometry; the others are placed by a first pass's registration
// and injected as places (or invisible boxes) before the final pass.
// Diagnostic positions are relative to the caller's `src`.
pub fn run(
    src: &str,
    copts: &rpic_core::CompileOptions,
    options_json: &str,
) -> Result<GeoOut, Failure> {
    let (gopts, feats) = parse_options(options_json)?;
    if feats.is_empty() {
        let p = compile_pass(src, 0, copts)?;
        return georef_pass(&p, 0, &gopts);
    }
    let names: Vec<&str> = feats.iter().map(|f| f.name.as_str()).collect();
    let k = names.len() as u32;
    let placeholders: String = names.iter().map(|n| format!("{n}: (0, 0)\n")).collect();
    let p1 = compile_pass(&format!("{placeholders}{src}"), k, copts)?;
    let defined = defined_by_source(&p1.scene.json, &names, k)?;
    let own: Vec<geopic_core::NamedFeature> = feats
        .iter()
        .filter(|f| defined.contains(&f.name))
        .cloned()
        .collect();
    let inject: Vec<&geopic_core::NamedFeature> = feats
        .iter()
        .filter(|f| !defined.contains(&f.name))
        .collect();
    // pass 1: the registration — declared anchor, or the source's control
    // points, the source-defined features among them
    let pass1 = geopic_core::GeoOptions {
        features: own,
        ..gopts.clone()
    };
    let first = match georef_pass(&p1, k, &pass1) {
        // Nothing but the injected features can place the drawing (no
        // anchor, no control points of the source's own): anchor pass 1 at
        // the first of them, with the declared (or default) scale and
        // bearing. Pass 2 then registers by the features themselves, which
        // land exactly where pass 1 put them. (R-only; DECISIONS.md D3.)
        Err(Failure::Geo(e)) if e.kind == "no_registration" && !inject.is_empty() => {
            let a = inject[0];
            georef_pass(
                &p1,
                k,
                &geopic_core::GeoOptions {
                    anchor: Some(geopic_core::LonLat {
                        lon: a.lon,
                        lat: a.lat,
                    }),
                    ..pass1
                },
            )?
        }
        other => other?,
    };
    if inject.is_empty() {
        return Ok(first);
    }
    let pre = prelude(&first, &inject)?;
    let k2 = pre.lines().count() as u32;
    let p2 = compile_pass(&format!("{pre}{src}"), k2, copts)?;
    let mut out = georef_pass(
        &p2,
        k2,
        &geopic_core::GeoOptions {
            features: feats.clone(),
            ..gopts
        },
    )?;
    if first.registration.method == geopic_core::Method::Anchor
        && first.registration.control_points == 0
    {
        // the injected features were placed *by* the declared values; the
        // second pass's "declared values ignored" would blame the source
        out.warnings
            .retain(|w| w.kind != "ignored_with_control_points");
    }
    Ok(out)
}
