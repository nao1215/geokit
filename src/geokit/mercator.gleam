//// Web Mercator (EPSG:3857) tile and quadkey conversion.
////
//// Web Mercator is the projection used by every slippy map service:
//// Google Maps, OpenStreetMap, Bing Maps, Mapbox. The world at zoom
//// level `z` is divided into `2 ^ z` × `2 ^ z` square tiles indexed
//// by `(x, y)` with `(0, 0)` at the top-left (north-west) corner.
////
//// Tiles outside the supported latitude range (`±85.05112878°`,
//// where the projection clips to keep the map square) are not
//// representable; [`from_lat_lng`](#from_lat_lng) clamps latitude
//// rather than reporting an error.
////
//// Quadkeys are Bing Maps' single-string encoding of `(zoom, x, y)`.

import gleam/bool
import gleam/float
import gleam/int
import gleam/result
import gleam/string

import gleam_community/maths

import geokit/latlng.{type LatLng}

/// A tile identified by its zoom level and `(x, y)` coordinates.
/// `pub opaque`; build through [`tile`](#tile) and inspect through
/// [`zoom`](#zoom), [`x`](#x), and [`y`](#y).
pub opaque type Tile {
  Tile(zoom: Int, x: Int, y: Int)
}

/// Errors returned by tile and quadkey operations.
pub type MercatorError {
  /// Zoom level was outside `[0, 30]`.
  ZoomOutOfRange(zoom: Int)
  /// `x` or `y` was outside `[0, 2^zoom)`.
  TileCoordOutOfRange(zoom: Int, x: Int, y: Int)
  /// A character outside `{0, 1, 2, 3}` appeared in a quadkey.
  InvalidQuadkeyChar(char: String, position: Int)
  /// [`quadkey_to_tile`](#quadkey_to_tile) was called with an empty
  /// string.
  EmptyQuadkey
}

// --- Constructors / accessors -------------------------------------------

/// Build a [`Tile`](#Tile). `zoom` must be in `[0, 30]`; `x` and `y`
/// must each be in `[0, 2^zoom)`.
///
/// Matches the constructor naming convention used by every other
/// opaque type in geokit (e.g. [`latlng.new`](../latlng.html#new)).
pub fn new(zoom zoom: Int, x x: Int, y y: Int) -> Result(Tile, MercatorError) {
  use <- bool.guard(
    when: zoom < 0 || zoom > 30,
    return: Error(ZoomOutOfRange(zoom: zoom)),
  )
  let max_coord = pow_2(zoom)
  use <- bool.guard(
    when: x < 0 || y < 0 || x >= max_coord || y >= max_coord,
    return: Error(TileCoordOutOfRange(zoom: zoom, x: x, y: y)),
  )
  Ok(Tile(zoom: zoom, x: x, y: y))
}

/// Build a [`Tile`](#Tile). Alias for [`new`](#new) kept for backward
/// compatibility; new code should call [`new`](#new) instead.
@deprecated("Use mercator.new — the constructor was renamed for parity with latlng.new (will be removed in 1.0).")
pub fn tile(zoom zoom: Int, x x: Int, y y: Int) -> Result(Tile, MercatorError) {
  new(zoom: zoom, x: x, y: y)
}

/// Zoom level of `tile`.
pub fn zoom(tile tile: Tile) -> Int {
  tile.zoom
}

/// Tile `x` coordinate.
pub fn x(tile tile: Tile) -> Int {
  tile.x
}

/// Tile `y` coordinate.
pub fn y(tile tile: Tile) -> Int {
  tile.y
}

// --- LatLng <-> Tile ----------------------------------------------------

/// Convert a [`LatLng`](../latlng.html#LatLng) to the [`Tile`](#Tile)
/// that contains it at the given zoom level.
///
/// Latitude is clamped to `±85.05112878°` (the Web Mercator pole
/// limit) before projection, so any input `LatLng` produces a valid
/// tile.
pub fn from_lat_lng(
  point point: LatLng,
  zoom zoom: Int,
) -> Result(Tile, MercatorError) {
  use <- bool.guard(
    when: zoom < 0 || zoom > 30,
    return: Error(ZoomOutOfRange(zoom: zoom)),
  )
  let pole_limit = 85.051_128_78
  let lat =
    float.clamp(latlng.lat(point), min: 0.0 -. pole_limit, max: pole_limit)
  let lng = latlng.lng(point)
  let n = int_to_float(pow_2(zoom))
  let lat_rad = maths.degrees_to_radians(lat)
  let x_float = { lng +. 180.0 } /. 360.0 *. n
  let y_float =
    { 1.0 -. maths.asinh(maths.tan(lat_rad)) /. maths.pi() } /. 2.0 *. n
  let max_coord = pow_2(zoom)
  let x_int =
    clamp_int(value: float_to_int(x_float), min: 0, max: max_coord - 1)
  let y_int =
    clamp_int(value: float_to_int(y_float), min: 0, max: max_coord - 1)
  Ok(Tile(zoom: zoom, x: x_int, y: y_int))
}

