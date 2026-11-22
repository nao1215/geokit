//// Encoded polylines: a list of positions as a short ASCII string, as
//// described in Google's Encoded Polyline Algorithm Format. Each
//// coordinate is rounded to `precision` decimal digits and stored as the
//// difference from the previous position. Google uses precision 5; some
//// routing services use 6. The same precision must be used to encode and
//// decode.

import gleam/bit_array
import gleam/bool
import gleam/float
import gleam/int
import gleam/list
import gleam/result
import gleam/string

import geokit.{type LatLng}

/// The reason a polyline operation failed.
pub type PolylineError {
  /// The input ended in the middle of a value.
  TruncatedInput
  /// A character outside `?` to `~` (ASCII 63 to 126), or a value longer
  /// than ten chunks. `character` is the grapheme that holds the bad byte
  /// and `position` is its 0-based grapheme index.
  InvalidCharacter(character: String, position: Int)
  /// The precision was outside [1, 11].
  PrecisionOutOfRange(precision: Int)
  /// The decoded position at this 0-based index is outside the latitude
  /// or longitude range.
  CoordinateOutOfRange(index: Int)
}

// --- Encode --------------------------------------------------------------

/// Returns the encoded polyline for `points`, with each coordinate rounded
/// to `precision` decimal digits. `precision` must be in [1, 11]; above
/// 11 the values no longer fit in the integers JavaScript represents
/// exactly.
///
/// ## Examples
///
/// ```gleam
/// [
///   geokit.wrap_lat_lng(latitude: 38.5, longitude: -120.2),
///   geokit.wrap_lat_lng(latitude: 40.7, longitude: -120.95),
///   geokit.wrap_lat_lng(latitude: 43.252, longitude: -126.453),
/// ]
/// |> encode(precision: 5)
/// // -> Ok("_p~iF~ps|U_ulLnnqC_mqNvxq`@")
/// ```
///
/// ```gleam
/// encode([], precision: 12)
/// // -> Error(PrecisionOutOfRange(precision: 12))
/// ```
pub fn encode(
  points: List(LatLng),
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
  encode_loop(
    points: points,
    factor: scale_factor(precision),
    table: string.to_utf_codepoints(output_chars),
    last_lat: 0,
    last_lng: 0,
    acc: [],
  )
}

// `acc` holds the output codepoints in reverse order.
fn encode_loop(
  points points: List(LatLng),
  factor factor: Float,
  table table: List(UtfCodepoint),
  last_lat last_lat: Int,
  last_lng last_lng: Int,
  acc acc: List(UtfCodepoint),
) -> String {
  case points {
    [] -> string.from_utf_codepoints(list.reverse(acc))
    [head, ..tail] -> {
      let lat_scaled = float.round(geokit.latitude(head) *. factor)
      let lng_scaled = float.round(geokit.longitude(head) *. factor)
      let acc =
        encode_signed(value: lat_scaled - last_lat, table: table, acc: acc)
      let acc =
        encode_signed(value: lng_scaled - last_lng, table: table, acc: acc)
      encode_loop(
        points: tail,
        factor: factor,
        table: table,
        last_lat: lat_scaled,
        last_lng: lng_scaled,
        acc: acc,
      )
    }
  }
}

fn encode_signed(
  value value: Int,
  table table: List(UtfCodepoint),
  acc acc: List(UtfCodepoint),
) -> List(UtfCodepoint) {
  let shifted = case value < 0 {
    True -> bit_not_lower(value * 2)
    False -> value * 2
  }
  encode_unsigned(value: shifted, table: table, acc: acc)
}

fn encode_unsigned(
  value value: Int,
  table table: List(UtfCodepoint),
  acc acc: List(UtfCodepoint),
) -> List(UtfCodepoint) {
  case value >= 0x20 {
    True ->
      encode_unsigned(
        value: value / 0x20,
        table: table,
        acc: push_chunk(table: table, chunk: value % 0x20 + 0x20, acc: acc),
      )
    False -> push_chunk(table: table, chunk: value, acc: acc)
  }
}

