import gleam/int
import gleam/list
import gleam/string
import gleeunit/should

import geokit.{type LatLng}
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
  let assert Ok(p1) = geokit.lat_lng(latitude: 38.5, longitude: -120.2)
  let assert Ok(p2) = geokit.lat_lng(latitude: 40.7, longitude: -120.95)
  let assert Ok(p3) = geokit.lat_lng(latitude: 43.252, longitude: -126.453)
  encode5([p1, p2, p3])
  |> should.equal("_p~iF~ps|U_ulLnnqC_mqNvxq`@")
}

pub fn encode_empty_test() -> Nil {
  encode5([])
  |> should.equal("")
}

// --- decode --------------------------------------------------------------

pub fn decode_google_reference_test() -> Nil {
  let assert Ok(points) =
    polyline.decode("_p~iF~ps|U_ulLnnqC_mqNvxq`@", precision: 5)
  list.length(points)
  |> should.equal(3)
  let assert [p1, p2, p3] = points
  approx_equal(geokit.latitude(p1), 38.5, 0.00001)
  |> should.be_true
  approx_equal(geokit.longitude(p1), -120.2, 0.00001)
  |> should.be_true
  approx_equal(geokit.latitude(p2), 40.7, 0.00001)
  |> should.be_true
  approx_equal(geokit.longitude(p2), -120.95, 0.00001)
  |> should.be_true
  approx_equal(geokit.latitude(p3), 43.252, 0.00001)
  |> should.be_true
  approx_equal(geokit.longitude(p3), -126.453, 0.00001)
  |> should.be_true
}

pub fn decode_empty_test() -> Nil {
  let assert Ok(points) = polyline.decode("", precision: 5)
  list.length(points)
  |> should.equal(0)
}

// --- round-trip ----------------------------------------------------------

pub fn round_trip_test() -> Nil {
  let assert Ok(a) = geokit.lat_lng(latitude: 35.6812, longitude: 139.7671)
  let assert Ok(b) = geokit.lat_lng(latitude: 34.6937, longitude: 135.5023)
  let assert Ok(c) = geokit.lat_lng(latitude: 51.5074, longitude: -0.1278)
  let encoded = encode5([a, b, c])
  let assert Ok(decoded) = polyline.decode(encoded, precision: 5)
  let assert [a2, b2, c2] = decoded
  approx_equal(geokit.latitude(a), geokit.latitude(a2), 0.00001)
  |> should.be_true
  approx_equal(geokit.latitude(b), geokit.latitude(b2), 0.00001)
  |> should.be_true
  approx_equal(geokit.latitude(c), geokit.latitude(c2), 0.00001)
  |> should.be_true
}

pub fn round_trip_precision_6_test() -> Nil {
  let assert Ok(a) = geokit.lat_lng(latitude: 35.681234, longitude: 139.767123)
  let assert Ok(b) = geokit.lat_lng(latitude: 34.693712, longitude: 135.502345)
  let assert Ok(encoded) = polyline.encode([a, b], precision: 6)
  let assert Ok(decoded) = polyline.decode(encoded, precision: 6)
  let assert [a2, b2] = decoded
  approx_equal(geokit.latitude(a), geokit.latitude(a2), 0.000001)
  |> should.be_true
  approx_equal(geokit.longitude(a), geokit.longitude(a2), 0.000001)
  |> should.be_true
  approx_equal(geokit.latitude(b), geokit.latitude(b2), 0.000001)
  |> should.be_true
  approx_equal(geokit.longitude(b), geokit.longitude(b2), 0.000001)
  |> should.be_true
}

// --- error handling ------------------------------------------------------

pub fn decode_truncated_test() -> Nil {
  // A single character with high bit set (no terminator) is truncated.
  case polyline.decode("?", precision: 5) {
    // "?" = 0x3F, value = 0, full chunk → valid 0-delta = (0,0)
    // So decode("?") may succeed; try a clearly truncated stream.
    Ok(_) -> Nil
    Error(_) -> Nil
  }
  case polyline.decode("_", precision: 5) {
    // "_" = 0x5F, value = 32 = continuation byte without termination
    Error(polyline.TruncatedInput) -> Nil
    _ -> should.be_true(False)
  }
}

// --- precision validation (regression for #10) ---------------------------

