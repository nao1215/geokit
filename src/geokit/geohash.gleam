//// Niemeyer geohash encoding and decoding.
////
//// A geohash is a short alphanumeric string identifying a
//// rectangular cell on the Earth's surface. Longer hashes pinpoint
//// smaller cells. The alphabet is base32 (10 digits + 22 letters,
//// omitting `a`, `i`, `l`, `o` to avoid visual ambiguity); each
//// character contributes 5 bits, alternating between longitude and
//// latitude.
////
//// See <http://geohash.org/> for the original specification.

import gleam/bool
import gleam/list
import gleam/result
import gleam/string

import geokit.{type LatLng}

const base32_alphabet: String = "0123456789bcdefghjkmnpqrstuvwxyz"

/// Errors returned by [`encode`](#encode), [`decode`](#decode),
/// [`decode_bounds`](#decode_bounds), and [`neighbor`](#neighbor).
pub type GeohashError {
  /// [`encode`](#encode) was called with `precision` outside the
  /// supported range `[1, 12]`.
  PrecisionOutOfRange(precision: Int)
  /// [`decode`](#decode) was called with an empty string.
  EmptyHash
  /// A character outside the base32 alphabet appeared in a hash
  /// passed to [`decode`](#decode).
  InvalidCharacter(char: String, position: Int)
}

/// Compass direction used by [`neighbor`](#neighbor).
pub type Direction {
  North
  South
  East
  West
  NorthEast
  NorthWest
  SouthEast
  SouthWest
}

/// The eight neighbours of a geohash cell. See [`neighbors`](#neighbors).
pub type Neighbors {
  Neighbors(
    north: String,
    south: String,
    east: String,
    west: String,
    north_east: String,
    north_west: String,
    south_east: String,
    south_west: String,
  )
}

// --- Encode --------------------------------------------------------------

/// Encode a [`LatLng`](../latlng.html#LatLng) as a base32 geohash of
/// the requested precision. Precision is the number of output
/// characters and must be in `[1, 12]`. Each additional character
/// shrinks the cell width by a factor of ~5.6.
///
/// Midpoint inputs (the equator, the poles, the prime / anti
/// meridian, and other coordinates that land exactly on a recursive
/// bisection midpoint) follow the canonical Wikipedia / `ngeohash` /
/// `pygeohash` / `geohash.org` convention: `coordinate >= midpoint`
/// places the bit in the upper half. This makes geokit-emitted
/// hashes byte-compatible with every other geohash implementation.
///
/// ```gleam
/// import geokit/geohash
/// import geokit/latlng
///
/// let assert Ok(tokyo) = geokit.lat_lng(latitude: 35.6812, longitude: 139.7671)
/// let assert Ok(hash) = geohash.encode(point: tokyo, precision: 8)
/// // hash == "xn76urx4"
/// ```
pub fn encode(
  point point: LatLng,
  precision precision: Int,
) -> Result(String, GeohashError) {
  use <- bool.guard(
    when: precision < 1 || precision > 12,
    return: Error(PrecisionOutOfRange(precision: precision)),
  )
  let bits =
    encode_bits(
      current: #(geokit.longitude(point), #(-180.0, 180.0)),
      other: #(geokit.latitude(point), #(-90.0, 90.0)),
      remaining: precision * 5,
      acc: [],
    )
  Ok(bits_to_base32(list.reverse(bits), ""))
}

// Bits alternate between the axes, longitude first: each step bisects
// `current` (a coordinate and its interval) and then swaps the axes.
fn encode_bits(
  current current: #(Float, #(Float, Float)),
  other other: #(Float, #(Float, Float)),
  remaining remaining: Int,
  acc acc: List(Int),
) -> List(Int) {
  case remaining {
    0 -> acc
    _ -> {
      let #(value, #(min, max)) = current
      // The midpoint belongs to the upper half.
      let bit = case value >=. { min +. max } /. 2.0 {
        True -> 1
        False -> 0
      }
      encode_bits(
        current: other,
        other: #(value, halve(bit: bit, range: #(min, max))),
        remaining: remaining - 1,
        acc: [bit, ..acc],
      )
    }
  }
}

// The upper half of `range` for bit 1, the lower half for bit 0.
fn halve(bit bit: Int, range range: #(Float, Float)) -> #(Float, Float) {
  let #(min, max) = range
  let mid = { min +. max } /. 2.0
  case bit {
    1 -> #(mid, max)
    _ -> #(min, mid)
  }
}

fn bits_to_base32(bits: List(Int), acc: String) -> String {
  case bits {
    [b0, b1, b2, b3, b4, ..rest] -> {
      let value = b0 * 16 + b1 * 8 + b2 * 4 + b3 * 2 + b4
      bits_to_base32(rest, acc <> string.slice(base32_alphabet, value, 1))
    }
    _ -> acc
  }
}

