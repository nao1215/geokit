import gleam/string
import gleeunit/should

import geokit
import geokit/geohash

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
  let assert Ok(point) = geokit.lat_lng(latitude: 42.6, longitude: -5.6)
  let assert Ok(hash) = geohash.encode(point: point, precision: 5)
  hash
  |> should.equal("ezs42")
}

pub fn encode_origin_test() -> Nil {
  // Issue #31: (0, 0) at precision 5 → "s0000". The equator and prime
  // meridian sit exactly on the recursive bisection midpoint, and the
  // canonical Wikipedia / `ngeohash` / `pygeohash` / `geohash.org`
  // convention uses `>=` at the midpoint so the bit goes to the upper
  // half. The previous output "7zzzz" came from a strict `>` and
  // disagreed with every other implementation.
  let assert Ok(origin) = geokit.lat_lng(latitude: 0.0, longitude: 0.0)
  let assert Ok(hash) = geohash.encode(point: origin, precision: 5)
  hash
  |> should.equal("s0000")
}

pub fn encode_high_precision_test() -> Nil {
  // (57.64911, 10.40744) at precision 11 → "u4pruydqqvj".
  let assert Ok(point) = geokit.lat_lng(latitude: 57.64911, longitude: 10.40744)
  let assert Ok(hash) = geohash.encode(point: point, precision: 11)
  hash
  |> should.equal("u4pruydqqvj")
}

pub fn encode_tokyo_test() -> Nil {
  // (35.6812, 139.7671) at precision 8 → "xn76urx6" (matches ngeohash).
  let assert Ok(tokyo) = geokit.lat_lng(latitude: 35.6812, longitude: 139.7671)
  let assert Ok(hash) = geohash.encode(point: tokyo, precision: 8)
  hash
  |> should.equal("xn76urx6")
}

pub fn encode_precision_too_low_test() -> Nil {
  let assert Ok(point) = geokit.lat_lng(latitude: 0.0, longitude: 0.0)
  case geohash.encode(point: point, precision: 0) {
    Error(geohash.PrecisionOutOfRange(precision: 0)) -> Nil
    _ -> should.be_true(False)
  }
}

pub fn encode_precision_too_high_test() -> Nil {
  let assert Ok(point) = geokit.lat_lng(latitude: 0.0, longitude: 0.0)
  case geohash.encode(point: point, precision: 13) {
    Error(geohash.PrecisionOutOfRange(precision: 13)) -> Nil
    _ -> should.be_true(False)
  }
}

// --- decode --------------------------------------------------------------