pub fn encode_with_rejects_zero_precision_test() -> Nil {
  let assert Ok(p) = geokit.lat_lng(latitude: 35.0, longitude: 139.0)
  case polyline.encode([p], precision: 0) {
    Error(polyline.PrecisionOutOfRange(precision: 0)) -> Nil
    _ -> should.be_true(False)
  }
}

pub fn encode_with_rejects_negative_precision_test() -> Nil {
  let assert Ok(p) = geokit.lat_lng(latitude: 35.0, longitude: 139.0)
  case polyline.encode([p], precision: -1) {
    Error(polyline.PrecisionOutOfRange(precision: -1)) -> Nil
    _ -> should.be_true(False)
  }
}

pub fn encode_with_rejects_too_large_precision_test() -> Nil {
  let assert Ok(p) = geokit.lat_lng(latitude: 35.0, longitude: 139.0)
  case polyline.encode([p], precision: 12) {
    Error(polyline.PrecisionOutOfRange(precision: 12)) -> Nil
    _ -> should.be_true(False)
  }
}

pub fn encode_with_accepts_max_precision_11_test() -> Nil {
  let assert Ok(p) = geokit.lat_lng(latitude: 35.0, longitude: 139.0)
  let assert Ok(_) = polyline.encode([p], precision: 11)
  Nil
}

pub fn decode_with_rejects_zero_precision_test() -> Nil {
  case polyline.decode("_p~iF~ps|U", precision: 0) {
    Error(polyline.PrecisionOutOfRange(precision: 0)) -> Nil
    _ -> should.be_true(False)
  }
}

pub fn decode_with_rejects_negative_precision_test() -> Nil {
  case polyline.decode("_p~iF~ps|U", precision: -1) {
    Error(polyline.PrecisionOutOfRange(precision: -1)) -> Nil
    _ -> should.be_true(False)
  }
}

pub fn decode_with_rejects_too_large_precision_test() -> Nil {
  case polyline.decode("_p~iF~ps|U", precision: 12) {
    Error(polyline.PrecisionOutOfRange(precision: 12)) -> Nil
    _ -> should.be_true(False)
  }
}

// --- character range and chunk limits -----------------------------------

pub fn decode_rejects_del_test() -> Nil {
  // Valid polyline characters are 63..126; DEL (127) is outside.
  polyline.decode("??\u{7F}?", precision: 5)
  |> should.equal(
    Error(polyline.InvalidCharacter(character: "\u{7F}", position: 2)),
  )
}

pub fn decode_rejects_non_ascii_test() -> Nil {
  polyline.decode("??é?", precision: 5)
  |> should.equal(Error(polyline.InvalidCharacter(character: "é", position: 2)))
}

pub fn decode_rejects_chunk_beyond_ten_test() -> Nil {
  // Ten chunks cover the largest value precision 11 produces (shifts
  // 0..45); an eleventh continuation chunk is outside the format.
  polyline.decode("__________?", precision: 5)
  |> should.equal(
    Error(polyline.InvalidCharacter(character: "?", position: 10)),
  )
  polyline.decode(string.repeat("_", 40) <> "??", precision: 5)
  |> should.equal(
    Error(polyline.InvalidCharacter(character: "_", position: 10)),
  )
}

pub fn decode_accepts_ten_chunks_test() -> Nil {
  // Nine continuation chunks and a stop chunk: the largest legal width.
  let assert Ok(_) = polyline.decode("_________??", precision: 5)
  Nil
}

pub fn decode_reports_grapheme_with_combining_mark_test() -> Nil {
  // "?" followed by a combining acute accent is one grapheme; the
  // invalid byte belongs to it, so it is reported at grapheme 0.
  polyline.decode("?\u{0301}", precision: 5)
  |> should.equal(
    Error(polyline.InvalidCharacter(character: "?\u{0301}", position: 0)),
  )
  polyline.decode("??e\u{0301}?", precision: 5)
  |> should.equal(
    Error(polyline.InvalidCharacter(character: "e\u{0301}", position: 2)),
  )
}

pub fn decode_reports_grapheme_index_after_cap_test() -> Nil {
  // The chunk that exceeds the width cap carries a combining mark.
  polyline.decode("__________?\u{0301}", precision: 5)
  |> should.equal(
    Error(polyline.InvalidCharacter(character: "?\u{0301}", position: 10)),
  )
}