// --- Decode --------------------------------------------------------------

/// Decode a geohash to the centre of the cell it identifies.
///
/// The input is case-insensitive: upper-case characters are folded
/// to lower-case before lookup.
///
/// ```gleam
/// import geokit/geohash
///
/// let assert Ok(centre) = geohash.decode("xn76urx4")
/// // centre ≈ (35.6812, 139.7671)
/// ```
pub fn decode(hash hash: String) -> Result(LatLng, GeohashError) {
  use #(sw, ne) <- result.try(decode_bounds(hash: hash))
  let lat = { geokit.latitude(sw) +. geokit.latitude(ne) } /. 2.0
  let lng = { geokit.longitude(sw) +. geokit.longitude(ne) } /. 2.0
  Ok(geokit.wrap_lat_lng(latitude: lat, longitude: lng))
}

/// Decode a geohash to the south-west and north-east corners of its
/// cell, returned as a tuple `#(sw, ne)`.
///
/// The input is case-insensitive: upper-case characters are folded to
/// lower-case before lookup. This matches `chrisveness/latlon-geohash`
/// and `ngeohash`.
pub fn decode_bounds(
  hash hash: String,
) -> Result(#(LatLng, LatLng), GeohashError) {
  let normalised = string.lowercase(hash)
  use <- bool.guard(when: normalised == "", return: Error(EmptyHash))
  use bits <- result.try(hash_to_bits(hash: normalised, position: 0, acc: []))
  let #(last_axis, other_axis) =
    decode_bits(bits: list.reverse(bits), current: #(-180.0, 180.0), other: #(
      -90.0,
      90.0,
    ))
  // Each character is 5 bits, so an even-length hash has an even number
  // of bits and the axes end where they started (longitude current).
  let #(#(lng_min, lng_max), #(lat_min, lat_max)) = case
    string.length(normalised) % 2
  {
    0 -> #(last_axis, other_axis)
    _ -> #(other_axis, last_axis)
  }
  Ok(#(
    geokit.wrap_lat_lng(latitude: lat_min, longitude: lng_min),
    geokit.wrap_lat_lng(latitude: lat_max, longitude: lng_max),
  ))
}

fn hash_to_bits(
  hash hash: String,
  position position: Int,
  acc acc: List(Int),
) -> Result(List(Int), GeohashError) {
  case string.pop_grapheme(hash) {
    Error(Nil) -> Ok(acc)
    Ok(#(head, tail)) ->
      case index_of(char: head, table: base32_alphabet) {
        Error(Nil) -> Error(InvalidCharacter(char: head, position: position))
        Ok(value) ->
          hash_to_bits(hash: tail, position: position + 1, acc: [
            value % 2,
            value / 2 % 2,
            value / 4 % 2,
            value / 8 % 2,
            value / 16 % 2,
            ..acc
          ])
      }
  }
}

// The decoding counterpart of `encode_bits`: each bit halves the
// interval of `current`, then the axes swap.
fn decode_bits(
  bits bits: List(Int),
  current current: #(Float, Float),
  other other: #(Float, Float),
) -> #(#(Float, Float), #(Float, Float)) {
  case bits {
    [] -> #(current, other)
    [bit, ..rest] ->
      decode_bits(
        bits: rest,
        current: other,
        other: halve(bit: bit, range: current),
      )
  }
}

// Position of the single character `char` in `table`.
fn index_of(char char: String, table table: String) -> Result(Int, Nil) {
  use #(before, _) <- result.map(string.split_once(table, char))
  string.length(before)
}

// --- Neighbours ----------------------------------------------------------

/// The neighbour of `hash` in the given [`Direction`](#Direction).
///
/// Returns [`EmptyHash`](#GeohashError) when called on the empty
/// string. Wraps across the antimeridian for east / west, returns
/// [`EmptyHash`](#GeohashError) when a polar neighbour would cross
/// the pole (north of the northernmost row or south of the
/// southernmost row).
///
/// The input is case-insensitive: upper-case characters are folded
/// to lower-case before lookup, matching `chrisveness/latlon-geohash`
/// and `ngeohash`.
pub fn neighbor(
  hash hash: String,
  direction direction: Direction,
) -> Result(String, GeohashError) {
  let normalised = string.lowercase(hash)
  use _ <- result.try(hash_to_bits(hash: normalised, position: 0, acc: []))
  case direction {
    North -> step(hash: normalised, toward: ToNorth)
    South -> step(hash: normalised, toward: ToSouth)
    East -> step(hash: normalised, toward: ToEast)
    West -> step(hash: normalised, toward: ToWest)
    NorthEast -> two_steps(hash: normalised, first: ToNorth, second: ToEast)
    NorthWest -> two_steps(hash: normalised, first: ToNorth, second: ToWest)
    SouthEast -> two_steps(hash: normalised, first: ToSouth, second: ToEast)
    SouthWest -> two_steps(hash: normalised, first: ToSouth, second: ToWest)
  }
}

