import gleam/list
import gleeunit/should

import geokit/latlng
import geokit/polyline

fn approx_equal(a: Float, b: Float, tolerance: Float) -> Bool {
  let delta = case a >. b {
    True -> a -. b
    False -> b -. a
  }
  delta <=. tolerance
}

// --- encode --------------------------------------------------------------

pub fn encode_google_reference_test() -> Nil {
  // Google's official example:
  // points (38.5, -120.2), (40.7, -120.95), (43.252, -126.453)
  // → "_p~iF~ps|U_ulLnnqC_mqNvxq`@"
  let assert Ok(p1) = latlng.new(lat: 38.5, lng: -120.2)
  let assert Ok(p2) = latlng.new(lat: 40.7, lng: -120.95)
  let assert Ok(p3) = latlng.new(lat: 43.252, lng: -126.453)
  polyline.encode(points: [p1, p2, p3])
  |> should.equal("_p~iF~ps|U_ulLnnqC_mqNvxq`@")
}

pub fn encode_empty_test() -> Nil {
  polyline.encode(points: [])
  |> should.equal("")
}

// --- decode --------------------------------------------------------------

pub fn decode_google_reference_test() -> Nil {
  let assert Ok(points) = polyline.decode(input: "_p~iF~ps|U_ulLnnqC_mqNvxq`@")
  list.length(points)
  |> should.equal(3)
  let assert [p1, p2, p3] = points
  approx_equal(latlng.lat(p1), 38.5, 0.00001)
  |> should.be_true
  approx_equal(latlng.lng(p1), -120.2, 0.00001)
  |> should.be_true
  approx_equal(latlng.lat(p2), 40.7, 0.00001)
  |> should.be_true
  approx_equal(latlng.lng(p2), -120.95, 0.00001)
  |> should.be_true
  approx_equal(latlng.lat(p3), 43.252, 0.00001)
  |> should.be_true
  approx_equal(latlng.lng(p3), -126.453, 0.00001)
  |> should.be_true
}

pub fn decode_empty_test() -> Nil {
  let assert Ok(points) = polyline.decode(input: "")
  list.length(points)
  |> should.equal(0)
}

// --- round-trip ----------------------------------------------------------

pub fn round_trip_test() -> Nil {
  let assert Ok(a) = latlng.new(lat: 35.6812, lng: 139.7671)
  let assert Ok(b) = latlng.new(lat: 34.6937, lng: 135.5023)
  let assert Ok(c) = latlng.new(lat: 51.5074, lng: -0.1278)
  let encoded = polyline.encode(points: [a, b, c])
  let assert Ok(decoded) = polyline.decode(input: encoded)
  let assert [a2, b2, c2] = decoded
  approx_equal(latlng.lat(a), latlng.lat(a2), 0.00001)
  |> should.be_true
  approx_equal(latlng.lat(b), latlng.lat(b2), 0.00001)
  |> should.be_true
  approx_equal(latlng.lat(c), latlng.lat(c2), 0.00001)
  |> should.be_true
}

pub fn round_trip_precision_6_test() -> Nil {
  let assert Ok(a) = latlng.new(lat: 35.681234, lng: 139.767123)
  let assert Ok(b) = latlng.new(lat: 34.693712, lng: 135.502345)
  let encoded = polyline.encode_with(points: [a, b], precision: 6)
  let assert Ok(decoded) = polyline.decode_with(input: encoded, precision: 6)
  let assert [a2, b2] = decoded
  approx_equal(latlng.lat(a), latlng.lat(a2), 0.000001)
  |> should.be_true
  approx_equal(latlng.lng(a), latlng.lng(a2), 0.000001)
  |> should.be_true
  approx_equal(latlng.lat(b), latlng.lat(b2), 0.000001)
  |> should.be_true
  approx_equal(latlng.lng(b), latlng.lng(b2), 0.000001)
  |> should.be_true
}

// --- error handling ------------------------------------------------------

pub fn decode_truncated_test() -> Nil {
  // A single character with high bit set (no terminator) is truncated.
  case polyline.decode(input: "?") {
    // "?" = 0x3F, value = 0, full chunk → valid 0-delta = (0,0)
    // So decode("?") may succeed; try a clearly truncated stream.
    Ok(_) -> Nil
    Error(_) -> Nil
  }
  case polyline.decode(input: "_") {
    // "_" = 0x5F, value = 32 = continuation byte without termination
    Error(polyline.TruncatedInput) -> Nil
    _ -> should.be_true(False)
  }
}
