import gleeunit/should

import geokit.{type LatLng}
import geokit/tile

fn approx_equal(a: Float, b: Float, tolerance: Float) -> Bool {
  let delta = case a >. b {
    True -> a -. b
    False -> b -. a
  }
  delta <=. tolerance
}

// --- tile constructor / accessors ---------------------------------------

pub fn tile_constructor_test() -> Nil {
  let assert Ok(t) = tile.new(zoom: 5, x: 10, y: 12)
  tile.zoom(t)
  |> should.equal(5)
  tile.x(t)
  |> should.equal(10)
  tile.y(t)
  |> should.equal(12)
}

pub fn tile_zoom_out_of_range_test() -> Nil {
  case tile.new(zoom: -1, x: 0, y: 0) {
    Error(tile.ZoomOutOfRange(zoom: -1)) -> Nil
    _ -> should.be_true(False)
  }
  case tile.new(zoom: 31, x: 0, y: 0) {
    Error(tile.ZoomOutOfRange(zoom: 31)) -> Nil
    _ -> should.be_true(False)
  }
}

pub fn tile_coord_out_of_range_test() -> Nil {
  // At zoom 2, max coord is 4 (exclusive), so x=4 is invalid.
  case tile.new(zoom: 2, x: 4, y: 0) {
    Error(tile.CoordinateOutOfRange(zoom: 2, x: 4, y: 0)) -> Nil
    _ -> should.be_true(False)
  }
}

pub fn tile_each_coord_bound_is_checked_test() -> Nil {
  // Each of the four bounds alone must reject the tile.
  tile.new(zoom: 2, x: -1, y: 0)
  |> should.equal(Error(tile.CoordinateOutOfRange(zoom: 2, x: -1, y: 0)))
  tile.new(zoom: 2, x: 0, y: -1)
  |> should.equal(Error(tile.CoordinateOutOfRange(zoom: 2, x: 0, y: -1)))
  tile.new(zoom: 2, x: 0, y: 4)
  |> should.equal(Error(tile.CoordinateOutOfRange(zoom: 2, x: 0, y: 4)))
}

pub fn from_lat_lng_zoom_out_of_range_test() -> Nil {
  let assert Ok(origin) = geokit.lat_lng(latitude: 0.0, longitude: 0.0)
  tile.from_lat_lng(origin, zoom: -1)
  |> should.equal(Error(tile.ZoomOutOfRange(zoom: -1)))
  tile.from_lat_lng(origin, zoom: 31)
  |> should.equal(Error(tile.ZoomOutOfRange(zoom: 31)))
}

// --- LatLng <-> Tile ----------------------------------------------------

pub fn origin_at_zoom_zero_test() -> Nil {
  // The single tile at zoom 0 covers the whole world.
  let assert Ok(origin) = geokit.lat_lng(latitude: 0.0, longitude: 0.0)
  let assert Ok(t) = tile.from_lat_lng(origin, zoom: 0)
  tile.x(t)
  |> should.equal(0)
  tile.y(t)
  |> should.equal(0)
}

pub fn known_tile_at_zoom_2_test() -> Nil {
  // Tokyo (35.68, 139.77) at zoom 2 lies in tile (3, 1) — east hemisphere
  // upper-middle quadrant.
  let assert Ok(tokyo) = geokit.lat_lng(latitude: 35.68, longitude: 139.77)
  let assert Ok(t) = tile.from_lat_lng(tokyo, zoom: 2)
  tile.zoom(t)
  |> should.equal(2)
  tile.x(t)
  |> should.equal(3)
  tile.y(t)
  |> should.equal(1)
}

pub fn lat_lng_round_trip_test() -> Nil {
  // For a point at the tile center, projecting to a tile then back
  // recovers a point inside the same tile.
  let assert Ok(point) = geokit.lat_lng(latitude: 35.68, longitude: 139.77)
  let assert Ok(t) = tile.from_lat_lng(point, zoom: 10)
  let nw = north_west(t)
  let #(sw, ne) = tile_bounds(t)
  // The original point should lie inside the tile's bounding box.
  { geokit.latitude(point) <=. geokit.latitude(nw) }
  |> should.be_true
  { geokit.latitude(point) >=. geokit.latitude(sw) }
  |> should.be_true
  { geokit.longitude(point) >=. geokit.longitude(sw) }
  |> should.be_true
  { geokit.longitude(point) <=. geokit.longitude(ne) }
  |> should.be_true
}

