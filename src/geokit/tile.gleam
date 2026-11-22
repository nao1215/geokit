//// Web Mercator (EPSG:3857) map tiles. At zoom level `z` the world is a
//// grid of 2^z by 2^z tiles, with `x` growing east from the antimeridian
//// and `y` growing south from the top edge at latitude 85.05112878.
//// A quadkey writes a tile as one base-4 digit per zoom level.

import gleam/bool
import gleam/float
import gleam/int
import gleam/result
import gleam/string

import gleam_community/maths

import geokit.{type BoundingBox, type LatLng, BoundingBox}

/// A tile at a zoom level. Build one with [`new`](#new),
/// [`from_lat_lng`](#from_lat_lng) or [`from_quadkey`](#from_quadkey).
pub opaque type Tile {
  // Invariant: zoom is in [0, 30], and x and y are in [0, 2^zoom).
  Tile(zoom: Int, x: Int, y: Int)
}

/// The reason a tile operation failed.
pub type TileError {
  /// The zoom level was outside [0, 30].
  ZoomOutOfRange(zoom: Int)
  /// `x` or `y` was outside [0, 2^zoom).
  CoordinateOutOfRange(zoom: Int, x: Int, y: Int)
  /// A character other than 0, 1, 2 or 3, at a 0-based position.
  InvalidQuadkeyCharacter(character: String, position: Int)
}

/// Returns the tile at `zoom` in [0, 30] with `x` and `y` in [0, 2^zoom).
///
/// ## Examples
///
/// ```gleam
/// new(zoom: 1, x: 1, y: 0) |> result.map(to_quadkey)
/// // -> Ok("1")
/// ```
///
/// ```gleam
/// new(zoom: 1, x: 2, y: 0)
/// // -> Error(CoordinateOutOfRange(zoom: 1, x: 2, y: 0))
/// ```
pub fn new(zoom zoom: Int, x x: Int, y y: Int) -> Result(Tile, TileError) {
  use <- bool.guard(
    when: zoom < 0 || zoom > 30,
    return: Error(ZoomOutOfRange(zoom: zoom)),
  )
  let max_coord = int.bitwise_shift_left(1, zoom)
  use <- bool.guard(
    when: x < 0 || y < 0 || x >= max_coord || y >= max_coord,
    return: Error(CoordinateOutOfRange(zoom: zoom, x: x, y: y)),
  )
  Ok(Tile(zoom: zoom, x: x, y: y))
}

/// Returns the zoom level of `tile`.
///
/// ## Examples
///
/// ```gleam
/// from_quadkey("120") |> result.map(zoom)
/// // -> Ok(3)
/// ```
pub fn zoom(tile: Tile) -> Int {
  tile.zoom
}

/// Returns the column of `tile`, counted east from the antimeridian.
///
/// ## Examples
///
/// ```gleam
/// from_quadkey("120") |> result.map(x)
/// // -> Ok(4)
/// ```
pub fn x(tile: Tile) -> Int {
  tile.x
}

/// Returns the row of `tile`, counted south from the top edge.
///
/// ## Examples
///
/// ```gleam
/// from_quadkey("120") |> result.map(y)
/// // -> Ok(2)
/// ```
pub fn y(tile: Tile) -> Int {
  tile.y
}

// --- LatLng <-> Tile ----------------------------------------------------

/// Returns the tile that contains `point` at `zoom` in [0, 30]. Latitudes
/// beyond 85.05112878 degrees north or south map to the top or bottom
/// row.
///
/// ## Examples
///
/// ```gleam
/// let tokyo = geokit.wrap_lat_lng(latitude: 35.6812, longitude: 139.7671)
/// from_lat_lng(tokyo, zoom: 10)
/// |> result.map(fn(tile) { #(x(tile), y(tile)) })
/// // -> Ok(#(909, 403))
/// ```
///
/// ```gleam
/// from_lat_lng(tokyo, zoom: 31)
/// // -> Error(ZoomOutOfRange(zoom: 31))
/// ```
pub fn from_lat_lng(point: LatLng, zoom zoom: Int) -> Result(Tile, TileError) {
  use <- bool.guard(
    when: zoom < 0 || zoom > 30,
    return: Error(ZoomOutOfRange(zoom: zoom)),
  )
  let pole_limit = 85.051_128_78
  let lat =
    float.clamp(geokit.latitude(point), min: 0.0 -. pole_limit, max: pole_limit)
  let lng = geokit.longitude(point)
  let n = int.to_float(int.bitwise_shift_left(1, zoom))
  let lat_rad = maths.degrees_to_radians(lat)
  let x_float = { lng +. 180.0 } /. 360.0 *. n
  let y_float =
    { 1.0 -. maths.asinh(maths.tan(lat_rad)) /. maths.pi() } /. 2.0 *. n
  let max_coord = int.bitwise_shift_left(1, zoom)
  let x_int = int.clamp(float.truncate(x_float), min: 0, max: max_coord - 1)
  let y_int = int.clamp(float.truncate(y_float), min: 0, max: max_coord - 1)
  Ok(Tile(zoom: zoom, x: x_int, y: y_int))
}