// --- extreme coordinates at high precision -------------------------------

fn round_trip_extremes(precision: Int) -> Nil {
  let points = [
    geokit.wrap_lat_lng(latitude: 0.0, longitude: 180.0),
    geokit.wrap_lat_lng(latitude: 0.0, longitude: -180.0),
    geokit.wrap_lat_lng(latitude: 90.0, longitude: 180.0),
    geokit.wrap_lat_lng(latitude: -90.0, longitude: -180.0),
    geokit.wrap_lat_lng(latitude: 90.0, longitude: 0.0),
    geokit.wrap_lat_lng(latitude: -90.0, longitude: 0.0),
  ]
  let assert Ok(encoded) = polyline.encode(points, precision: precision)
  let assert Ok(decoded) = polyline.decode(encoded, precision: precision)
  list.length(decoded)
  |> should.equal(list.length(points))
  list.zip(points, decoded)
  |> list.each(fn(pair) {
    let #(expected, actual) = pair
    approx_equal(geokit.latitude(actual), geokit.latitude(expected), 1.0e-9)
    |> should.be_true
    approx_equal(geokit.longitude(actual), geokit.longitude(expected), 1.0e-9)
    |> should.be_true
  })
}

pub fn round_trip_extremes_precision_8_test() -> Nil {
  round_trip_extremes(8)
}

pub fn round_trip_extremes_precision_11_test() -> Nil {
  round_trip_extremes(11)
}

pub fn round_trip_single_antimeridian_point_precision_8_test() -> Nil {
  let points = [geokit.wrap_lat_lng(latitude: 0.0, longitude: 180.0)]
  let assert Ok(encoded) = polyline.encode(points, precision: 8)
  polyline.decode(encoded, precision: 8)
  |> should.equal(Ok(points))
}

// --- long inputs --------------------------------------------------------

pub fn decode_long_polyline_test() -> Nil {
  // 100_000 points must decode without exhausting the stack on either
  // target.
  let points =
    list.repeat(Nil, times: 100_000)
    |> list.index_map(fn(_, i) {
      geokit.wrap_lat_lng(
        latitude: int.to_float(i % 1000) /. 100.0,
        longitude: int.to_float(i % 777) /. 100.0,
      )
    })
  let encoded = encode5(points)
  let assert Ok(decoded) = polyline.decode(encoded, precision: 5)
  list.length(decoded)
  |> should.equal(100_000)
  list.zip(points, decoded)
  |> list.all(fn(pair) { pair.0 == pair.1 })
  |> should.be_true
}

fn encode5(points: List(LatLng)) -> String {
  let assert Ok(encoded) = polyline.encode(points, precision: 5)
  encoded
}

// --- decoded coordinates out of range ------------------------------------

pub fn decode_rejects_latitude_beyond_pole_test() -> Nil {
  // Each part starts from (0, 0), so joining them adds the deltas: the
  // second point is at latitude 90 + 1.
  let input =
    encode5([geokit.wrap_lat_lng(latitude: 90.0, longitude: 0.0)])
    <> encode5([geokit.wrap_lat_lng(latitude: 1.0, longitude: 0.0)])
  polyline.decode(input, precision: 5)
  |> should.equal(Error(polyline.CoordinateOutOfRange(index: 1)))
}

pub fn decode_rejects_longitude_beyond_antimeridian_test() -> Nil {
  let input =
    encode5([
      geokit.wrap_lat_lng(latitude: 0.0, longitude: 1.0),
      geokit.wrap_lat_lng(latitude: 0.0, longitude: -180.0),
    ])
    <> encode5([geokit.wrap_lat_lng(latitude: 0.0, longitude: -1.0)])
  polyline.decode(input, precision: 5)
  |> should.equal(Error(polyline.CoordinateOutOfRange(index: 2)))
}

// --- Boundaries found by mutation testing ---------------------------------

pub fn precision_1_is_accepted_test() -> Nil {
  let point = geokit.wrap_lat_lng(latitude: 1.0, longitude: 2.0)
  assert polyline.encode([point], precision: 1) == Ok("Sg@")
  assert polyline.decode("CE", precision: 1)
    == Ok([geokit.wrap_lat_lng(latitude: 0.2, longitude: 0.3)])
}
