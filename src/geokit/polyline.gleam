//// Google Encoded Polyline algorithm.
////
//// Encodes a sequence of `LatLng` points as a compact ASCII string
//// using delta encoding, ZigZag transform, base-32 chunking, and a
//// `+ 0x3F` ASCII offset. Used by the Google Maps Directions API,
//// OSRM, Mapbox Directions, and Valhalla.
////
//// Specification:
//// <https://developers.google.com/maps/documentation/utilities/polylinealgorithmformat>.

import gleam/bool
import gleam/float
import gleam/int
import gleam/list
import gleam/result
import gleam/string

import geokit/latlng.{type LatLng}

/// Errors returned by [`decode`](#decode).
pub type PolylineError {
  /// The input string was malformed — typically a continuation byte
  /// without a corresponding stop byte (high bit set on the last
  /// chunk).
  TruncatedInput
  /// A character outside the printable ASCII range used by the
  /// encoding appeared in the input.
  InvalidCharacter(char: String, position: Int)
}

// --- Encode --------------------------------------------------------------

/// Encode a list of points using the default precision of 5 (1e-5
/// degrees, ~1 m at the equator). This matches Google's original
/// algorithm.
///
/// ```gleam
/// import geokit/polyline
/// import geokit/latlng
///
/// let assert Ok(p1) = latlng.new(lat: 38.5, lng: -120.2)
/// let assert Ok(p2) = latlng.new(lat: 40.7, lng: -120.95)
/// let assert Ok(p3) = latlng.new(lat: 43.252, lng: -126.453)
/// polyline.encode([p1, p2, p3])
/// // == "_p~iF~ps|U_ulLnnqC_mqNvxq`@"
/// ```
pub fn encode(points points: List(LatLng)) -> String {
  encode_with(points: points, precision: 5)
}

/// Encode a list of points with the given precision (number of
/// decimal digits to preserve). Precision 6 is used by Valhalla and
/// the Open Source Routing Machine for higher accuracy.
pub fn encode_with(
  points points: List(LatLng),
  precision precision: Int,
) -> String {
  let factor = pow10(precision)
  encode_loop(points: points, factor: factor, last_lat: 0, last_lng: 0, acc: "")
}

fn encode_loop(
  points points: List(LatLng),
  factor factor: Int,
  last_lat last_lat: Int,
  last_lng last_lng: Int,
  acc acc: String,
) -> String {
  case points {
    [] -> acc
    [head, ..tail] -> {
      let lat_scaled = round_to_int(latlng.lat(head) *. int_to_float(factor))
      let lng_scaled = round_to_int(latlng.lng(head) *. int_to_float(factor))
      let lat_delta = lat_scaled - last_lat
      let lng_delta = lng_scaled - last_lng
      encode_loop(
        points: tail,
        factor: factor,
        last_lat: lat_scaled,
        last_lng: lng_scaled,
        acc: acc <> encode_signed(lat_delta) <> encode_signed(lng_delta),
      )
    }
  }
}

fn encode_signed(value: Int) -> String {
  let shifted = case value < 0 {
    True -> bit_not_lower(value * 2)
    False -> value * 2
  }
  encode_unsigned(shifted, "")
}

fn encode_unsigned(value: Int, acc: String) -> String {
  case value >= 0x20 {
    True -> {
      let chunk = value % 0x20 + 0x20 + 63
      encode_unsigned(value / 0x20, acc <> int_codepoint_to_string(chunk))
    }
    False -> acc <> int_codepoint_to_string(value + 63)
  }
}

// ZigZag bit-not on the low 32 bits, which the spec calls for. We
// reproduce the effect with arithmetic since Gleam Int has no
// dedicated bitwise-not.
fn bit_not_lower(value: Int) -> Int {
  -value - 1
}

// --- Decode --------------------------------------------------------------

/// Decode a polyline string with the default precision (5).
///
/// ```gleam
/// import geokit/polyline
///
/// let assert Ok(points) = polyline.decode("_p~iF~ps|U_ulLnnqC_mqNvxq`@")
/// // points == [(38.5, -120.2), (40.7, -120.95), (43.252, -126.453)]
/// ```
pub fn decode(input input: String) -> Result(List(LatLng), PolylineError) {
  decode_with(input: input, precision: 5)
}