/// Returns the area covered by `tile`.
///
/// ## Examples
///
/// ```gleam
/// new(zoom: 1, x: 1, y: 0)
/// |> result.map(fn(tile) {
///   let box = bounds(tile)
///   #(geokit.latitude(box.south_west), geokit.longitude(box.south_west))
/// })
/// // -> Ok(#(0.0, 0.0))
/// ```
pub fn bounds(tile: Tile) -> BoundingBox {
  let nw = corner_lat_lng(zoom: tile.zoom, x: tile.x, y: tile.y)
  let se = corner_lat_lng(zoom: tile.zoom, x: tile.x + 1, y: tile.y + 1)
  BoundingBox(
    south_west: geokit.wrap_lat_lng(
      latitude: geokit.latitude(se),
      longitude: geokit.longitude(nw),
    ),
    north_east: geokit.wrap_lat_lng(
      latitude: geokit.latitude(nw),
      longitude: geokit.longitude(se),
    ),
  )
}

fn corner_lat_lng(zoom zoom: Int, x x: Int, y y: Int) -> LatLng {
  let n = int.to_float(int.bitwise_shift_left(1, zoom))
  let lng = int.to_float(x) /. n *. 360.0 -. 180.0
  let lat_rad =
    maths.atan(maths.sinh(maths.pi() *. { 1.0 -. 2.0 *. int.to_float(y) /. n }))
  let lat = maths.radians_to_degrees(lat_rad)
  geokit.wrap_lat_lng(latitude: lat, longitude: lng)
}

// --- Quadkey ------------------------------------------------------------

/// Returns the quadkey of `tile`, one digit per zoom level. The zoom 0
/// tile has the empty quadkey.
///
/// ## Examples
///
/// ```gleam
/// new(zoom: 3, x: 4, y: 2) |> result.map(to_quadkey)
/// // -> Ok("120")
/// ```
pub fn to_quadkey(tile: Tile) -> String {
  to_quadkey_loop(tile: tile, level: tile.zoom, acc: "")
}

fn to_quadkey_loop(
  tile tile: Tile,
  level level: Int,
  acc acc: String,
) -> String {
  case level {
    0 -> acc
    _ -> {
      let mask = int.bitwise_shift_left(1, level - 1)
      let bit_x = tile.x / mask % 2
      let bit_y = tile.y / mask % 2
      let digit = case bit_x + 2 * bit_y {
        0 -> "0"
        1 -> "1"
        2 -> "2"
        _ -> "3"
      }
      to_quadkey_loop(tile: tile, level: level - 1, acc: acc <> digit)
    }
  }
}

/// Returns the tile named by `quadkey`. Its zoom is the length of the
/// quadkey, at most 30, and the empty string is the zoom 0 tile.
///
/// ## Examples
///
/// ```gleam
/// from_quadkey("120") |> result.map(fn(tile) { #(x(tile), y(tile)) })
/// // -> Ok(#(4, 2))
/// ```
///
/// ```gleam
/// from_quadkey("124")
/// // -> Error(InvalidQuadkeyCharacter(character: "4", position: 2))
/// ```
pub fn from_quadkey(quadkey: String) -> Result(Tile, TileError) {
  let length = string.length(quadkey)
  use <- bool.guard(
    when: length > 30,
    return: Error(ZoomOutOfRange(zoom: length)),
  )
  use #(x_int, y_int, parsed_length) <- result.try(from_quadkey_loop(
    chars: string.to_graphemes(quadkey),
    position: 0,
    x: 0,
    y: 0,
  ))
  Ok(Tile(zoom: parsed_length, x: x_int, y: y_int))
}

fn from_quadkey_loop(
  chars chars: List(String),
  position position: Int,
  x x: Int,
  y y: Int,
) -> Result(#(Int, Int, Int), TileError) {
  case chars {
    [] -> Ok(#(x, y, position))
    [head, ..tail] -> {
      let digit_result = case head {
        "0" -> Ok(#(0, 0))
        "1" -> Ok(#(1, 0))
        "2" -> Ok(#(0, 1))
        "3" -> Ok(#(1, 1))
        _ -> Error(InvalidQuadkeyCharacter(character: head, position: position))
      }
      use #(bit_x, bit_y) <- result.try(digit_result)
      from_quadkey_loop(
        chars: tail,
        position: position + 1,
        x: x * 2 + bit_x,
        y: y * 2 + bit_y,
      )
    }
  }
}