// Output characters are the 64 ASCII codes 63..126; chunk value `v`
// in 0..63 is the codepoint at offset `v` of `table`.
const output_chars: String =
  "?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"

fn push_chunk(
  table table: List(UtfCodepoint),
  chunk chunk: Int,
  acc acc: List(UtfCodepoint),
) -> List(UtfCodepoint) {
  list.append(list.take(list.drop(table, chunk), 1), acc)
}

// The ZigZag bit-not (`~value`) written as arithmetic: `int.bitwise_not`
// works on 32 bits on JavaScript, and scaled values at high precision
// do not fit in 32 bits.
fn bit_not_lower(value: Int) -> Int {
  -value - 1
}

// --- Decode --------------------------------------------------------------

/// Returns the positions in an encoded polyline. `precision` must be the
/// one used to encode it, in [1, 11]. Returns an error for a malformed
/// string or a position outside the latitude or longitude range.
///
/// ## Examples
///
/// ```gleam
/// decode("_p~iF~ps|U_ulLnnqC_mqNvxq`@", precision: 5)
/// |> result.map(list.map(_, geokit.latitude))
/// // -> Ok([38.5, 40.7, 43.252])
/// ```
///
/// ```gleam
/// decode("_p~iF", precision: 5)
/// // -> Error(TruncatedInput)
/// ```
pub fn decode(
  input: String,
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
  list.reverse(raw_points)
  |> list.index_map(fn(scaled, index) {
    let #(lat_int, lng_int) = scaled
    geokit.lat_lng(
      latitude: int.to_float(lat_int) /. factor,
      longitude: int.to_float(lng_int) /. factor,
    )
    |> result.replace_error(CoordinateOutOfRange(index:))
  })
  |> result.all
}

// The input is walked byte by byte, so `position` is a byte offset.
// `input` is kept so the error path can report the grapheme that holds
// the offending byte and its grapheme index.
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

// Each chunk carries 5 bits. The largest value `encode` produces
// is the ZigZag of 180e11 at precision 11, about 46 bits, which needs
// ten chunks (shifts 0 to 45). A longer run of continuation chunks is
// rejected at the chunk that would start beyond bit 50, so every
// accepted value stays below 2^53 and both targets agree.
const max_shift: Int = 45

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
      Error(invalid_character(input: input, byte_offset: position))
    _ -> Error(TruncatedInput)
  }
}

// --- Helpers -------------------------------------------------------------

// The grapheme of `input` that contains the byte at `byte_offset`, and
// its grapheme index. Only called on the error path, so the walk over
// the graphemes costs nothing on valid input. A combining mark after
// an ASCII character joins it into one grapheme, so the reported
// character is the whole cluster at the cluster's index.
fn invalid_character(
  input input: String,
  byte_offset byte_offset: Int,
) -> PolylineError {
  locate_grapheme(
    graphemes: string.to_graphemes(input),
    byte_offset: byte_offset,
    start: 0,
    index: 0,
  )
}

fn locate_grapheme(
  graphemes graphemes: List(String),
  byte_offset byte_offset: Int,
  start start: Int,
  index index: Int,
) -> PolylineError {
  case graphemes {
    [] -> InvalidCharacter(character: "", position: index)
    [grapheme, ..rest] -> {
      let end = start + string.byte_size(grapheme)
      case byte_offset < end {
        True -> InvalidCharacter(character: grapheme, position: index)
        False ->
          locate_grapheme(
            graphemes: rest,
            byte_offset: byte_offset,
            start: end,
            index: index + 1,
          )
      }
    }
  }
}

fn scale_factor(precision: Int) -> Float {
  list.repeat(10, times: precision)
  |> int.product
  |> int.to_float
}
