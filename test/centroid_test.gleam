import gleeunit/should

import geokit/centroid
import geokit/geometry
import geokit/latlng

fn approx_equal(a: Float, b: Float, tolerance: Float) -> Bool {
  let delta = case a >. b {
    True -> a -. b
    False -> b -. a
  }
  delta <=. tolerance
}

// --- point ---------------------------------------------------------------

pub fn centroid_of_point_test() -> Nil {
  let assert Ok(p) = latlng.new(lat: 35.6812, lng: 139.7671)
  let assert Ok(c) = centroid.compute(geometry: geometry.Point(p))
  latlng.equal(c, p)
  |> should.be_true
}

// --- line string ---------------------------------------------------------

pub fn centroid_of_line_string_test() -> Nil {
  // Mean of (0,0), (0,2), (2,0), (2,2) is (1,1).
  let assert Ok(a) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(b) = latlng.new(lat: 0.0, lng: 2.0)
  let assert Ok(c) = latlng.new(lat: 2.0, lng: 0.0)
  let assert Ok(d) = latlng.new(lat: 2.0, lng: 2.0)
  let assert Ok(centre) =
    centroid.compute(geometry: geometry.LineString([a, b, c, d]))
  latlng.lat(centre)
  |> should.equal(1.0)
  latlng.lng(centre)
  |> should.equal(1.0)
}

// --- polygon (unit square) ----------------------------------------------

pub fn centroid_of_unit_square_test() -> Nil {
  // Unit square centroid is at (0.5, 0.5).
  let assert Ok(a) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(b) = latlng.new(lat: 0.0, lng: 1.0)
  let assert Ok(c) = latlng.new(lat: 1.0, lng: 1.0)
  let assert Ok(d) = latlng.new(lat: 1.0, lng: 0.0)
  let assert Ok(centre) =
    centroid.compute(geometry: geometry.Polygon([[a, b, c, d, a]]))
  approx_equal(latlng.lat(centre), 0.5, 0.0001)
  |> should.be_true
  approx_equal(latlng.lng(centre), 0.5, 0.0001)
  |> should.be_true
}

pub fn centroid_of_offset_square_test() -> Nil {
  // Square from (10, 20) to (12, 22) has centroid (11, 21).
  let assert Ok(a) = latlng.new(lat: 10.0, lng: 20.0)
  let assert Ok(b) = latlng.new(lat: 10.0, lng: 22.0)
  let assert Ok(c) = latlng.new(lat: 12.0, lng: 22.0)
  let assert Ok(d) = latlng.new(lat: 12.0, lng: 20.0)
  let assert Ok(centre) =
    centroid.compute(geometry: geometry.Polygon([[a, b, c, d, a]]))
  approx_equal(latlng.lat(centre), 11.0, 0.0001)
  |> should.be_true
  approx_equal(latlng.lng(centre), 21.0, 0.0001)
  |> should.be_true
}

// --- empty ---------------------------------------------------------------

pub fn centroid_empty_line_test() -> Nil {
  case centroid.compute(geometry: geometry.LineString([])) {
    Error(centroid.EmptyGeometry) -> Nil
    _ -> should.be_true(False)
  }
}

// --- of_points (List(LatLng) convenience wrapper) -----------------------

pub fn centroid_of_points_matches_line_string_test() -> Nil {
  let assert Ok(a) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(b) = latlng.new(lat: 0.0, lng: 2.0)
  let assert Ok(c) = latlng.new(lat: 2.0, lng: 0.0)
  let assert Ok(d) = latlng.new(lat: 2.0, lng: 2.0)
  let assert Ok(via_helper) = centroid.of_points([a, b, c, d])
  let assert Ok(via_geom) =
    centroid.compute(geometry: geometry.LineString([a, b, c, d]))
  latlng.equal(via_helper, via_geom)
  |> should.be_true
  latlng.lat(via_helper)
  |> should.equal(1.0)
  latlng.lng(via_helper)
  |> should.equal(1.0)
}

pub fn centroid_of_points_single_test() -> Nil {
  let assert Ok(p) = latlng.new(lat: 35.6812, lng: 139.7671)
  let assert Ok(c) = centroid.of_points([p])
  latlng.equal(c, p)
  |> should.be_true
}

pub fn centroid_of_points_empty_test() -> Nil {
  case centroid.of_points([]) {
    Error(centroid.EmptyGeometry) -> Nil
    _ -> should.be_true(False)
  }
}

pub fn centroid_compute_multi_point_test() -> Nil {
  let assert Ok(a) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(b) = latlng.new(lat: 10.0, lng: 10.0)
  let assert Ok(via_multi) =
    centroid.compute(geometry: geometry.MultiPoint([a, b]))
  let assert Ok(via_line) =
    centroid.compute(geometry: geometry.LineString([a, b]))
  latlng.equal(via_multi, via_line) |> should.be_true
}

pub fn centroid_compute_multi_point_empty_test() -> Nil {
  case centroid.compute(geometry: geometry.MultiPoint([])) {
    Error(centroid.EmptyGeometry) -> Nil
    _ -> should.be_true(False)
  }
}

pub fn of_points_closed_ring_unit_square_returns_true_centroid_test() -> Nil {
  // GeoJSON-shaped closed ring (5 points, last duplicates first).
  // Pre-#26, the trailing (0, 0) was double-counted and the mean
  // came out at (0.4, 0.4). With closing-duplicate dedupe the
  // function now returns the unit square's true mean (0.5, 0.5).
  let assert Ok(a) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(b) = latlng.new(lat: 0.0, lng: 1.0)
  let assert Ok(c) = latlng.new(lat: 1.0, lng: 1.0)
  let assert Ok(d) = latlng.new(lat: 1.0, lng: 0.0)
  let assert Ok(e) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(centre) = centroid.of_points(points: [a, b, c, d, e])
  latlng.lat(centre) |> should.equal(0.5)
  latlng.lng(centre) |> should.equal(0.5)
}

pub fn of_points_unclosed_ring_uses_arithmetic_mean_test() -> Nil {
  let assert Ok(a) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(b) = latlng.new(lat: 0.0, lng: 1.0)
  let assert Ok(c) = latlng.new(lat: 1.0, lng: 1.0)
  let assert Ok(d) = latlng.new(lat: 1.0, lng: 0.0)
  let assert Ok(centre) = centroid.of_points(points: [a, b, c, d])
  latlng.lat(centre) |> should.equal(0.5)
  latlng.lng(centre) |> should.equal(0.5)
}

pub fn of_points_interior_adjacent_duplicates_are_kept_test() -> Nil {
  // Only the closing duplicate (last == first) is dropped. An
  // interior repeat is left alone because it may carry weight that
  // the caller intends.
  let assert Ok(a) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(b) = latlng.new(lat: 1.0, lng: 1.0)
  let assert Ok(centre) = centroid.of_points(points: [a, a, b])
  latlng.lng(centre) |> should.equal({ 0.0 +. 0.0 +. 1.0 } /. 3.0)
}

pub fn of_points_single_point_test() -> Nil {
  let assert Ok(only) = latlng.new(lat: 5.0, lng: 10.0)
  let assert Ok(centre) = centroid.of_points(points: [only])
  latlng.lat(centre) |> should.equal(5.0)
  latlng.lng(centre) |> should.equal(10.0)
}

pub fn of_points_empty_errors_test() -> Nil {
  case centroid.of_points(points: []) {
    Error(centroid.EmptyGeometry) -> Nil
    _ -> should.be_true(False)
  }
}