pub fn decode_wikipedia_test() -> Nil {
  let assert Ok(centre) = geohash.decode("ezs42")
  // The cell centre is at (42.6, -5.6) ± half-cell.
  approx_equal(geokit.latitude(centre), 42.6, 0.05)
  |> should.be_true
  approx_equal(geokit.longitude(centre), -5.6, 0.05)
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

// --- case insensitivity (issue #2) --------------------------------------

pub fn decode_accepts_upper_case_test() -> Nil {
  let assert Ok(lower) = geohash.decode("wypzpg")
  let assert Ok(upper) = geohash.decode("WYPZPG")
  lower |> should.equal(upper)
}

pub fn decode_accepts_mixed_case_test() -> Nil {
  let assert Ok(lower) = geohash.decode("xn76urx6")
  let assert Ok(mixed) = geohash.decode("Xn76UrX6")
  lower |> should.equal(mixed)
}

pub fn neighbor_accepts_upper_case_test() -> Nil {
  let assert Ok(lower) =
    geohash.neighbor(hash: "wypzpg", direction: geohash.North)
  let assert Ok(upper) =
    geohash.neighbor(hash: "WYPZPG", direction: geohash.North)
  upper
  |> should.equal(lower)
}

pub fn neighbors_accepts_upper_case_test() -> Nil {
  let assert Ok(lower) = geohash.neighbors(hash: "wypzpg")
  let assert Ok(upper) = geohash.neighbors(hash: "WYPZPG")
  upper.north
  |> should.equal(lower.north)
  upper.east
  |> should.equal(lower.east)
}

// --- round-trip ----------------------------------------------------------

pub fn round_trip_tokyo_test() -> Nil {
  let assert Ok(tokyo) = geokit.lat_lng(latitude: 35.6812, longitude: 139.7671)
  let assert Ok(hash) = geohash.encode(point: tokyo, precision: 9)
  let assert Ok(centre) = geohash.decode(hash)
  approx_equal(geokit.latitude(centre), 35.6812, 0.0001)
  |> should.be_true
  approx_equal(geokit.longitude(centre), 139.7671, 0.0001)
  |> should.be_true
}

pub fn decode_bounds_contains_original_test() -> Nil {
  let assert Ok(point) = geokit.lat_lng(latitude: 35.6812, longitude: 139.7671)
  let assert Ok(hash) = geohash.encode(point: point, precision: 6)
  let assert Ok(#(sw, ne)) = geohash.decode_bounds(hash: hash)
  let contains =
    geokit.latitude(sw) <=. 35.6812
    && geokit.latitude(ne) >=. 35.6812
    && geokit.longitude(sw) <=. 139.7671
    && geokit.longitude(ne) >=. 139.7671
  contains
  |> should.be_true
}

// --- neighbours ----------------------------------------------------------

pub fn neighbor_east_then_west_round_trip_test() -> Nil {
  // east(west(h)) == h for any non-boundary hash.
  let assert Ok(point) = geokit.lat_lng(latitude: 12.0, longitude: 34.0)
  let assert Ok(start) = geohash.encode(point: point, precision: 6)
  let assert Ok(east) = geohash.neighbor(hash: start, direction: geohash.East)
  let assert Ok(back) = geohash.neighbor(hash: east, direction: geohash.West)
  back
  |> should.equal(start)
}

pub fn neighbor_north_then_south_round_trip_test() -> Nil {
  // south(north(h)) == h.
  let assert Ok(point) = geokit.lat_lng(latitude: 12.0, longitude: 34.0)
  let assert Ok(start) = geohash.encode(point: point, precision: 6)
  let assert Ok(n) = geohash.neighbor(hash: start, direction: geohash.North)
  let assert Ok(back) = geohash.neighbor(hash: n, direction: geohash.South)
  back
  |> should.equal(start)
}

pub fn neighbor_decode_north_is_north_of_centre_test() -> Nil {
  // The northern neighbour's cell must lie north of the original
  // cell: its SW latitude should equal the original's NE latitude.
  let assert Ok(point) = geokit.lat_lng(latitude: 35.0, longitude: 135.0)
  let assert Ok(start) = geohash.encode(point: point, precision: 6)
  let assert Ok(#(_, ne_origin)) = geohash.decode_bounds(hash: start)
  let assert Ok(n) = geohash.neighbor(hash: start, direction: geohash.North)
  let assert Ok(#(sw_north, _)) = geohash.decode_bounds(hash: n)
  approx_equal(geokit.latitude(sw_north), geokit.latitude(ne_origin), 0.001)
  |> should.be_true
}

pub fn encode_at_35_135_matches_ngeohash_test() -> Nil {
  // Issue #31: lng = 135 lands exactly on the third bisection
  // midpoint ([90, 180] → mid 135), so the canonical `>=` convention
  // picks a different bit than the previous strict `>`. The test
  // value below is the post-fix output, which matches ngeohash.
  let assert Ok(point) = geokit.lat_lng(latitude: 35.0, longitude: 135.0)
  let assert Ok(hash) = geohash.encode(point: point, precision: 6)
  hash
  |> should.equal("xn0p05")
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

// --- antimeridian wrap --------------------------------------------------

pub fn neighbor_west_wraps_across_antimeridian_test() -> Nil {
  // ngeohash.neighbor(hash, [0, -1]) for cells on the western edge.
  geohash.neighbor(hash: "0", direction: geohash.West)
  |> should.equal(Ok("p"))
  geohash.neighbor(hash: "00", direction: geohash.West)
  |> should.equal(Ok("pb"))
  geohash.neighbor(hash: "0000", direction: geohash.West)
  |> should.equal(Ok("pbpb"))
  geohash.neighbor(hash: "2", direction: geohash.West)
  |> should.equal(Ok("r"))
  geohash.neighbor(hash: "8", direction: geohash.West)
  |> should.equal(Ok("x"))
  geohash.neighbor(hash: "b", direction: geohash.West)
  |> should.equal(Ok("z"))
}

pub fn neighbor_east_wraps_across_antimeridian_test() -> Nil {
  geohash.neighbor(hash: "pbpb", direction: geohash.East)
  |> should.equal(Ok("0000"))
  geohash.neighbor(hash: "p", direction: geohash.East)
  |> should.equal(Ok("0"))
}

pub fn neighbor_pole_still_fails_test() -> Nil {
  geohash.neighbor(hash: "b", direction: geohash.North)
  |> should.equal(Error(geohash.EmptyHash))
  geohash.neighbor(hash: "0", direction: geohash.South)
  |> should.equal(Error(geohash.EmptyHash))
}

// --- input validation ---------------------------------------------------

pub fn neighbor_rejects_invalid_char_in_prefix_test() -> Nil {
  geohash.neighbor(hash: "a0", direction: geohash.North)
  |> should.equal(Error(geohash.InvalidCharacter(char: "a", position: 0)))
  geohash.neighbor(hash: "u4i0", direction: geohash.East)
  |> should.equal(Error(geohash.InvalidCharacter(char: "i", position: 2)))
}

pub fn neighbor_rejects_invalid_last_char_test() -> Nil {
  geohash.neighbor(hash: "u4o", direction: geohash.South)
  |> should.equal(Error(geohash.InvalidCharacter(char: "o", position: 2)))
}

pub fn neighbors_rejects_invalid_char_test() -> Nil {
  geohash.neighbors(hash: "xl76u")
  |> should.equal(Error(geohash.InvalidCharacter(char: "l", position: 1)))
}
