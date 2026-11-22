//// Geohash encoding and decoding. A geohash names a rectangular cell
//// with a string over the alphabet `0123456789bcdefghjkmnpqrstuvwxyz`.
//// Each character adds 5 bits, alternating between longitude and
//// latitude, so a longer hash names a smaller cell inside the shorter
//// one. Decoding is case-insensitive.

import gleam/bool
import gleam/list
import gleam/result
import gleam/string

import geokit.{type BoundingBox, type LatLng, BoundingBox}

const base32_alphabet: String = "0123456789bcdefghjkmnpqrstuvwxyz"

/// The reason a geohash operation failed.
pub type GeohashError {
  /// The precision was outside [1, 12].
  PrecisionOutOfRange(precision: Int)
  /// The hash was the empty string.
  EmptyHash
  /// A character outside the geohash alphabet, at a 0-based position.
  InvalidCharacter(character: String, position: Int)
  /// A step north of the northernmost row or south of the southernmost
  /// row was asked for.
  NoNeighborBeyondPole
}

/// A direction for [`neighbor`](#neighbor).
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

/// The eight cells around a geohash cell, as returned by
/// [`neighbors`](#neighbors).
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

/// Returns the geohash of the cell that contains `point`. `precision` is
/// the number of characters, in [1, 12]. A point exactly on a cell edge
/// belongs to the cell to its north or east.
///
/// ## Examples
///
/// ```gleam
/// let tokyo = geokit.wrap_lat_lng(latitude: 35.6812, longitude: 139.7671)
/// encode(tokyo, precision: 8)
/// // -> Ok("xn76urx6")
/// ```
///
/// ```gleam
/// encode(tokyo, precision: 13)
/// // -> Error(PrecisionOutOfRange(precision: 13))
/// ```
pub fn encode(
  point: LatLng,
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

/// Returns the center of the cell named by `hash`.
///
/// ## Examples
///
/// ```gleam
/// decode("xn76urx6")
/// |> result.map(fn(center) {
///   #(geokit.latitude(center), geokit.longitude(center))
/// })
/// // -> Ok(#(35.68127632141113, 139.76720809936523))
/// ```
///
/// ```gleam
/// decode("xn7a")
/// // -> Error(InvalidCharacter(character: "a", position: 3))
/// ```
pub fn decode(hash: String) -> Result(LatLng, GeohashError) {
  use BoundingBox(south_west: sw, north_east: ne) <- result.try(decode_bounds(
    hash,
  ))
  let lat = { geokit.latitude(sw) +. geokit.latitude(ne) } /. 2.0
  let lng = { geokit.longitude(sw) +. geokit.longitude(ne) } /. 2.0
  Ok(geokit.wrap_lat_lng(latitude: lat, longitude: lng))
}

/// Returns the cell named by `hash`.
///
/// ## Examples
///
/// ```gleam
/// decode_bounds("xn")
/// |> result.map(fn(cell) {
///   #(geokit.latitude(cell.south_west), geokit.longitude(cell.north_east))
/// })
/// // -> Ok(#(33.75, 146.25))
/// ```
///
/// ```gleam
/// decode_bounds("")
/// // -> Error(EmptyHash)
/// ```
pub fn decode_bounds(hash: String) -> Result(BoundingBox, GeohashError) {
  let lowered = string.lowercase(hash)
  use <- bool.guard(when: lowered == "", return: Error(EmptyHash))
  use bits <- result.try(hash_to_bits(hash: lowered, position: 0, acc: []))
  let #(last_axis, other_axis) =
    decode_bits(bits: list.reverse(bits), current: #(-180.0, 180.0), other: #(
      -90.0,
      90.0,
    ))
  // Each character is 5 bits, so an even-length hash has an even number
  // of bits and the axes end where they started (longitude current).
  let #(#(lng_min, lng_max), #(lat_min, lat_max)) = case
    string.length(lowered) % 2
  {
    0 -> #(last_axis, other_axis)
    _ -> #(other_axis, last_axis)
  }
  Ok(BoundingBox(
    south_west: geokit.wrap_lat_lng(latitude: lat_min, longitude: lng_min),
    north_east: geokit.wrap_lat_lng(latitude: lat_max, longitude: lng_max),
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
        Error(Nil) ->
          Error(InvalidCharacter(character: head, position: position))
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

// --- Neighbors -----------------------------------------------------------

/// Returns the cell next to `hash` in the given direction, at the same
/// precision. East and west wrap across the antimeridian. Returns
/// `Error(NoNeighborBeyondPole)` for a step past a pole, and
/// `Error(EmptyHash)` or `Error(InvalidCharacter(..))` for a bad hash.
///
/// ## Examples
///
/// ```gleam
/// neighbor("xn76urx6", toward: North)
/// // -> Ok("xn76urx7")
/// ```
///
/// ```gleam
/// neighbor("b", toward: North)
/// // -> Error(NoNeighborBeyondPole)
/// ```
pub fn neighbor(
  hash: String,
  toward direction: Direction,
) -> Result(String, GeohashError) {
  let lowered = string.lowercase(hash)
  use _ <- result.try(hash_to_bits(hash: lowered, position: 0, acc: []))
  case direction {
    North -> step(hash: lowered, toward: ToNorth)
    South -> step(hash: lowered, toward: ToSouth)
    East -> step(hash: lowered, toward: ToEast)
    West -> step(hash: lowered, toward: ToWest)
    NorthEast -> two_steps(hash: lowered, first: ToNorth, second: ToEast)
    NorthWest -> two_steps(hash: lowered, first: ToNorth, second: ToWest)
    SouthEast -> two_steps(hash: lowered, first: ToSouth, second: ToEast)
    SouthWest -> two_steps(hash: lowered, first: ToSouth, second: ToWest)
  }
}

/// Returns the eight cells around `hash`. A cell in the northernmost or
/// southernmost row has no cell on one side, so the result is
/// `Error(NoNeighborBeyondPole)` there. Use [`neighbor`](#neighbor) to
/// get the cells that do exist.
///
/// ## Examples
///
/// ```gleam
/// neighbors("xn76urx6") |> result.map(fn(cells) { cells.east })
/// // -> Ok("xn76urxd")
/// ```
///
/// ```gleam
/// neighbors("b")
/// // -> Error(NoNeighborBeyondPole)
/// ```
pub fn neighbors(hash: String) -> Result(Neighbors, GeohashError) {
  use n <- result.try(neighbor(hash, toward: North))
  use s <- result.try(neighbor(hash, toward: South))
  use e <- result.try(neighbor(hash, toward: East))
  use w <- result.try(neighbor(hash, toward: West))
  use ne <- result.try(neighbor(hash, toward: NorthEast))
  use nw <- result.try(neighbor(hash, toward: NorthWest))
  use se <- result.try(neighbor(hash, toward: SouthEast))
  use sw <- result.try(neighbor(hash, toward: SouthWest))
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
        // Crossing a pole has no neighbor.
        True, "" -> Error(NoNeighborBeyondPole)
        True, _ -> step(hash: parent, toward: toward)
      })
      // The Niemeyer adjacency tables are keyed *by position within
      // the neighbor string*: find the position of `last` in the
      // neighbor table, and that position indexes the base32
      // alphabet to give the new character. (Not: find the base32
      // index of `last` and look up that position in the neighbor
      // table, which is the easy mistake.)
      case index_of(char: last, table: lookup) {
        Error(Nil) ->
          Error(InvalidCharacter(
            character: last,
            position: string.length(parent),
          ))
        Ok(value) -> Ok(new_parent <> string.slice(base32_alphabet, value, 1))
      }
    }
  }
}

// Adjacency tables (Niemeyer): `#(neighbor, border)` for a direction
// and the parity of the hash length. `border` lists the characters
// that, as the last character of a hash, lie on the edge of the parent
// cell in that direction; the neighbor is then computed from the
// parent's neighbor.
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
