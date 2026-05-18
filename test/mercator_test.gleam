import gleeunit/should

import geokit/latlng
import geokit/mercator

fn approx_equal(a: Float, b: Float, tolerance: Float) -> Bool {
  let delta = case a >. b {
    True -> a -. b
    False -> b -. a
  }
  delta <=. tolerance
}

// --- tile constructor / accessors ---------------------------------------

pub fn tile_constructor_test() -> Nil {
  let assert Ok(t) = mercator.new(zoom: 5, x: 10, y: 12)
  mercator.zoom(tile: t)
  |> should.equal(5)
  mercator.x(tile: t)
  |> should.equal(10)
  mercator.y(tile: t)
  |> should.equal(12)
}

pub fn tile_zoom_out_of_range_test() -> Nil {
  case mercator.new(zoom: -1, x: 0, y: 0) {
    Error(mercator.ZoomOutOfRange(zoom: -1)) -> Nil
    _ -> should.be_true(False)
  }
  case mercator.new(zoom: 31, x: 0, y: 0) {
    Error(mercator.ZoomOutOfRange(zoom: 31)) -> Nil
    _ -> should.be_true(False)
  }
}

pub fn tile_coord_out_of_range_test() -> Nil {
  // At zoom 2, max coord is 4 (exclusive), so x=4 is invalid.
  case mercator.new(zoom: 2, x: 4, y: 0) {
    Error(mercator.TileCoordOutOfRange(zoom: 2, x: 4, y: 0)) -> Nil
    _ -> should.be_true(False)
  }
}

// --- LatLng <-> Tile ----------------------------------------------------

pub fn origin_at_zoom_zero_test() -> Nil {
  // The single tile at zoom 0 covers the whole world.
  let assert Ok(origin) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(t) = mercator.from_lat_lng(point: origin, zoom: 0)
  mercator.x(tile: t)
  |> should.equal(0)
  mercator.y(tile: t)
  |> should.equal(0)
}

pub fn known_tile_at_zoom_2_test() -> Nil {
  // Tokyo (35.68, 139.77) at zoom 2 lies in tile (3, 1) — east hemisphere
  // upper-middle quadrant.
  let assert Ok(tokyo) = latlng.new(lat: 35.68, lng: 139.77)
  let assert Ok(t) = mercator.from_lat_lng(point: tokyo, zoom: 2)
  mercator.zoom(tile: t)
  |> should.equal(2)
  mercator.x(tile: t)
  |> should.equal(3)
  mercator.y(tile: t)
  |> should.equal(1)
}

pub fn lat_lng_round_trip_test() -> Nil {
  // For a point at the tile centre, projecting to a tile then back
  // recovers a point inside the same tile.
  let assert Ok(point) = latlng.new(lat: 35.68, lng: 139.77)
  let assert Ok(t) = mercator.from_lat_lng(point: point, zoom: 10)
  let nw = mercator.to_lat_lng(tile: t)
  let #(sw, ne) = mercator.bounds(tile: t)
  // The original point should lie inside the tile's bounding box.
  { latlng.lat(point) <=. latlng.lat(nw) }
  |> should.be_true
  { latlng.lat(point) >=. latlng.lat(sw) }
  |> should.be_true
  { latlng.lng(point) >=. latlng.lng(sw) }
  |> should.be_true
  { latlng.lng(point) <=. latlng.lng(ne) }
  |> should.be_true
}

pub fn tile_to_lat_lng_origin_test() -> Nil {
  // Tile (0,0,0) NW corner is roughly (85.05, -180).
  let assert Ok(t) = mercator.new(zoom: 0, x: 0, y: 0)
  let nw = mercator.to_lat_lng(tile: t)
  approx_equal(latlng.lng(nw), -180.0, 0.001)
  |> should.be_true
  approx_equal(latlng.lat(nw), 85.05112878, 0.001)
  |> should.be_true
}

