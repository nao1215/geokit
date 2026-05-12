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

import geokit/latlng.{type LatLng}

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
/// ```gleam
/// import geokit/geohash
/// import geokit/latlng
///
/// let assert Ok(tokyo) = latlng.new(lat: 35.6812, lng: 139.7671)
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
  let target_bits = precision * 5
  let bits =
    encode_bits(
      lat_min: -90.0,
      lat_max: 90.0,
      lng_min: -180.0,
      lng_max: 180.0,
      lat: latlng.lat(point),
      lng: latlng.lng(point),
      remaining: target_bits,
      use_lng: True,
      acc: [],
    )
  Ok(bits_to_base32(list.reverse(bits), ""))
}

fn encode_bits(
  lat_min lat_min: Float,
  lat_max lat_max: Float,
  lng_min lng_min: Float,
  lng_max lng_max: Float,
  lat lat: Float,
  lng lng: Float,
  remaining remaining: Int,
  use_lng use_lng: Bool,
  acc acc: List(Int),
) -> List(Int) {
  use <- bool.guard(when: remaining <= 0, return: acc)
  case use_lng {
    True -> {
      let mid = { lng_min +. lng_max } /. 2.0
      let go_high = lng >. mid
      let new_min = case go_high {
        True -> mid
        False -> lng_min
      }
      let new_max = case go_high {
        True -> lng_max
        False -> mid
      }
      let bit = case go_high {
        True -> 1
        False -> 0
      }
      encode_bits(
        lat_min: lat_min,
        lat_max: lat_max,
        lng_min: new_min,
        lng_max: new_max,
        lat: lat,
        lng: lng,
        remaining: remaining - 1,
        use_lng: False,
        acc: [bit, ..acc],
      )
    }
    False -> {
      let mid = { lat_min +. lat_max } /. 2.0
      let go_high = lat >. mid
      let new_min = case go_high {
        True -> mid
        False -> lat_min
      }
      let new_max = case go_high {
        True -> lat_max
        False -> mid
      }
      let bit = case go_high {
        True -> 1
        False -> 0
      }
      encode_bits(
        lat_min: new_min,
        lat_max: new_max,
        lng_min: lng_min,
        lng_max: lng_max,
        lat: lat,
        lng: lng,
        remaining: remaining - 1,
        use_lng: True,
        acc: [bit, ..acc],
      )
    }
  }
}

