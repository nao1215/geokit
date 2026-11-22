//// Google Encoded Polyline algorithm.
////
//// Encodes a sequence of `LatLng` points as a compact ASCII string
//// using delta encoding, ZigZag transform, base-32 chunking, and a
//// `+ 0x3F` ASCII offset. Used by the Google Maps Directions API,
//// OSRM, Mapbox Directions, and Valhalla.
////
//// Specification:
//// <https://developers.google.com/maps/documentation/utilities/polylinealgorithmformat>.

import gleam/bit_array
import gleam/bool
import gleam/float
import gleam/int
import gleam/list
import gleam/result
import gleam/string

import geokit/latlng.{type LatLng}

/// Errors returned by [`encode_with`](#encode_with), [`decode`](#decode),
/// and [`decode_with`](#decode_with).
pub type PolylineError {
  /// The input string was malformed — typically a continuation byte
  /// without a corresponding stop byte (high bit set on the last
  /// chunk).
  TruncatedInput
  /// A character outside the printable ASCII range used by the
  /// encoding appeared in the input.
  InvalidCharacter(char: String, position: Int)
  /// `precision` was outside the supported range `[1, 11]`. The
  /// Google reference encoding uses 5; Valhalla and OSRM use 6.
  /// Precisions above 11 overflow the safe integer range on the
  /// JavaScript target.
  PrecisionOutOfRange(precision: Int)
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
  // Precision 5 is statically valid, so we bypass the precision
  // check that `encode_with` enforces at runtime and call the
  // internal encoder directly.
  encode_unchecked(points: points, precision: 5)
}

/// Encode a list of points with the given precision (number of
/// decimal digits to preserve). `precision` must be in `[1, 11]`;
/// precision 6 is used by Valhalla and the Open Source Routing
/// Machine for higher accuracy than the Google default of 5.
pub fn encode_with(
  points points: List(LatLng),
  precision precision: Int,
) -> Result(String, PolylineError) {
  use <- bool.guard(
    when: precision < 1 || precision > 11,
    return: Error(PrecisionOutOfRange(precision: precision)),
  )
  Ok(encode_unchecked(points: points, precision: precision))
}

fn encode_unchecked(
  points points: List(LatLng),
  precision precision: Int,
) -> String {
  let factor = scale_factor(precision)
  encode_loop(points: points, factor: factor, last_lat: 0, last_lng: 0, acc: "")
}

fn encode_loop(
  points points: List(LatLng),
  factor factor: Float,
  last_lat last_lat: Int,
  last_lng last_lng: Int,
  acc acc: String,
) -> String {
  case points {
    [] -> acc
    [head, ..tail] -> {
      let lat_scaled = round_to_int(latlng.lat(head) *. factor)
      let lng_scaled = round_to_int(latlng.lng(head) *. factor)
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
/// precision used at encode time. `precision` must be in `[1, 11]`,
/// matching [`encode_with`](#encode_with).
pub fn decode_with(
  input input: String,
  precision precision: Int,
) -> Result(List(LatLng), PolylineError) {
  use <- bool.guard(
    when: precision < 1 || precision > 11,
    return: Error(PrecisionOutOfRange(precision: precision)),
  )
  let factor = scale_factor(precision)
  use raw_points <- result.try(
    decode_loop(
      input: input,
      bytes: bit_array.from_string(input),
      position: 0,
      last_lat: 0,
      last_lng: 0,
      acc: [],
    ),
  )
  Ok(
    list.reverse(raw_points)
    |> list.map(fn(scaled) {
      let #(lat_int, lng_int) = scaled
      let lat = int.to_float(lat_int) /. factor
      let lng = int.to_float(lng_int) /. factor
      latlng.wrap(lat: lat, lng: lng)
    }),
  )
}

// The input is walked byte by byte. Every valid character is ASCII, so
// up to the first invalid byte the byte offset equals the grapheme
// position reported in `InvalidCharacter`; `input` is kept to slice
// out the offending grapheme.
fn decode_loop(
  input input: String,
  bytes bytes: BitArray,
  position position: Int,
  last_lat last_lat: Int,
  last_lng last_lng: Int,
  acc acc: List(#(Int, Int)),
) -> Result(List(#(Int, Int)), PolylineError) {
  case bytes {
    <<>> -> Ok(acc)
    _ ->
      case decode_pair(input: input, bytes: bytes, position: position) {
        Error(error) -> Error(error)
        Ok(#(lat_delta, lng_delta, rest, after)) -> {
          let new_lat = last_lat + lat_delta
          let new_lng = last_lng + lng_delta
          decode_loop(
            input: input,
            bytes: rest,
            position: after,
            last_lat: new_lat,
            last_lng: new_lng,
            acc: [#(new_lat, new_lng), ..acc],
          )
        }
      }
  }
}

fn decode_pair(
  input input: String,
  bytes bytes: BitArray,
  position position: Int,
) -> Result(#(Int, Int, BitArray, Int), PolylineError) {
  use #(lat_delta, after_lat_bytes, after_lat) <- result.try(decode_signed(
    input: input,
    bytes: bytes,
    position: position,
  ))
  use #(lng_delta, rest, after_lng) <- result.try(decode_signed(
    input: input,
    bytes: after_lat_bytes,
    position: after_lat,
  ))
  Ok(#(lat_delta, lng_delta, rest, after_lng))
}

fn decode_signed(
  input input: String,
  bytes bytes: BitArray,
  position position: Int,
) -> Result(#(Int, BitArray, Int), PolylineError) {
  use #(value, rest, after_pos) <- result.try(decode_unsigned(
    input: input,
    bytes: bytes,
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

// Each chunk carries 5 bits. A 32-bit value needs at most seven chunks
// (shifts 0 to 30); a longer run of continuation chunks is rejected at
// the chunk that would start beyond bit 32, so both targets agree even
// on inputs that would exceed the JavaScript safe-integer range.
const max_shift: Int = 30

fn decode_unsigned(
  input input: String,
  bytes bytes: BitArray,
  position position: Int,
  shift shift: Int,
  acc acc: Int,
) -> Result(#(Int, BitArray, Int), PolylineError) {
  case bytes {
    <<code, rest:bytes>> if code >= 63 && code <= 126 && shift <= max_shift -> {
      let value = code - 63
      case value < 0x20 {
        True ->
          Ok(#(acc + int.bitwise_shift_left(value, shift), rest, position + 1))
        False ->
          decode_unsigned(
            input: input,
            bytes: rest,
            position: position + 1,
            shift: shift + 5,
            acc: acc + int.bitwise_shift_left(value - 0x20, shift),
          )
      }
    }
    <<_, _:bytes>> ->
      Error(InvalidCharacter(
        char: string.slice(input, position, 1),
        position: position,
      ))
    _ -> Error(TruncatedInput)
  }
}

// --- Helpers -------------------------------------------------------------

fn scale_factor(precision: Int) -> Float {
  list.repeat(10, times: precision)
  |> int.product
  |> int.to_float
}

fn round_to_int(value: Float) -> Int {
  use <- bool.guard(when: value <. 0.0, return: -float.round(0.0 -. value))
  float.round(value)
}

fn int_codepoint_to_string(value: Int) -> String {
  case string.utf_codepoint(value) {
    Ok(code) -> string.from_utf_codepoints([code])
    Error(Nil) -> ""
  }
}