pub fn tile_north_west_corner_of_origin_test() -> Nil {
  // Tile (0,0,0) NW corner is roughly (85.05, -180).
  let assert Ok(t) = tile.new(zoom: 0, x: 0, y: 0)
  let nw = north_west(t)
  approx_equal(geokit.longitude(nw), -180.0, 0.001)
  |> should.be_true
  approx_equal(geokit.latitude(nw), 85.05112878, 0.001)
  |> should.be_true
}

pub fn lat_lng_clamps_at_poles_test() -> Nil {
  // Latitudes beyond the Mercator clip should still produce a valid
  // tile (the function clamps rather than errors).
  let assert Ok(north) = geokit.lat_lng(latitude: 89.9, longitude: 0.0)
  let assert Ok(t) = tile.from_lat_lng(north, zoom: 5)
  tile.zoom(t)
  |> should.equal(5)
}

// --- quadkey ------------------------------------------------------------

pub fn quadkey_zero_test() -> Nil {
  // The single tile at zoom 0 has an empty quadkey by convention.
  let assert Ok(t) = tile.new(zoom: 0, x: 0, y: 0)
  tile.to_quadkey(t)
  |> should.equal("")
}

pub fn quadkey_microsoft_example_test() -> Nil {
  // Bing Maps documentation example: tile (3, 5) at zoom 3 → "213".
  let assert Ok(t) = tile.new(zoom: 3, x: 3, y: 5)
  tile.to_quadkey(t)
  |> should.equal("213")
}

pub fn quadkey_round_trip_test() -> Nil {
  let assert Ok(t) = tile.new(zoom: 7, x: 65, y: 42)
  let qk = tile.to_quadkey(t)
  let assert Ok(decoded) = tile.from_quadkey(qk)
  tile.zoom(decoded)
  |> should.equal(7)
  tile.x(decoded)
  |> should.equal(65)
  tile.y(decoded)
  |> should.equal(42)
}

pub fn quadkey_invalid_char_test() -> Nil {
  case tile.from_quadkey("12X3") {
    Error(tile.InvalidQuadkeyCharacter(character: "X", position: 2)) -> Nil
    _ -> should.be_true(False)
  }
}

// Issue #20: from_quadkey("") used to error with EmptyQuadkey,
// breaking the to_quadkey -> from_quadkey round-trip at zoom 0
// (where the whole world is one tile whose canonical Bing Maps
// quadkey is "").
pub fn quadkey_empty_decodes_to_zoom_zero_root_test() -> Nil {
  let assert Ok(t) = tile.from_quadkey("")
  tile.zoom(t)
  |> should.equal(0)
  tile.x(t)
  |> should.equal(0)
  tile.y(t)
  |> should.equal(0)
}

pub fn quadkey_zoom_zero_round_trip_test() -> Nil {
  let assert Ok(ll) = geokit.lat_lng(latitude: 0.0, longitude: 0.0)
  let assert Ok(tile) = tile.from_lat_lng(ll, zoom: 0)
  let qk = tile.to_quadkey(tile)
  qk
  |> should.equal("")
  let assert Ok(decoded) = tile.from_quadkey(qk)
  tile.zoom(decoded)
  |> should.equal(0)
  tile.x(decoded)
  |> should.equal(0)
  tile.y(decoded)
  |> should.equal(0)
}

pub fn quadkey_too_long_31_chars_rejected_test() -> Nil {
  // Regression for #9: from_quadkey used to accept inputs longer
  // than 30 chars and produce Tile values with zoom outside the
  // [0, 30] range that tile.new accepts. The two constructors
  // must agree on the valid domain.
  case tile.from_quadkey("0000000000000000000000000000000") {
    Error(tile.ZoomOutOfRange(zoom: 31)) -> Nil
    _ -> should.be_true(False)
  }
}

pub fn quadkey_too_long_50_chars_rejected_test() -> Nil {
  let qk = "00000000000000000000000000000000000000000000000000"
  case tile.from_quadkey(qk) {
    Error(tile.ZoomOutOfRange(zoom: 50)) -> Nil
    _ -> should.be_true(False)
  }
}

pub fn quadkey_at_max_length_30_accepted_test() -> Nil {
  // Length 30 is the documented upper bound — it must still parse.
  let qk = "000000000000000000000000000000"
  let assert Ok(t) = tile.from_quadkey(qk)
  tile.zoom(t)
  |> should.equal(30)
}

fn tile_bounds(t: tile.Tile) -> #(LatLng, LatLng) {
  let box = tile.bounds(t)
  #(box.south_west, box.north_east)
}

fn north_west(t: tile.Tile) -> LatLng {
  let box = tile.bounds(t)
  geokit.wrap_lat_lng(
    latitude: geokit.latitude(box.north_east),
    longitude: geokit.longitude(box.south_west),
  )
}
