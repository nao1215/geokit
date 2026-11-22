import gleam/int
import gleam/list
import gleam/string
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
  let assert Ok(encoded) = polyline.encode_with(points: [a, b], precision: 6)
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

// --- precision validation (regression for #10) ---------------------------

pub fn encode_with_rejects_zero_precision_test() -> Nil {
  let assert Ok(p) = latlng.new(lat: 35.0, lng: 139.0)
  case polyline.encode_with(points: [p], precision: 0) {
    Error(polyline.PrecisionOutOfRange(precision: 0)) -> Nil
    _ -> should.be_true(False)
  }
}

pub fn encode_with_rejects_negative_precision_test() -> Nil {
  let assert Ok(p) = latlng.new(lat: 35.0, lng: 139.0)
  case polyline.encode_with(points: [p], precision: -1) {
    Error(polyline.PrecisionOutOfRange(precision: -1)) -> Nil
    _ -> should.be_true(False)
  }
}

pub fn encode_with_rejects_too_large_precision_test() -> Nil {
  let assert Ok(p) = latlng.new(lat: 35.0, lng: 139.0)
  case polyline.encode_with(points: [p], precision: 12) {
    Error(polyline.PrecisionOutOfRange(precision: 12)) -> Nil
    _ -> should.be_true(False)
  }
}

pub fn encode_with_accepts_max_precision_11_test() -> Nil {
  let assert Ok(p) = latlng.new(lat: 35.0, lng: 139.0)
  let assert Ok(_) = polyline.encode_with(points: [p], precision: 11)
  Nil
}

pub fn decode_with_rejects_zero_precision_test() -> Nil {
  case polyline.decode_with(input: "_p~iF~ps|U", precision: 0) {
    Error(polyline.PrecisionOutOfRange(precision: 0)) -> Nil
    _ -> should.be_true(False)
  }
}

pub fn decode_with_rejects_negative_precision_test() -> Nil {
  case polyline.decode_with(input: "_p~iF~ps|U", precision: -1) {
    Error(polyline.PrecisionOutOfRange(precision: -1)) -> Nil
    _ -> should.be_true(False)
  }
}

pub fn decode_with_rejects_too_large_precision_test() -> Nil {
  case polyline.decode_with(input: "_p~iF~ps|U", precision: 12) {
    Error(polyline.PrecisionOutOfRange(precision: 12)) -> Nil
    _ -> should.be_true(False)
  }
}

// --- character range and chunk limits -----------------------------------

pub fn decode_rejects_del_test() -> Nil {
  // Valid polyline characters are 63..126; DEL (127) is outside.
  polyline.decode(input: "??\u{7F}?")
  |> should.equal(Error(polyline.InvalidCharacter(char: "\u{7F}", position: 2)))
}

pub fn decode_rejects_non_ascii_test() -> Nil {
  polyline.decode(input: "??é?")
  |> should.equal(Error(polyline.InvalidCharacter(char: "é", position: 2)))
}

pub fn decode_rejects_chunk_beyond_ten_test() -> Nil {
  // Ten chunks cover the largest value precision 11 produces (shifts
  // 0..45); an eleventh continuation chunk is outside the format.
  polyline.decode(input: "__________?")
  |> should.equal(Error(polyline.InvalidCharacter(char: "?", position: 10)))
  polyline.decode(input: string.repeat("_", 40) <> "??")
  |> should.equal(Error(polyline.InvalidCharacter(char: "_", position: 10)))
}

pub fn decode_accepts_ten_chunks_test() -> Nil {
  // Nine continuation chunks and a stop chunk: the largest legal width.
  let assert Ok(_) = polyline.decode(input: "_________??")
  Nil
}

pub fn decode_reports_grapheme_with_combining_mark_test() -> Nil {
  // "?" followed by a combining acute accent is one grapheme; the
  // invalid byte belongs to it, so it is reported at grapheme 0.
  polyline.decode(input: "?\u{0301}")
  |> should.equal(
    Error(polyline.InvalidCharacter(char: "?\u{0301}", position: 0)),
  )
  polyline.decode(input: "??e\u{0301}?")
  |> should.equal(
    Error(polyline.InvalidCharacter(char: "e\u{0301}", position: 2)),
  )
}

pub fn decode_reports_grapheme_index_after_cap_test() -> Nil {
  // The chunk that exceeds the width cap carries a combining mark.
  polyline.decode(input: "__________?\u{0301}")
  |> should.equal(
    Error(polyline.InvalidCharacter(char: "?\u{0301}", position: 10)),
  )
}

// --- extreme coordinates at high precision -------------------------------

fn round_trip_extremes(precision: Int) -> Nil {
  let points = [
    latlng.new_or_panic(lat: 0.0, lng: 180.0),
    latlng.new_or_panic(lat: 0.0, lng: -180.0),
    latlng.new_or_panic(lat: 90.0, lng: 180.0),
    latlng.new_or_panic(lat: -90.0, lng: -180.0),
    latlng.new_or_panic(lat: 90.0, lng: 0.0),
    latlng.new_or_panic(lat: -90.0, lng: 0.0),
  ]
  let assert Ok(encoded) =
    polyline.encode_with(points: points, precision: precision)
  let assert Ok(decoded) =
    polyline.decode_with(input: encoded, precision: precision)
  list.length(decoded)
  |> should.equal(list.length(points))
  list.zip(points, decoded)
  |> list.each(fn(pair) {
    let #(expected, actual) = pair
    approx_equal(latlng.lat(actual), latlng.lat(expected), 1.0e-9)
    |> should.be_true
    approx_equal(latlng.lng(actual), latlng.lng(expected), 1.0e-9)
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
  let points = [latlng.new_or_panic(lat: 0.0, lng: 180.0)]
  let assert Ok(encoded) = polyline.encode_with(points: points, precision: 8)
  polyline.decode_with(input: encoded, precision: 8)
  |> should.equal(Ok(points))
}

// --- long inputs --------------------------------------------------------

pub fn decode_long_polyline_test() -> Nil {
  // 100_000 points must decode without exhausting the stack on either
  // target.
  let points =
    list.repeat(Nil, times: 100_000)
    |> list.index_map(fn(_, i) {
      latlng.wrap(
        lat: int.to_float(i % 1000) /. 100.0,
        lng: int.to_float(i % 777) /. 100.0,
      )
    })
  let encoded = polyline.encode(points: points)
  let assert Ok(decoded) = polyline.decode(input: encoded)
  list.length(decoded)
  |> should.equal(100_000)
  list.zip(points, decoded)
  |> list.all(fn(pair) { latlng.equal(pair.0, pair.1) })
  |> should.be_true
}