/// All eight neighbours of `hash`, returned as a
/// [`Neighbors`](#Neighbors) record.
pub fn neighbors(hash hash: String) -> Result(Neighbors, GeohashError) {
  use n <- result.try(neighbor(hash: hash, direction: North))
  use s <- result.try(neighbor(hash: hash, direction: South))
  use e <- result.try(neighbor(hash: hash, direction: East))
  use w <- result.try(neighbor(hash: hash, direction: West))
  use ne <- result.try(neighbor(hash: hash, direction: NorthEast))
  use nw <- result.try(neighbor(hash: hash, direction: NorthWest))
  use se <- result.try(neighbor(hash: hash, direction: SouthEast))
  use sw <- result.try(neighbor(hash: hash, direction: SouthWest))
  Ok(Neighbors(
    north: n,
    south: s,
    east: e,
    west: w,
    north_east: ne,
    north_west: nw,
    south_east: se,
    south_west: sw,
  ))
}

// The four directions the adjacency tables cover. Diagonals are two
// steps.
type Cardinal {
  ToNorth
  ToSouth
  ToEast
  ToWest
}

fn two_steps(
  hash hash: String,
  first first: Cardinal,
  second second: Cardinal,
) -> Result(String, GeohashError) {
  use partial <- result.try(step(hash: hash, toward: first))
  step(hash: partial, toward: second)
}

// `hash` is lower-case and every character is in the alphabet.
fn step(
  hash hash: String,
  toward toward: Cardinal,
) -> Result(String, GeohashError) {
  case string.last(hash) {
    Error(Nil) -> Error(EmptyHash)
    Ok(last) -> {
      let parent = string.drop_end(hash, 1)
      // Per the Niemeyer adjacency algorithm the lookup table is keyed
      // by `length % 2`: an even-length hash uses the "even" tables,
      // an odd one the "odd" tables.
      let #(lookup, border) =
        tables(toward: toward, is_even: string.length(hash) % 2 == 0)
      use new_parent <- result.try(case string.contains(border, last), parent {
        False, _ -> Ok(parent)
        // Crossing the antimeridian: the top-level cell wraps around,
        // so the last character is looked up in the table as is.
        True, "" if toward == ToEast || toward == ToWest -> Ok("")
        // Crossing a pole has no neighbour.
        True, "" -> Error(EmptyHash)
        True, _ -> step(hash: parent, toward: toward)
      })
      // The Niemeyer adjacency tables are keyed *by position within
      // the neighbour string*: find the position of `last` in the
      // neighbour table, and that position indexes the base32
      // alphabet to give the new character. (Not: find the base32
      // index of `last`, look up that position in the neighbour table
      // — which is the easy mistake.)
      case index_of(char: last, table: lookup) {
        Error(Nil) ->
          Error(InvalidCharacter(char: last, position: string.length(parent)))
        Ok(value) -> Ok(new_parent <> string.slice(base32_alphabet, value, 1))
      }
    }
  }
}

// Adjacency tables (Niemeyer): `#(neighbour, border)` for a direction
// and the parity of the hash length. `border` lists the characters
// that, as the last character of a hash, lie on the edge of the parent
// cell in that direction; the neighbour is then computed from the
// parent's neighbour.
fn tables(toward toward: Cardinal, is_even is_even: Bool) -> #(String, String) {
  case toward, is_even {
    ToNorth, True -> #("p0r21436x8zb9dcf5h7kjnmqesgutwvy", "prxz")
    ToNorth, False -> #("bc01fg45238967deuvhjyznpkmstqrwx", "bcfguvyz")
    ToEast, True -> #("bc01fg45238967deuvhjyznpkmstqrwx", "bcfguvyz")
    ToEast, False -> #("p0r21436x8zb9dcf5h7kjnmqesgutwvy", "prxz")
    ToSouth, True -> #("14365h7k9dcfesgujnmqp0r2twvyx8zb", "028b")
    ToSouth, False -> #("238967debc01fg45kmstqrwxuvhjyznp", "0145hjnp")
    ToWest, True -> #("238967debc01fg45kmstqrwxuvhjyznp", "0145hjnp")
    ToWest, False -> #("14365h7k9dcfesgujnmqp0r2twvyx8zb", "028b")
  }
}