/// Decode a polyline string with the given precision. Must match the
/// precision used at encode time.
pub fn decode_with(
  input input: String,
  precision precision: Int,
) -> Result(List(LatLng), PolylineError) {
  let factor = pow10(precision)
  use #(raw_points, _) <- result.try(
    decode_loop(
      chars: string.to_graphemes(input),
      position: 0,
      last_lat: 0,
      last_lng: 0,
      acc: [],
    ),
  )
  Ok(
    raw_points
    |> list.reverse
    |> list.map(fn(scaled) {
      let #(lat_int, lng_int) = scaled
      let lat = int_to_float(lat_int) /. int_to_float(factor)
      let lng = int_to_float(lng_int) /. int_to_float(factor)
      latlng.wrap(lat: lat, lng: lng)
    }),
  )
}

fn decode_loop(
  chars chars: List(String),
  position position: Int,
  last_lat last_lat: Int,
  last_lng last_lng: Int,
  acc acc: List(#(Int, Int)),
) -> Result(#(List(#(Int, Int)), Int), PolylineError) {
  case chars {
    [] -> Ok(#(acc, position))
    _ -> {
      use #(lat_delta, after_lat_chars, after_lat_pos) <- result.try(
        decode_signed(chars: chars, position: position),
      )
      use #(lng_delta, after_lng_chars, after_lng_pos) <- result.try(
        decode_signed(chars: after_lat_chars, position: after_lat_pos),
      )
      let new_lat = last_lat + lat_delta
      let new_lng = last_lng + lng_delta
      decode_loop(
        chars: after_lng_chars,
        position: after_lng_pos,
        last_lat: new_lat,
        last_lng: new_lng,
        acc: [#(new_lat, new_lng), ..acc],
      )
    }
  }
}

fn decode_signed(
  chars chars: List(String),
  position position: Int,
) -> Result(#(Int, List(String), Int), PolylineError) {
  use #(value, rest, after_pos) <- result.try(decode_unsigned(
    chars: chars,
    position: position,
    shift: 0,
    acc: 0,
  ))
  let signed = case value % 2 {
    0 -> value / 2
    _ -> bit_not_lower(value / 2)
  }
  Ok(#(signed, rest, after_pos))
}

fn decode_unsigned(
  chars chars: List(String),
  position position: Int,
  shift shift: Int,
  acc acc: Int,
) -> Result(#(Int, List(String), Int), PolylineError) {
  case chars {
    [] -> Error(TruncatedInput)
    [head, ..tail] -> {
      use code <- result.try(grapheme_codepoint(
        grapheme: head,
        position: position,
      ))
      use <- bool.guard(
        when: code < 63,
        return: Error(InvalidCharacter(char: head, position: position)),
      )
      let value = code - 63
      let chunk = case value < 0x20 {
        True -> value
        False -> value - 0x20
      }
      let new_acc = acc + chunk * pow_of_two(shift)
      case value < 0x20 {
        True -> Ok(#(new_acc, tail, position + 1))
        False ->
          decode_unsigned(
            chars: tail,
            position: position + 1,
            shift: shift + 5,
            acc: new_acc,
          )
      }
    }
  }
}

// --- Helpers -------------------------------------------------------------

fn pow10(exponent: Int) -> Int {
  use <- bool.guard(when: exponent <= 0, return: 1)
  10 * pow10(exponent - 1)
}

fn pow_of_two(exponent: Int) -> Int {
  use <- bool.guard(when: exponent <= 0, return: 1)
  2 * pow_of_two(exponent - 1)
}

fn round_to_int(value: Float) -> Int {
  use <- bool.guard(when: value <. 0.0, return: -float.round(0.0 -. value))
  float.round(value)
}

fn int_to_float(value: Int) -> Float {
  int.to_float(value)
}

// We pass codepoints around as Ints so the bit / shift / mod
// arithmetic stays in one place. `grapheme_codepoint` extracts the
// raw codepoint of an ASCII grapheme; non-ASCII inputs return
// `InvalidCharacter`.
fn grapheme_codepoint(
  grapheme grapheme: String,
  position position: Int,
) -> Result(Int, PolylineError) {
  case string.to_utf_codepoints(grapheme) {
    [code] -> {
      let value = string.utf_codepoint_to_int(code)
      use <- bool.guard(
        when: value > 127,
        return: Error(InvalidCharacter(char: grapheme, position: position)),
      )
      Ok(value)
    }
    _ -> Error(InvalidCharacter(char: grapheme, position: position))
  }
}

fn int_codepoint_to_string(value: Int) -> String {
  case string.utf_codepoint(value) {
    Ok(code) -> string.from_utf_codepoints([code])
    Error(Nil) -> ""
  }
}