fn bits_to_base32(bits: List(Int), acc: String) -> String {
  case bits {
    [b0, b1, b2, b3, b4, ..rest] -> {
      let value = b0 * 16 + b1 * 8 + b2 * 4 + b3 * 2 + b4
      let char = case string.slice(base32_alphabet, value, 1) {
        "" -> "0"
        ch -> ch
      }
      bits_to_base32(rest, acc <> char)
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
  let lat = { latlng.lat(sw) +. latlng.lat(ne) } /. 2.0
  let lng = { latlng.lng(sw) +. latlng.lng(ne) } /. 2.0
  Ok(latlng.wrap(lat: lat, lng: lng))
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
  let #(lat_min, lat_max, lng_min, lng_max) =
    decode_bits(
      bits: list.reverse(bits),
      lat_min: -90.0,
      lat_max: 90.0,
      lng_min: -180.0,
      lng_max: 180.0,
      use_lng: True,
    )
  Ok(#(
    latlng.wrap(lat: lat_min, lng: lng_min),
    latlng.wrap(lat: lat_max, lng: lng_max),
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
      case index_in_alphabet(char: head) {
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

fn decode_bits(
  bits bits: List(Int),
  lat_min lat_min: Float,
  lat_max lat_max: Float,
  lng_min lng_min: Float,
  lng_max lng_max: Float,
  use_lng use_lng: Bool,
) -> #(Float, Float, Float, Float) {
  case bits {
    [] -> #(lat_min, lat_max, lng_min, lng_max)
    [bit, ..rest] ->
      case use_lng {
        True -> {
          let mid = { lng_min +. lng_max } /. 2.0
          case bit {
            1 ->
              decode_bits(
                bits: rest,
                lat_min: lat_min,
                lat_max: lat_max,
                lng_min: mid,
                lng_max: lng_max,
                use_lng: False,
              )
            _ ->
              decode_bits(
                bits: rest,
                lat_min: lat_min,
                lat_max: lat_max,
                lng_min: lng_min,
                lng_max: mid,
                use_lng: False,
              )
          }
        }
        False -> {
          let mid = { lat_min +. lat_max } /. 2.0
          case bit {
            1 ->
              decode_bits(
                bits: rest,
                lat_min: mid,
                lat_max: lat_max,
                lng_min: lng_min,
                lng_max: lng_max,
                use_lng: True,
              )
            _ ->
              decode_bits(
                bits: rest,
                lat_min: lat_min,
                lat_max: mid,
                lng_min: lng_min,
                lng_max: lng_max,
                use_lng: True,
              )
          }
        }
      }
  }
}

fn index_in_alphabet(char char: String) -> Result(Int, Nil) {
  index_in_alphabet_loop(needle: char, haystack: base32_alphabet, position: 0)
}

fn index_in_alphabet_loop(
  needle needle: String,
  haystack haystack: String,
  position position: Int,
) -> Result(Int, Nil) {
  case string.pop_grapheme(haystack) {
    Error(Nil) -> Error(Nil)
    Ok(#(head, tail)) -> {
      use <- bool.guard(when: head == needle, return: Ok(position))
      index_in_alphabet_loop(
        needle: needle,
        haystack: tail,
        position: position + 1,
      )
    }
  }
}

// --- Neighbours ----------------------------------------------------------

// Adjacency tables (Niemeyer). The first row is for even-length
// hashes, the second for odd-length hashes. `BORDER[d]` lists the
// characters that, when seen as the last character of a hash of the
// given parity, lie on the boundary of the parent cell in direction
// `d` — in that case the neighbour is computed by recursing into the
// parent.

const neighbor_n_even: String = "p0r21436x8zb9dcf5h7kjnmqesgutwvy"

const neighbor_n_odd: String = "bc01fg45238967deuvhjyznpkmstqrwx"

const neighbor_e_even: String = "bc01fg45238967deuvhjyznpkmstqrwx"

const neighbor_e_odd: String = "p0r21436x8zb9dcf5h7kjnmqesgutwvy"

const neighbor_s_even: String = "14365h7k9dcfesgujnmqp0r2twvyx8zb"

const neighbor_s_odd: String = "238967debc01fg45kmstqrwxuvhjyznp"

const neighbor_w_even: String = "238967debc01fg45kmstqrwxuvhjyznp"

const neighbor_w_odd: String = "14365h7k9dcfesgujnmqp0r2twvyx8zb"

const border_n_even: String = "prxz"

const border_n_odd: String = "bcfguvyz"

const border_e_even: String = "bcfguvyz"

const border_e_odd: String = "prxz"

const border_s_even: String = "028b"

const border_s_odd: String = "0145hjnp"

const border_w_even: String = "0145hjnp"

const border_w_odd: String = "028b"

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
  case direction {
    North -> step(hash: normalised, direction: North)
    South -> step(hash: normalised, direction: South)
    East -> step(hash: normalised, direction: East)
    West -> step(hash: normalised, direction: West)
    NorthEast -> two_steps(hash: normalised, first: North, second: East)
    NorthWest -> two_steps(hash: normalised, first: North, second: West)
    SouthEast -> two_steps(hash: normalised, first: South, second: East)
    SouthWest -> two_steps(hash: normalised, first: South, second: West)
  }
}

fn two_steps(
  hash hash: String,
  first first: Direction,
  second second: Direction,
) -> Result(String, GeohashError) {
  use partial <- result.try(neighbor(hash: hash, direction: first))
  neighbor(hash: partial, direction: second)
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

fn step(
  hash hash: String,
  direction direction: Direction,
) -> Result(String, GeohashError) {
  use <- bool.guard(when: hash == "", return: Error(EmptyHash))
  let length = string.length(hash)
  let parent_length = length - 1
  let parent = string.slice(hash, 0, parent_length)
  let last = string.slice(hash, parent_length, 1)
  // Per the Niemeyer adjacency algorithm the lookup table is keyed by
  // `length % 2`: an even-length hash uses the "even" tables, an odd
  // one the "odd" tables.
  let is_even = length % 2 == 0
  let border = border_table(direction: direction, is_even: is_even)
  let lookup = neighbor_table(direction: direction, is_even: is_even)
  let parent_result = case string.contains(border, last) {
    True ->
      case parent {
        "" -> Error(EmptyHash)
        _ -> step(hash: parent, direction: direction)
      }
    False -> Ok(parent)
  }
  use new_parent <- result.try(parent_result)
  // The Niemeyer adjacency tables are keyed *by position within the
  // neighbour string*: find the position of `last` in the neighbour
  // table, and that position indexes the base32 alphabet to give the
  // new character. (Not: find the base32 index of `last`, look up
  // that position in the neighbour table — which is the easy
  // mistake.)
  case index_of_char_in(haystack: lookup, needle: last, position: 0) {
    Error(Nil) -> Error(InvalidCharacter(char: last, position: parent_length))
    Ok(value) -> Ok(new_parent <> string.slice(base32_alphabet, value, 1))
  }
}

fn index_of_char_in(
  haystack haystack: String,
  needle needle: String,
  position position: Int,
) -> Result(Int, Nil) {
  case string.pop_grapheme(haystack) {
    Error(Nil) -> Error(Nil)
    Ok(#(head, tail)) -> {
      use <- bool.guard(when: head == needle, return: Ok(position))
      index_of_char_in(haystack: tail, needle: needle, position: position + 1)
    }
  }
}

fn neighbor_table(
  direction direction: Direction,
  is_even is_even: Bool,
) -> String {
  case direction, is_even {
    North, True -> neighbor_n_even
    North, False -> neighbor_n_odd
    East, True -> neighbor_e_even
    East, False -> neighbor_e_odd
    South, True -> neighbor_s_even
    South, False -> neighbor_s_odd
    West, True -> neighbor_w_even
    West, False -> neighbor_w_odd
    _, _ -> ""
  }
}

fn border_table(direction direction: Direction, is_even is_even: Bool) -> String {
  case direction, is_even {
    North, True -> border_n_even
    North, False -> border_n_odd
    East, True -> border_e_even
    East, False -> border_e_odd
    South, True -> border_s_even
    South, False -> border_s_odd
    West, True -> border_w_even
    West, False -> border_w_odd
    _, _ -> ""
  }
}
