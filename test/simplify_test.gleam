import gleam/int
import gleam/list
import gleeunit/should

import geokit/geojson
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

pub fn simplify_diagonal_segment_away_from_origin_test() -> Nil {
  // Segment (lng 20, lat 10) - (lng 22, lat 12) with the middle point at
  // (lng 20.5, lat 12): its distance to the line is 1.5 / sqrt(2), about
  // 1.061 degrees. Both ends are away from the origin and the segment is
  // diagonal, so a formula that adds a coordinate instead of subtracting it
  // gives another distance.
  let assert Ok(a) = latlng.new(lat: 10.0, lng: 20.0)
  let assert Ok(b) = latlng.new(lat: 12.0, lng: 20.5)
  let assert Ok(c) = latlng.new(lat: 12.0, lng: 22.0)
  simplify.line_string(points: [a, b, c], tolerance: 1.0)
  |> should.equal(Ok([a, b, c]))
  simplify.line_string(points: [a, b, c], tolerance: 1.1)
  |> should.equal(Ok([a, c]))
}

pub fn compute_accepts_zero_tolerance_test() -> Nil {
  // Zero is the smallest valid tolerance; only negative values are errors.
  let assert Ok(a) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(b) = latlng.new(lat: 1.0, lng: 0.5)
  let assert Ok(c) = latlng.new(lat: 0.0, lng: 1.0)
  simplify.compute(geometry: geometry.LineString([a, b, c]), tolerance: 0.0)
  |> should.equal(Ok(geometry.LineString([a, b, c])))
}

