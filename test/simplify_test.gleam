import gleam/list
import gleeunit/should

import geokit/latlng
import geokit/simplify

// --- basic ---------------------------------------------------------------

pub fn simplify_empty_test() -> Nil {
  let assert Ok(result) = simplify.line_string(points: [], tolerance: 0.1)
  list.length(result)
  |> should.equal(0)
}

pub fn simplify_single_point_test() -> Nil {
  let assert Ok(p) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(result) = simplify.line_string(points: [p], tolerance: 0.1)
  list.length(result)
  |> should.equal(1)
}

pub fn simplify_two_points_test() -> Nil {
  let assert Ok(a) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(b) = latlng.new(lat: 1.0, lng: 1.0)
  let assert Ok(result) = simplify.line_string(points: [a, b], tolerance: 0.1)
  list.length(result)
  |> should.equal(2)
}

// --- collinear -----------------------------------------------------------

pub fn simplify_collinear_drops_middle_test() -> Nil {
  // a -- b -- c collinear: b should be dropped at any positive
  // tolerance.
  let assert Ok(a) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(b) = latlng.new(lat: 0.0, lng: 0.5)
  let assert Ok(c) = latlng.new(lat: 0.0, lng: 1.0)
  let assert Ok(result) =
    simplify.line_string(points: [a, b, c], tolerance: 0.001)
  list.length(result)
  |> should.equal(2)
}

pub fn simplify_kept_when_perpendicular_test() -> Nil {
  // a (0,0) → b (1, 0.5) → c (0, 1). Point b has perpendicular
  // distance 0.5 from line a-c, so it survives any tolerance below
  // 0.5.
  let assert Ok(a) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(b) = latlng.new(lat: 1.0, lng: 0.5)
  let assert Ok(c) = latlng.new(lat: 0.0, lng: 1.0)
  let assert Ok(result) =
    simplify.line_string(points: [a, b, c], tolerance: 0.1)
  list.length(result)
  |> should.equal(3)
}

pub fn simplify_dropped_at_large_tolerance_test() -> Nil {
  // Same shape, with tolerance > 0.5: middle point is dropped.
  let assert Ok(a) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(b) = latlng.new(lat: 1.0, lng: 0.5)
  let assert Ok(c) = latlng.new(lat: 0.0, lng: 1.0)
  let assert Ok(result) =
    simplify.line_string(points: [a, b, c], tolerance: 1.0)
  list.length(result)
  |> should.equal(2)
}

// --- error ---------------------------------------------------------------

pub fn simplify_negative_tolerance_test() -> Nil {
  let assert Ok(p) = latlng.new(lat: 0.0, lng: 0.0)
  case simplify.line_string(points: [p], tolerance: -0.1) {
    Error(simplify.NegativeTolerance(tolerance: -0.1)) -> Nil
    _ -> should.be_true(False)
  }
}
