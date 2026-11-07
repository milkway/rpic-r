// JSON → R, for results the engine only exposes as JSON text (the compile
// bundle, a registration). Objects become named lists; an array becomes an
// atomic vector when every element is a number, string or logical (so a
// bbox is `c(x0, y0, x1, y1)`), a list otherwise; `null` becomes `NA` (the
// package's idiom for absent fields). Numbers are doubles. Object keys come
// in serde_json's map order (sorted) — callers order top-level keys.

use extendr_api::prelude::*;
use serde_json::Value;

pub fn to_robj(v: &Value) -> Robj {
    convert(v, 1)
}

// The same, for values R hands back to a JSON serialiser (MapLibre layer
// specs on their way to mapgl/htmlwidgets, which use `auto_unbox = TRUE`):
// an array becomes an atomic vector only when it has two or more elements,
// so a one-element array (`["zoom"]`, `["geometry-type"]`) stays a list and
// is written back as an array, not unboxed to a scalar.
pub fn to_robj_arrays(v: &Value) -> Robj {
    convert(v, 2)
}

// `min_atomic`: the shortest homogeneous array that becomes an atomic vector.
fn convert(v: &Value, min_atomic: usize) -> Robj {
    match v {
        Value::Null => r!(NA_LOGICAL),
        Value::Bool(b) => r!(*b),
        Value::Number(n) => r!(n.as_f64().unwrap_or(f64::NAN)),
        Value::String(s) => r!(s.as_str()),
        Value::Array(a) => array(a, min_atomic),
        Value::Object(m) => {
            let names: Vec<&str> = m.keys().map(String::as_str).collect();
            let values: Vec<Robj> = m.values().map(|x| convert(x, min_atomic)).collect();
            match List::from_names_and_values(names, values) {
                Ok(l) => l.into(),
                Err(_) => r!(NULL),
            }
        }
    }
}

fn array(a: &[Value], min_atomic: usize) -> Robj {
    if a.is_empty() || a.len() < min_atomic {
        return List::from_values(a.iter().map(|x| convert(x, min_atomic))).into();
    }
    if a.iter().all(Value::is_number) {
        let v: Vec<f64> = a.iter().map(|x| x.as_f64().unwrap_or(f64::NAN)).collect();
        return r!(v);
    }
    if a.iter().all(Value::is_string) {
        let v: Vec<&str> = a.iter().map(|x| x.as_str().unwrap_or("")).collect();
        return r!(v);
    }
    if a.iter().all(Value::is_boolean) {
        let v: Vec<bool> = a.iter().map(|x| x.as_bool().unwrap_or(false)).collect();
        return r!(v);
    }
    List::from_values(a.iter().map(|x| convert(x, min_atomic))).into()
}