pub fn simplify_closed_line_away_from_origin_test() -> Nil {
  // The first and last points coincide, so the distance is measured to
  // that point: (lng 20.3, lat 10.4) is 0.5 degrees from (lng 20, lat 10).
  let assert Ok(a) = latlng.new(lat: 10.0, lng: 20.0)
  let assert Ok(b) = latlng.new(lat: 10.4, lng: 20.3)
  simplify.line_string(points: [a, b, a], tolerance: 0.45)
  |> should.equal(Ok([a, b, a]))
  simplify.line_string(points: [a, b, a], tolerance: 0.55)
  |> should.equal(Ok([a, a]))
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

pub fn compute_multi_point_is_no_op_test() -> Nil {
  let assert Ok(a) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(b) = latlng.new(lat: 0.0, lng: 0.5)
  let assert Ok(c) = latlng.new(lat: 0.0, lng: 1.0)
  // A bag of points has no edges to collapse, so simplify leaves it
  // unchanged regardless of tolerance.
  let assert Ok(geom) =
    simplify.compute(geometry: geometry.MultiPoint([a, b, c]), tolerance: 0.001)
  case geom {
    geometry.MultiPoint(points) ->
      list.length(points)
      |> should.equal(3)
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

// --- long inputs (20_000 points) ----------------------------------------

// 20_000 points walking the perimeter of the square [0, 10] x [0, 10]
// counter-clockwise from (0, 0). The ring is not closed.
fn square_perimeter() -> List(latlng.LatLng) {
  list.repeat(Nil, times: 20_000)
  |> list.index_map(fn(_, i) {
    let side = i / 5000
    let t = int.to_float(i % 5000) /. 500.0
    case side {
      0 -> latlng.wrap(lat: 0.0, lng: t)
      1 -> latlng.wrap(lat: t, lng: 10.0)
      2 -> latlng.wrap(lat: 10.0, lng: 10.0 -. t)
      _ -> latlng.wrap(lat: 10.0 -. t, lng: 0.0)
    }
  })
}

pub fn simplify_long_square_test() -> Nil {
  let assert Ok(simplified) =
    simplify.line_string(points: square_perimeter(), tolerance: 1.0e-6)
  // Only the start and the three later corners survive.
  list.map(simplified, fn(p) { #(latlng.lat(p), latlng.lng(p)) })
  |> should.equal([
    #(0.0, 0.0),
    #(0.0, 10.0),
    #(10.0, 10.0),
    #(10.0, 0.0),
    #(10.0 -. 4999.0 /. 500.0, 0.0),
  ])
}

pub fn simplify_long_random_walk_test() -> Nil {
  let walk = random_walk(20_000)
  let assert Ok(simplified) =
    simplify.line_string(points: walk, tolerance: 0.05)
  // Count recorded from the recursive implementation this replaced
  // (it ran on Erlang; JavaScript overflowed its stack).
  list.length(simplified)
  |> should.equal(9694)
  list.first(simplified)
  |> should.equal(list.first(walk))
  list.last(simplified)
  |> should.equal(list.last(walk))
}

// Deterministic random walk from the Park-Miller generator (products
// stay below 2^53, so both targets agree).
fn random_walk(n: Int) -> List(latlng.LatLng) {
  let #(_, _, _, points) =
    list.fold(list.repeat(Nil, times: n), #(12_345, 0.0, 0.0, []), fn(acc, _) {
      let #(seed, lat, lng, points) = acc
      let seed = seed * 16_807 % 2_147_483_647
      let step_lat = int.to_float(seed % 2001 - 1000) /. 10_000.0
      let seed = seed * 16_807 % 2_147_483_647
      let step_lng = int.to_float(seed % 2001 - 1000) /. 10_000.0
      let lat = lat +. step_lat
      let lng = lng +. step_lng
      #(seed, lat, lng, [latlng.wrap(lat: lat, lng: lng), ..points])
    })
  list.reverse(points)
}

// --- closed polygon rings -------------------------------------------------

fn ll(lat: Float, lng: Float) -> latlng.LatLng {
  latlng.new_or_panic(lat: lat, lng: lng)
}

pub fn compute_polygon_keeps_ring_valid_test() -> Nil {
  // A square with a collinear point in the middle of every side. The
  // ring starts and ends at the same vertex, so plain Douglas-Peucker
  // over it measures every point against a zero-length chord.
  let ring = [
    ll(0.0, 0.0),
    ll(0.0, 5.0),
    ll(0.0, 10.0),
    ll(5.0, 10.0),
    ll(10.0, 10.0),
    ll(10.0, 5.0),
    ll(10.0, 0.0),
    ll(5.0, 0.0),
    ll(0.0, 0.0),
  ]
  let assert Ok(simplified) =
    simplify.compute(geometry: geometry.Polygon([ring]), tolerance: 1.0)
  simplified
  |> should.equal(
    geometry.Polygon([
      [
        ll(0.0, 0.0),
        ll(0.0, 10.0),
        ll(10.0, 10.0),
        ll(10.0, 0.0),
        ll(0.0, 0.0),
      ],
    ]),
  )
  geojson.encode_geometry(geometry: simplified)
  |> geojson.decode_geometry
  |> should.equal(Ok(simplified))
}

pub fn compute_polygon_keeps_original_when_ring_would_collapse_test() -> Nil {
  // At a tolerance larger than the square, both halves reduce to their
  // endpoints and only three positions would remain, which is not a
  // valid ring, so the original ring is kept.
  let ring = [
    ll(0.0, 0.0),
    ll(0.0, 10.0),
    ll(10.0, 10.0),
    ll(10.0, 0.0),
    ll(0.0, 0.0),
  ]
  let assert Ok(simplified) =
    simplify.compute(
      geometry: geometry.MultiPolygon([[ring]]),
      tolerance: 100.0,
    )
  simplified
  |> should.equal(geometry.MultiPolygon([[ring]]))
  geojson.encode_geometry(geometry: simplified)
  |> geojson.decode_geometry
  |> should.equal(Ok(simplified))
}

// --- tiny segments --------------------------------------------------------

pub fn simplify_tiny_segment_test() -> Nil {
  // The chord from (0, 0) to (lng 1e-12, lat 0) is 1e-12 degrees long
  // and the middle point is 1e-12 degrees off it, so it survives a
  // tolerance of 0.9e-12 and is dropped at 1.1e-12.
  let a = ll(0.0, 0.0)
  let b = ll(1.0e-12, 0.5e-12)
  let c = ll(0.0, 1.0e-12)
  simplify.line_string(points: [a, b, c], tolerance: 0.9e-12)
  |> should.equal(Ok([a, b, c]))
  simplify.line_string(points: [a, b, c], tolerance: 1.1e-12)
  |> should.equal(Ok([a, c]))
}
