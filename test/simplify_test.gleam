import gleam/list
import gleeunit/should

import geokit/geometry
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

// --- compute (issue #5) -------------------------------------------------

pub fn compute_point_test() -> Nil {
  let assert Ok(p) = latlng.new(lat: 35.0, lng: 139.0)
  let assert Ok(geom) =
    simplify.compute(geometry: geometry.Point(p), tolerance: 0.001)
  case geom {
    geometry.Point(q) ->
      latlng.equal(p, q)
      |> should.be_true
    _ -> should.be_true(False)
  }
}

pub fn compute_line_string_drops_collinear_test() -> Nil {
  let assert Ok(a) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(b) = latlng.new(lat: 0.0, lng: 0.5)
  let assert Ok(c) = latlng.new(lat: 0.0, lng: 1.0)
  let assert Ok(geom) =
    simplify.compute(geometry: geometry.LineString([a, b, c]), tolerance: 0.001)
  case geom {
    geometry.LineString(points) ->
      list.length(points)
      |> should.equal(2)
    _ -> should.be_true(False)
  }
}

pub fn compute_polygon_simplifies_each_ring_test() -> Nil {
  let assert Ok(a) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(b) = latlng.new(lat: 0.0, lng: 0.5)
  let assert Ok(c) = latlng.new(lat: 0.0, lng: 1.0)
  let assert Ok(d) = latlng.new(lat: 1.0, lng: 1.0)
  let assert Ok(e) = latlng.new(lat: 1.0, lng: 0.0)
  // Exterior ring has a collinear middle point on the bottom edge
  // that should be dropped.
  let ring = [a, b, c, d, e, a]
  let assert Ok(geom) =
    simplify.compute(geometry: geometry.Polygon([ring]), tolerance: 0.001)
  case geom {
    geometry.Polygon([simplified]) -> {
      // 5 corners + closure; middle of bottom edge dropped.
      list.length(simplified)
      |> should.equal(5)
    }
    _ -> should.be_true(False)
  }
}

pub fn compute_multipolygon_recurses_test() -> Nil {
  let assert Ok(a) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(b) = latlng.new(lat: 0.0, lng: 0.5)
  let assert Ok(c) = latlng.new(lat: 0.0, lng: 1.0)
  let polygon = [[a, b, c, a]]
  let assert Ok(geom) =
    simplify.compute(
      geometry: geometry.MultiPolygon([polygon, polygon]),
      tolerance: 0.001,
    )
  case geom {
    geometry.MultiPolygon(ps) ->
      list.length(ps)
      |> should.equal(2)
    _ -> should.be_true(False)
  }
}

pub fn compute_negative_tolerance_test() -> Nil {
  let assert Ok(p) = latlng.new(lat: 0.0, lng: 0.0)
  case simplify.compute(geometry: geometry.Point(p), tolerance: -0.5) {
    Error(simplify.NegativeTolerance(tolerance: -0.5)) -> Nil
    _ -> should.be_true(False)
  }
}