pub fn lat_lng_clamps_at_poles_test() -> Nil {
  // Latitudes beyond the Mercator clip should still produce a valid
  // tile (the function clamps rather than errors).
  let assert Ok(north) = latlng.new(lat: 89.9, lng: 0.0)
  let assert Ok(t) = mercator.from_lat_lng(point: north, zoom: 5)
  mercator.zoom(tile: t)
  |> should.equal(5)
}

// --- quadkey ------------------------------------------------------------

pub fn quadkey_zero_test() -> Nil {
  // The single tile at zoom 0 has an empty quadkey by convention.
  let assert Ok(t) = mercator.new(zoom: 0, x: 0, y: 0)
  mercator.to_quadkey(tile: t)
  |> should.equal("")
}

pub fn quadkey_microsoft_example_test() -> Nil {
  // Bing Maps documentation example: tile (3, 5) at zoom 3 → "213".
  let assert Ok(t) = mercator.new(zoom: 3, x: 3, y: 5)
  mercator.to_quadkey(tile: t)
  |> should.equal("213")
}

pub fn quadkey_round_trip_test() -> Nil {
  let assert Ok(t) = mercator.new(zoom: 7, x: 65, y: 42)
  let qk = mercator.to_quadkey(tile: t)
  let assert Ok(decoded) = mercator.from_quadkey(quadkey: qk)
  mercator.zoom(tile: decoded)
  |> should.equal(7)
  mercator.x(tile: decoded)
  |> should.equal(65)
  mercator.y(tile: decoded)
  |> should.equal(42)
}

pub fn quadkey_invalid_char_test() -> Nil {
  case mercator.from_quadkey(quadkey: "12X3") {
    Error(mercator.InvalidQuadkeyChar(char: "X", position: 2)) -> Nil
    _ -> should.be_true(False)
  }
}

// Issue #20: from_quadkey("") used to error with EmptyQuadkey,
// breaking the to_quadkey -> from_quadkey round-trip at zoom 0
// (where the whole world is one tile whose canonical Bing Maps
// quadkey is "").
pub fn quadkey_empty_decodes_to_zoom_zero_root_test() -> Nil {
  let assert Ok(t) = mercator.from_quadkey(quadkey: "")
  mercator.zoom(t)
  |> should.equal(0)
  mercator.x(t)
  |> should.equal(0)
  mercator.y(t)
  |> should.equal(0)
}

pub fn quadkey_zoom_zero_round_trip_test() -> Nil {
  let assert Ok(ll) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(tile) = mercator.from_lat_lng(point: ll, zoom: 0)
  let qk = mercator.to_quadkey(tile: tile)
  qk
  |> should.equal("")
  let assert Ok(decoded) = mercator.from_quadkey(quadkey: qk)
  mercator.zoom(decoded)
  |> should.equal(0)
  mercator.x(decoded)
  |> should.equal(0)
  mercator.y(decoded)
  |> should.equal(0)
}

pub fn quadkey_too_long_31_chars_rejected_test() -> Nil {
  // Regression for #9: from_quadkey used to accept inputs longer
  // than 30 chars and produce Tile values with zoom outside the
  // [0, 30] range that mercator.new accepts. The two constructors
  // must agree on the valid domain.
  case mercator.from_quadkey(quadkey: "0000000000000000000000000000000") {
    Error(mercator.ZoomOutOfRange(zoom: 31)) -> Nil
    _ -> should.be_true(False)
  }
}

pub fn quadkey_too_long_50_chars_rejected_test() -> Nil {
  let qk = "00000000000000000000000000000000000000000000000000"
  case mercator.from_quadkey(quadkey: qk) {
    Error(mercator.ZoomOutOfRange(zoom: 50)) -> Nil
    _ -> should.be_true(False)
  }
}

pub fn quadkey_at_max_length_30_accepted_test() -> Nil {
  // Length 30 is the documented upper bound — it must still parse.
  let qk = "000000000000000000000000000000"
  let assert Ok(t) = mercator.from_quadkey(quadkey: qk)
  mercator.zoom(tile: t)
  |> should.equal(30)
}
