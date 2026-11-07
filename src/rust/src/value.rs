// JSON → R, for results the engine only exposes as JSON text (the compile
// bundle, a registration). Objects become named lists; an array becomes an
// atomic vector when every element is a number, string or logical (so a
// bbox is `c(x0, y0, x1, y1)`), a list otherwise; `null` becomes `NA` (the
// package's idiom for absent fields). Numbers are doubles. Object keys come
// in serde_json's map order (sorted) — callers order top-level keys.

use extendr_api::prelude::*;
use serde_json::Value;

pub fn to_robj(v: &Value) -> Robj {
    match v {
        Value::Null => r!(NA_LOGICAL),
        Value::Bool(b) => r!(*b),
        Value::Number(n) => r!(n.as_f64().unwrap_or(f64::NAN)),
        Value::String(s) => r!(s.as_str()),
        Value::Array(a) => array(a),
        Value::Object(m) => {
            let names: Vec<&str> = m.keys().map(String::as_str).collect();
            let values: Vec<Robj> = m.values().map(to_robj).collect();
            match List::from_names_and_values(names, values) {
                Ok(l) => l.into(),
                Err(_) => r!(NULL),
            }
        }
    }
}

fn array(a: &[Value]) -> Robj {
    if a.is_empty() {
        return List::new(0).into();
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
    List::from_values(a.iter().map(to_robj)).into()
}
