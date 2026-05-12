import gleeunit/should

import geokit/distance
import geokit/latlng

// Approximate comparison: returns True if |a - b| <= tolerance.
fn approx_equal(a: Float, b: Float, tolerance: Float) -> Bool {
  let delta = case a >. b {
    True -> a -. b
    False -> b -. a
  }
  delta <=. tolerance
}

// --- haversine -----------------------------------------------------------

pub fn distance_zero_for_same_point_test() -> Nil {
  let assert Ok(tokyo) = latlng.new(lat: 35.6812, lng: 139.7671)
  distance.haversine(a: tokyo, b: tokyo)
  |> approx_equal(0.0, 0.001)
  |> should.be_true
}

pub fn tokyo_to_osaka_test() -> Nil {
  // Tokyo (35.6812, 139.7671) to Osaka (34.6937, 135.5023).
  // Reference: Python `math` haversine with WGS84 mean radius
  // ≈ 402_785 m.
  let assert Ok(tokyo) = latlng.new(lat: 35.6812, lng: 139.7671)
  let assert Ok(osaka) = latlng.new(lat: 34.6937, lng: 135.5023)
  let d = distance.haversine(a: tokyo, b: osaka)
  approx_equal(d, 402_785.0, 100.0)
  |> should.be_true
}

pub fn london_to_paris_test() -> Nil {
  // London (51.5074, -0.1278) to Paris (48.8566, 2.3522). Reference
  // haversine on WGS84 mean radius ≈ 343_500 m.
  let assert Ok(london) = latlng.new(lat: 51.5074, lng: -0.1278)
  let assert Ok(paris) = latlng.new(lat: 48.8566, lng: 2.3522)
  let d = distance.haversine(a: london, b: paris)
  approx_equal(d, 343_500.0, 4000.0)
  |> should.be_true
}

pub fn ny_to_la_test() -> Nil {
  // NYC (40.7128, -74.0060) to LA (34.0522, -118.2437). Reference ≈
  // 3_935_500 m.
  let assert Ok(nyc) = latlng.new(lat: 40.7128, lng: -74.006)
  let assert Ok(la) = latlng.new(lat: 34.0522, lng: -118.2437)
  let d = distance.haversine(a: nyc, b: la)
  approx_equal(d, 3_935_500.0, 20_000.0)
  |> should.be_true
}

pub fn antipodes_test() -> Nil {
  // Two diametrically opposite points should be ≈ half the Earth's
  // circumference: π × 6_371_008.8 m ≈ 20_015_115 m.
  let assert Ok(a) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(b) = latlng.new(lat: 0.0, lng: 180.0)
  let d = distance.haversine(a: a, b: b)
  approx_equal(d, 20_015_115.0, 1000.0)
  |> should.be_true
}

pub fn equator_quarter_test() -> Nil {
  // 0°E to 90°E along the equator: π/2 × 6_371_008.8 m ≈ 10_007_557 m.
  let assert Ok(a) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(b) = latlng.new(lat: 0.0, lng: 90.0)
  let d = distance.haversine(a: a, b: b)
  approx_equal(d, 10_007_557.0, 1000.0)
  |> should.be_true
}

pub fn haversine_km_matches_metres_test() -> Nil {
  let assert Ok(a) = latlng.new(lat: 35.0, lng: 139.0)
  let assert Ok(b) = latlng.new(lat: 36.0, lng: 140.0)
  let metres = distance.haversine(a: a, b: b)
  let km = distance.haversine_km(a: a, b: b)
  approx_equal(metres /. 1000.0, km, 0.000_001)
  |> should.be_true
}

pub fn symmetric_test() -> Nil {
  let assert Ok(a) = latlng.new(lat: 12.34, lng: 56.78)
  let assert Ok(b) = latlng.new(lat: -23.45, lng: 67.89)
  let d_ab = distance.haversine(a: a, b: b)
  let d_ba = distance.haversine(a: b, b: a)
  approx_equal(d_ab, d_ba, 0.001)
  |> should.be_true
}
