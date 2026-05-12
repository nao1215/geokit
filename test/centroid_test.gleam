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
