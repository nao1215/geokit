import gleam/string
import gleeunit/should

import geokit/geohash
import geokit/latlng

fn approx_equal(a: Float, b: Float, tolerance: Float) -> Bool {
  let delta = case a >. b {
    True -> a -. b
    False -> b -. a
  }
  delta <=. tolerance
}

// --- encode --------------------------------------------------------------

pub fn encode_wikipedia_test() -> Nil {
  // Wikipedia example: (42.6, -5.6) → "ezs42" (matches ngeohash).
  let assert Ok(point) = latlng.new(lat: 42.6, lng: -5.6)
  let assert Ok(hash) = geohash.encode(point: point, precision: 5)
  hash
  |> should.equal("ezs42")
}

pub fn encode_origin_test() -> Nil {
  // (0, 0) at precision 5 → "7zzzz" (matches ngeohash). The
  // commonly-cited "s0000" is wrong; it would require non-strict
  // greater-than comparison at the midpoint, which differs from the
  // standard geohash algorithm.
  let assert Ok(origin) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(hash) = geohash.encode(point: origin, precision: 5)
  hash
  |> should.equal("7zzzz")
}

pub fn encode_high_precision_test() -> Nil {
  // (57.64911, 10.40744) at precision 11 → "u4pruydqqvj".
  let assert Ok(point) = latlng.new(lat: 57.64911, lng: 10.40744)
  let assert Ok(hash) = geohash.encode(point: point, precision: 11)
  hash
  |> should.equal("u4pruydqqvj")
}

pub fn encode_tokyo_test() -> Nil {
  // (35.6812, 139.7671) at precision 8 → "xn76urx6" (matches ngeohash).
  let assert Ok(tokyo) = latlng.new(lat: 35.6812, lng: 139.7671)
  let assert Ok(hash) = geohash.encode(point: tokyo, precision: 8)
  hash
  |> should.equal("xn76urx6")
}

pub fn encode_precision_too_low_test() -> Nil {
  let assert Ok(point) = latlng.new(lat: 0.0, lng: 0.0)
  case geohash.encode(point: point, precision: 0) {
    Error(geohash.PrecisionOutOfRange(precision: 0)) -> Nil
    _ -> should.be_true(False)
  }
}

pub fn encode_precision_too_high_test() -> Nil {
  let assert Ok(point) = latlng.new(lat: 0.0, lng: 0.0)
  case geohash.encode(point: point, precision: 13) {
    Error(geohash.PrecisionOutOfRange(precision: 13)) -> Nil
    _ -> should.be_true(False)
  }
}

// --- decode --------------------------------------------------------------

pub fn decode_wikipedia_test() -> Nil {
  let assert Ok(centre) = geohash.decode("ezs42")
  // The cell centre is at (42.6, -5.6) ± half-cell.
  approx_equal(latlng.lat(centre), 42.6, 0.05)
  |> should.be_true
  approx_equal(latlng.lng(centre), -5.6, 0.05)
  |> should.be_true
}

pub fn decode_empty_test() -> Nil {
  case geohash.decode("") {
    Error(geohash.EmptyHash) -> Nil
    _ -> should.be_true(False)
  }
}

pub fn decode_invalid_char_test() -> Nil {
  case geohash.decode("abc") {
    Error(geohash.InvalidCharacter(char: "a", position: 0)) -> Nil
    _ -> should.be_true(False)
  }
}

// --- round-trip ----------------------------------------------------------

pub fn round_trip_tokyo_test() -> Nil {
  let assert Ok(tokyo) = latlng.new(lat: 35.6812, lng: 139.7671)
  let assert Ok(hash) = geohash.encode(point: tokyo, precision: 9)
  let assert Ok(centre) = geohash.decode(hash)
  approx_equal(latlng.lat(centre), 35.6812, 0.0001)
  |> should.be_true
  approx_equal(latlng.lng(centre), 139.7671, 0.0001)
  |> should.be_true
}

pub fn decode_bounds_contains_original_test() -> Nil {
  let assert Ok(point) = latlng.new(lat: 35.6812, lng: 139.7671)
  let assert Ok(hash) = geohash.encode(point: point, precision: 6)
  let assert Ok(#(sw, ne)) = geohash.decode_bounds(hash: hash)
  let contains =
    latlng.lat(sw) <=. 35.6812
    && latlng.lat(ne) >=. 35.6812
    && latlng.lng(sw) <=. 139.7671
    && latlng.lng(ne) >=. 139.7671
  contains
  |> should.be_true
}

// --- neighbours ----------------------------------------------------------

pub fn neighbor_east_then_west_round_trip_test() -> Nil {
  // east(west(h)) == h for any non-boundary hash.
  let assert Ok(point) = latlng.new(lat: 12.0, lng: 34.0)
  let assert Ok(start) = geohash.encode(point: point, precision: 6)
  let assert Ok(east) = geohash.neighbor(hash: start, direction: geohash.East)
  let assert Ok(back) = geohash.neighbor(hash: east, direction: geohash.West)
  back
  |> should.equal(start)
}

pub fn neighbor_north_then_south_round_trip_test() -> Nil {
  // south(north(h)) == h.
  let assert Ok(point) = latlng.new(lat: 12.0, lng: 34.0)
  let assert Ok(start) = geohash.encode(point: point, precision: 6)
  let assert Ok(n) = geohash.neighbor(hash: start, direction: geohash.North)
  let assert Ok(back) = geohash.neighbor(hash: n, direction: geohash.South)
  back
  |> should.equal(start)
}

pub fn neighbor_decode_north_is_north_of_centre_test() -> Nil {
  // The northern neighbour's cell must lie north of the original
  // cell: its SW latitude should equal the original's NE latitude.
  let assert Ok(point) = latlng.new(lat: 35.0, lng: 135.0)
  let assert Ok(start) = geohash.encode(point: point, precision: 6)
  let assert Ok(#(_, ne_origin)) = geohash.decode_bounds(hash: start)
  let assert Ok(n) = geohash.neighbor(hash: start, direction: geohash.North)
  let assert Ok(#(sw_north, _)) = geohash.decode_bounds(hash: n)
  approx_equal(latlng.lat(sw_north), latlng.lat(ne_origin), 0.001)
  |> should.be_true
}

pub fn encode_at_35_135_matches_ngeohash_test() -> Nil {
  let assert Ok(point) = latlng.new(lat: 35.0, lng: 135.0)
  let assert Ok(hash) = geohash.encode(point: point, precision: 6)
  hash
  |> should.equal("wypzpg")
}

pub fn neighbors_around_test() -> Nil {
  let assert Ok(all) = geohash.neighbors(hash: "u4pruyd")
  // Each neighbour has the same length as the input.
  string.length(all.north)
  |> should.equal(7)
  string.length(all.south)
  |> should.equal(7)
  string.length(all.east)
  |> should.equal(7)
  string.length(all.west)
  |> should.equal(7)
}

pub fn neighbor_empty_hash_test() -> Nil {
  case geohash.neighbor(hash: "", direction: geohash.North) {
    Error(geohash.EmptyHash) -> Nil
    _ -> should.be_true(False)
  }
}