/// Top-left (north-west) corner of `tile` as a
/// [`LatLng`](../latlng.html#LatLng).
pub fn to_lat_lng(tile tile: Tile) -> LatLng {
  corner_lat_lng(zoom: tile.zoom, x: tile.x, y: tile.y)
}

/// The south-west and north-east corners of `tile`, returned as
/// `#(sw, ne)`.
pub fn bounds(tile tile: Tile) -> #(LatLng, LatLng) {
  let nw = corner_lat_lng(zoom: tile.zoom, x: tile.x, y: tile.y)
  let se = corner_lat_lng(zoom: tile.zoom, x: tile.x + 1, y: tile.y + 1)
  let sw = latlng.wrap(lat: latlng.lat(se), lng: latlng.lng(nw))
  let ne = latlng.wrap(lat: latlng.lat(nw), lng: latlng.lng(se))
  #(sw, ne)
}

fn corner_lat_lng(zoom zoom: Int, x x: Int, y y: Int) -> LatLng {
  let n = int_to_float(pow_2(zoom))
  let lng = int_to_float(x) /. n *. 360.0 -. 180.0
  let lat_rad =
    maths.atan(maths.sinh(maths.pi() *. { 1.0 -. 2.0 *. int_to_float(y) /. n }))
  let lat = maths.radians_to_degrees(lat_rad)
  latlng.wrap(lat: lat, lng: lng)
}

// --- Quadkey ------------------------------------------------------------

/// Encode `tile` as a Bing-style quadkey. The length of the result
/// equals `zoom(tile)`.
pub fn to_quadkey(tile tile: Tile) -> String {
  to_quadkey_loop(tile: tile, level: tile.zoom, acc: "")
}

fn to_quadkey_loop(tile tile: Tile, level level: Int, acc acc: String) -> String {
  use <- bool.guard(when: level <= 0, return: acc)
  let mask = pow_2(level - 1)
  let bit_x = tile.x / mask % 2
  let bit_y = tile.y / mask % 2
  let digit = bit_x + 2 * bit_y
  let char = case digit {
    0 -> "0"
    1 -> "1"
    2 -> "2"
    _ -> "3"
  }
  to_quadkey_loop(tile: tile, level: level - 1, acc: acc <> char)
}

/// Decode a quadkey to a [`Tile`](#Tile). The resulting `zoom` equals
/// the length of the quadkey, which must be in `[1, 30]` to mirror
/// the range accepted by [`new`](#new).
pub fn from_quadkey(quadkey quadkey: String) -> Result(Tile, MercatorError) {
  use <- bool.guard(when: quadkey == "", return: Error(EmptyQuadkey))
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
) -> Result(#(Int, Int, Int), MercatorError) {
  case chars {
    [] -> Ok(#(x, y, position))
    [head, ..tail] -> {
      let digit_result = case head {
        "0" -> Ok(#(0, 0))
        "1" -> Ok(#(1, 0))
        "2" -> Ok(#(0, 1))
        "3" -> Ok(#(1, 1))
        _ -> Error(InvalidQuadkeyChar(char: head, position: position))
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

// --- Helpers ------------------------------------------------------------

fn pow_2(exponent: Int) -> Int {
  use <- bool.guard(when: exponent <= 0, return: 1)
  2 * pow_2(exponent - 1)
}

fn float_to_int(value: Float) -> Int {
  float.truncate(value)
}

fn int_to_float(value: Int) -> Float {
  int.to_float(value)
}

fn clamp_int(value value: Int, min min: Int, max max: Int) -> Int {
  use <- bool.guard(when: value < min, return: min)
  use <- bool.guard(when: value > max, return: max)
  value
}
