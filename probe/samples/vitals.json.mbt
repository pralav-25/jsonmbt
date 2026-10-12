///|
pub struct Inner {
  x : Int32
  ratio : Double
}

///|
pub struct Vitals {
  big : Int64
  d : Double
  inner : Inner
  meta : Map[String, String]
  ok : Bool
  note : String
}

///|
pub let vitals : Vitals = Vitals::{
  big: 9223372036854775807,
  d: 1.5e3,
  inner: { x: -1, ratio: 0.25, },
  meta: { "Content-Type": "text/plain" },
  ok: true,
  note: "esc\"ape\ttab",
}
