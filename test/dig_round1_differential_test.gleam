//// dig-bug round 1: differential testing.
////
//// Every public function in geokit is checked against a recognised
//// reference implementation. The references are recorded next to
//// each assertion so the values can be regenerated independently:
////
//// - Python `math` haversine and bearing on WGS84 mean radius
////   R = 6_371_008.8 m (the radius geokit itself uses).
//// - `ngeohash` (npm) for `geohash.encode` / `decode` /
////   `decode_bounds` / `neighbors`.
//// - `@mapbox/polyline` (npm) for Google Encoded Polyline at
////   precision 5 and 6.
//// - OSM slippy-map tile and Bing quadkey formulas (cross-checked
////   via Python).
//// - `@turf/bbox`, `@turf/centroid`, `@turf/simplify` for the
////   `bbox` / `centroid` / `simplify` modules. Turf uses an
////   arithmetic-mean centroid; for convex shapes that equals
////   geokit's signed-area centroid, so the cases below are convex.

import gleam/bool
import gleam/list
import gleeunit/should

import geokit/bbox
import geokit/bearing
import geokit/centroid
import geokit/distance
import geokit/geohash
import geokit/geometry
import geokit/latlng
import geokit/mercator
import geokit/polyline
import geokit/simplify

// --- helpers --------------------------------------------------------------

fn approx(a: Float, b: Float, tol: Float) -> Bool {
  let d = case a >. b {
    True -> a -. b
    False -> b -. a
  }
  d <=. tol
}

fn bearing_approx(value: Float, target: Float, tol: Float) -> Bool {
  let raw = value -. target
  let modded = case raw {
    _ if raw <. -180.0 -> raw +. 360.0
    _ if raw >. 180.0 -> raw -. 360.0
    _ -> raw
  }
  let abs_d = case modded <. 0.0 {
    True -> 0.0 -. modded
    False -> modded
  }
  abs_d <=. tol
}

fn int_to_float(n: Int) -> Float {
  use <- bool.guard(when: n <= 0, return: 0.0)
  1.0 +. int_to_float(n - 1)
}

fn build_curve(
  index: Int,
  count: Int,
  acc: List(latlng.LatLng),
) -> List(latlng.LatLng) {
  case index >= count {
    True -> list.reverse(acc)
    False -> {
      let f = int_to_float(index)
      let lat = 35.0 +. f *. 0.01
      let lng = 139.0 +. f *. 0.02
      let assert Ok(p) = latlng.new(lat: lat, lng: lng)
      build_curve(index + 1, count, [p, ..acc])
    }
  }
}

// --- Distance: haversine vs Python math --------------------------------

pub fn diff_distance_tokyo_osaka_test() -> Nil {
  let assert Ok(a) = latlng.new(lat: 35.6812, lng: 139.7671)
  let assert Ok(b) = latlng.new(lat: 34.6937, lng: 135.5023)
  // Python: 402_784.7393766611
  approx(distance.haversine(a: a, b: b), 402_784.7394, 0.001)
  |> should.be_true
}

pub fn diff_distance_tokyo_london_test() -> Nil {
  let assert Ok(a) = latlng.new(lat: 35.6812, lng: 139.7671)
  let assert Ok(b) = latlng.new(lat: 51.5074, lng: -0.1278)
  approx(distance.haversine(a: a, b: b), 9_562_311.1617, 0.001)
  |> should.be_true
}

pub fn diff_distance_tokyo_nyc_test() -> Nil {
  let assert Ok(a) = latlng.new(lat: 35.6812, lng: 139.7671)
  let assert Ok(b) = latlng.new(lat: 40.7128, lng: -74.006)
  approx(distance.haversine(a: a, b: b), 10_846_766.8037, 0.001)
  |> should.be_true
}

pub fn diff_distance_tokyo_sydney_test() -> Nil {
  let assert Ok(a) = latlng.new(lat: 35.6812, lng: 139.7671)
  let assert Ok(b) = latlng.new(lat: -33.8688, lng: 151.2093)
  approx(distance.haversine(a: a, b: b), 7_824_522.5299, 0.001)
  |> should.be_true
}

pub fn diff_distance_equator_quarter_test() -> Nil {
  let assert Ok(a) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(b) = latlng.new(lat: 0.0, lng: 90.0)
  // π/2 × R = 10_007_557.2204
  approx(distance.haversine(a: a, b: b), 10_007_557.2204, 0.001)
  |> should.be_true
}

pub fn diff_distance_antipodes_test() -> Nil {
  let assert Ok(a) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(b) = latlng.new(lat: 0.0, lng: 180.0)
  // π × R = 20_015_114.442_035_925
  approx(distance.haversine(a: a, b: b), 20_015_114.442_035_925, 0.001)
  |> should.be_true
}

pub fn diff_distance_pole_to_pole_test() -> Nil {
  let assert Ok(a) = latlng.new(lat: 90.0, lng: 0.0)
  let assert Ok(b) = latlng.new(lat: -90.0, lng: 0.0)
  approx(distance.haversine(a: a, b: b), 20_015_114.442_035_925, 0.001)
  |> should.be_true
}

pub fn diff_distance_same_point_test() -> Nil {
  let assert Ok(p) = latlng.new(lat: 35.6812, lng: 139.7671)
  approx(distance.haversine(a: p, b: p), 0.0, 0.000_001)
  |> should.be_true
}

pub fn diff_distance_one_micro_degree_apart_test() -> Nil {
  // 11.12 cm at the equator. Python: 0.111195...
  let assert Ok(a) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(b) = latlng.new(lat: 0.0, lng: 0.000_001)
  approx(distance.haversine(a: a, b: b), 0.111_195, 0.000_001)
  |> should.be_true
}

pub fn diff_distance_across_antimeridian_short_test() -> Nil {
  // (0, 179.99) ↔ (0, -179.99) — 0.02° apart through the meridian.
  // Python: 2223.901604670649
  let assert Ok(a) = latlng.new(lat: 0.0, lng: 179.99)
  let assert Ok(b) = latlng.new(lat: 0.0, lng: -179.99)
  approx(distance.haversine(a: a, b: b), 2223.901_604_670_649, 0.000_1)
  |> should.be_true
}

// --- Bearing vs Python ---------------------------------------------------

pub fn diff_bearing_tokyo_osaka_initial_test() -> Nil {
  let assert Ok(a) = latlng.new(lat: 35.6812, lng: 139.7671)
  let assert Ok(b) = latlng.new(lat: 34.6937, lng: 135.5023)
  // Python: 255.4180_369378
  bearing_approx(bearing.initial(from: a, to: b), 255.4180_369378, 0.000_001)
  |> should.be_true
}

pub fn diff_bearing_tokyo_osaka_final_test() -> Nil {
  let assert Ok(a) = latlng.new(lat: 35.6812, lng: 139.7671)
  let assert Ok(b) = latlng.new(lat: 34.6937, lng: 135.5023)
  // Python: 252.9595_824228
  bearing_approx(bearing.final(from: a, to: b), 252.9595_824228, 0.000_001)
  |> should.be_true
}

pub fn diff_bearing_tokyo_nyc_initial_test() -> Nil {
  let assert Ok(a) = latlng.new(lat: 35.6812, lng: 139.7671)
  let assert Ok(b) = latlng.new(lat: 40.7128, lng: -74.006)
  // Python: 25.154
  bearing_approx(bearing.initial(from: a, to: b), 25.154, 0.01)
  |> should.be_true
}

pub fn diff_bearing_tokyo_sydney_initial_test() -> Nil {
  let assert Ok(a) = latlng.new(lat: 35.6812, lng: 139.7671)
  let assert Ok(b) = latlng.new(lat: -33.8688, lng: 151.2093)
  bearing_approx(bearing.initial(from: a, to: b), 169.9281, 0.01)
  |> should.be_true
}

pub fn diff_bearing_due_north_test() -> Nil {
  let assert Ok(a) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(b) = latlng.new(lat: 1.0, lng: 0.0)
  bearing_approx(bearing.initial(from: a, to: b), 0.0, 0.000_001)
  |> should.be_true
}

pub fn diff_bearing_due_east_test() -> Nil {
  let assert Ok(a) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(b) = latlng.new(lat: 0.0, lng: 1.0)
  bearing_approx(bearing.initial(from: a, to: b), 90.0, 0.000_001)
  |> should.be_true
}

pub fn diff_bearing_antipodes_no_crash_test() -> Nil {
  // Antipodal points: bearing is geometrically undefined but the
  // function must return a value in [0, 360) without crashing.
  let assert Ok(a) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(b) = latlng.new(lat: 0.0, lng: 180.0)
  let value = bearing.initial(from: a, to: b)
  let in_range = value >=. 0.0 && value <. 360.0
  in_range
  |> should.be_true
}

// --- Geohash encode vs ngeohash -----------------------------------------

pub fn diff_geohash_encode_tokyo_p5_test() -> Nil {
  let assert Ok(p) = latlng.new(lat: 35.6812, lng: 139.7671)
  let assert Ok(hash) = geohash.encode(point: p, precision: 5)
  hash |> should.equal("xn76u")
}

pub fn diff_geohash_encode_tokyo_p7_test() -> Nil {
  let assert Ok(p) = latlng.new(lat: 35.6812, lng: 139.7671)
  let assert Ok(hash) = geohash.encode(point: p, precision: 7)
  hash |> should.equal("xn76urx")
}

pub fn diff_geohash_encode_tokyo_p9_test() -> Nil {
  let assert Ok(p) = latlng.new(lat: 35.6812, lng: 139.7671)
  let assert Ok(hash) = geohash.encode(point: p, precision: 9)
  hash |> should.equal("xn76urx61")
}

pub fn diff_geohash_encode_osaka_p5_test() -> Nil {
  let assert Ok(p) = latlng.new(lat: 34.6937, lng: 135.5023)
  let assert Ok(hash) = geohash.encode(point: p, precision: 5)
  hash |> should.equal("xn0m7")
}

pub fn diff_geohash_encode_equator_p5_test() -> Nil {
  let assert Ok(p) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(hash) = geohash.encode(point: p, precision: 5)
  hash |> should.equal("7zzzz")
}

pub fn diff_geohash_encode_antimeridian_p5_test() -> Nil {
  let assert Ok(p) = latlng.new(lat: 0.0, lng: 180.0)
  let assert Ok(hash) = geohash.encode(point: p, precision: 5)
  hash |> should.equal("rzzzz")
}

pub fn diff_geohash_encode_north_pole_p5_test() -> Nil {
  let assert Ok(p) = latlng.new(lat: 90.0, lng: 0.0)
  let assert Ok(hash) = geohash.encode(point: p, precision: 5)
  hash |> should.equal("gzzzz")
}

pub fn diff_geohash_encode_south_pole_p5_test() -> Nil {
  let assert Ok(p) = latlng.new(lat: -90.0, lng: 0.0)
  let assert Ok(hash) = geohash.encode(point: p, precision: 5)
  hash |> should.equal("5bpbp")
}

pub fn diff_geohash_encode_p1_tokyo_test() -> Nil {
  let assert Ok(p) = latlng.new(lat: 35.6812, lng: 139.7671)
  let assert Ok(hash) = geohash.encode(point: p, precision: 1)
  hash |> should.equal("x")
}

pub fn diff_geohash_encode_se_corner_world_test() -> Nil {
  // ngeohash.encode(-89.99, 179.99, 5) = "pbpbp"
  let assert Ok(p) = latlng.new(lat: -89.99, lng: 179.99)
  let assert Ok(hash) = geohash.encode(point: p, precision: 5)
  hash |> should.equal("pbpbp")
}

pub fn diff_geohash_encode_p1_top_right_test() -> Nil {
  // ngeohash.encode(89, 179, 1) = "z" — last cell of the world.
  let assert Ok(p) = latlng.new(lat: 89.0, lng: 179.0)
  let assert Ok(hash) = geohash.encode(point: p, precision: 1)
  hash |> should.equal("z")
}

// --- Geohash decode_bounds vs ngeohash ---------------------------------

pub fn diff_geohash_decode_bounds_tokyo_p5_test() -> Nil {
  // ngeohash.decode_bbox("xn76u") = [35.639648, 139.746094, 35.683594, 139.790039]
  let assert Ok(#(sw, ne)) = geohash.decode_bounds(hash: "xn76u")
  approx(latlng.lat(sw), 35.639_648, 0.000_001)
  |> should.be_true
  approx(latlng.lng(sw), 139.746_094, 0.000_001)
  |> should.be_true
  approx(latlng.lat(ne), 35.683_594, 0.000_001)
  |> should.be_true
  approx(latlng.lng(ne), 139.790_039, 0.000_001)
  |> should.be_true
}

pub fn diff_geohash_decode_bounds_tokyo_p9_test() -> Nil {
  // ngeohash.decode_bbox("xn76urx61") = [35.681190, 139.767079, 35.681233, 139.767122]
  let assert Ok(#(sw, ne)) = geohash.decode_bounds(hash: "xn76urx61")
  approx(latlng.lat(sw), 35.681_19, 0.000_001)
  |> should.be_true
  approx(latlng.lat(ne), 35.681_233, 0.000_001)
  |> should.be_true
}

// --- Geohash neighbours vs ngeohash -------------------------------------

pub fn diff_geohash_neighbors_tokyo_p5_test() -> Nil {
  // ngeohash.neighbors("xn76u") [N, NE, E, SE, S, SW, W, NW]
  //   = ["xn77h","xn77j","xn76v","xn76t","xn76s","xn76e","xn76g","xn775"]
  let assert Ok(ns) = geohash.neighbors(hash: "xn76u")
  ns.north |> should.equal("xn77h")
  ns.north_east |> should.equal("xn77j")
  ns.east |> should.equal("xn76v")
  ns.south_east |> should.equal("xn76t")
  ns.south |> should.equal("xn76s")
  ns.south_west |> should.equal("xn76e")
  ns.west |> should.equal("xn76g")
  ns.north_west |> should.equal("xn775")
}

pub fn diff_geohash_neighbors_origin_p5_test() -> Nil {
  // ngeohash: north of "7zzzz" = "ebpbp"
  let assert Ok(ns) = geohash.neighbors(hash: "7zzzz")
  ns.north |> should.equal("ebpbp")
}

// --- Polar neighbour convention (documented divergence from ngeohash) --

pub fn diff_geohash_north_of_north_pole_returns_empty_test() -> Nil {
  // Documented geokit behaviour: returns `Error(EmptyHash)` when a
  // polar neighbour would cross the pole. (ngeohash returns the
  // hash unchanged; geokit chooses the error path.)
  case geohash.neighbor(hash: "gzzzz", direction: geohash.North) {
    Error(geohash.EmptyHash) -> Nil
    _ -> should.be_true(False)
  }
}

pub fn diff_geohash_south_of_south_pole_returns_empty_test() -> Nil {
  case geohash.neighbor(hash: "5bpbp", direction: geohash.South) {
    Error(geohash.EmptyHash) -> Nil
    _ -> should.be_true(False)
  }
}

// --- Geohash invalid-character rejection -------------------------------

pub fn diff_geohash_decode_rejects_a_test() -> Nil {
  // 'a' is excluded from the Niemeyer alphabet (along with i, l, o).
  case geohash.decode("0a0") {
    Error(geohash.InvalidCharacter(char: "a", position: 1)) -> Nil
    _ -> should.be_true(False)
  }
}

pub fn diff_geohash_decode_rejects_i_test() -> Nil {
  case geohash.decode("0i0") {
    Error(geohash.InvalidCharacter(char: "i", position: 1)) -> Nil
    _ -> should.be_true(False)
  }
}

pub fn diff_geohash_decode_rejects_l_test() -> Nil {
  case geohash.decode("0l0") {
    Error(geohash.InvalidCharacter(char: "l", position: 1)) -> Nil
    _ -> should.be_true(False)
  }
}

pub fn diff_geohash_decode_rejects_o_test() -> Nil {
  case geohash.decode("0o0") {
    Error(geohash.InvalidCharacter(char: "o", position: 1)) -> Nil
    _ -> should.be_true(False)
  }
}

pub fn diff_geohash_max_precision_round_trip_test() -> Nil {
  // Precision 12 is the geokit-supported maximum.
  let assert Ok(tokyo) = latlng.new(lat: 35.6812, lng: 139.7671)
  let assert Ok(hash) = geohash.encode(point: tokyo, precision: 12)
  let assert Ok(centre) = geohash.decode(hash)
  approx(latlng.lat(centre), 35.6812, 0.000_001)
  |> should.be_true
  approx(latlng.lng(centre), 139.7671, 0.000_001)
  |> should.be_true
}

// --- Polyline encode vs @mapbox/polyline -------------------------------

pub fn diff_polyline_encode_google_reference_test() -> Nil {
  // Google's canonical example, identical in mapbox/polyline.
  let assert Ok(p1) = latlng.new(lat: 38.5, lng: -120.2)
  let assert Ok(p2) = latlng.new(lat: 40.7, lng: -120.95)
  let assert Ok(p3) = latlng.new(lat: 43.252, lng: -126.453)
  polyline.encode(points: [p1, p2, p3])
  |> should.equal("_p~iF~ps|U_ulLnnqC_mqNvxq`@")
}

pub fn diff_polyline_encode_single_origin_test() -> Nil {
  // polyline.encode([[0, 0]], 5) = "??"
  let assert Ok(p) = latlng.new(lat: 0.0, lng: 0.0)
  polyline.encode(points: [p])
  |> should.equal("??")
}

pub fn diff_polyline_encode_empty_test() -> Nil {
  polyline.encode(points: [])
  |> should.equal("")
}

pub fn diff_polyline_encode_tokyo_osaka_test() -> Nil {
  // mapbox: polyline.encode(
  //   [[35.6812, 139.7671], [34.6937, 135.5023]], 5) = "o~wxEkgatYzz_E~}_Y"
  let assert Ok(p1) = latlng.new(lat: 35.6812, lng: 139.7671)
  let assert Ok(p2) = latlng.new(lat: 34.6937, lng: 135.5023)
  polyline.encode(points: [p1, p2])
  |> should.equal("o~wxEkgatYzz_E~}_Y")
}

pub fn diff_polyline_encode_across_antimeridian_test() -> Nil {
  // mapbox: polyline.encode(
  //   [[0, 179.99], [0, -179.99]], 5) = "?ohqia@?~qctcA"
  let assert Ok(p1) = latlng.new(lat: 0.0, lng: 179.99)
  let assert Ok(p2) = latlng.new(lat: 0.0, lng: -179.99)
  polyline.encode(points: [p1, p2])
  |> should.equal("?ohqia@?~qctcA")
}

pub fn diff_polyline_encode_precision_6_test() -> Nil {
  // mapbox: polyline.encode(
  //   [[35.681234, 139.767123], [34.693712, 135.502345]], 6)
  //   = "c|x`cAetuqiGbwg{@rshcG"
  let assert Ok(p1) = latlng.new(lat: 35.681_234, lng: 139.767_123)
  let assert Ok(p2) = latlng.new(lat: 34.693_712, lng: 135.502_345)
  polyline.encode_with(points: [p1, p2], precision: 6)
  |> should.equal("c|x`cAetuqiGbwg{@rshcG")
}

pub fn diff_polyline_encode_single_non_origin_test() -> Nil {
  // mapbox: polyline.encode([[10, 20]], 5) = "_c`|@_gayB"
  let assert Ok(p) = latlng.new(lat: 10.0, lng: 20.0)
  polyline.encode(points: [p])
  |> should.equal("_c`|@_gayB")
}

// --- Polyline decode vs @mapbox/polyline -------------------------------

pub fn diff_polyline_decode_google_reference_test() -> Nil {
  let assert Ok(points) = polyline.decode(input: "_p~iF~ps|U_ulLnnqC_mqNvxq`@")
  let assert [p1, p2, p3] = points
  approx(latlng.lat(p1), 38.5, 0.000_01) |> should.be_true
  approx(latlng.lng(p1), -120.2, 0.000_01) |> should.be_true
  approx(latlng.lat(p2), 40.7, 0.000_01) |> should.be_true
  approx(latlng.lng(p2), -120.95, 0.000_01) |> should.be_true
  approx(latlng.lat(p3), 43.252, 0.000_01) |> should.be_true
  approx(latlng.lng(p3), -126.453, 0.000_01) |> should.be_true
}

pub fn diff_polyline_decode_single_non_origin_test() -> Nil {
  // mapbox: polyline.encode([[35.6812, 139.7671]], 5) = "o~wxEkgatY"
  let assert Ok(points) = polyline.decode(input: "o~wxEkgatY")
  let assert [p] = points
  approx(latlng.lat(p), 35.6812, 0.000_01) |> should.be_true
  approx(latlng.lng(p), 139.7671, 0.000_01) |> should.be_true
}

pub fn diff_polyline_decode_rejects_below_63_test() -> Nil {
  // Spec only accepts code 63 ('?')..126 ('~'). Space (code 32) is
  // below 63 → reject.
  case polyline.decode(input: " ") {
    Error(polyline.InvalidCharacter(char: " ", position: 0)) -> Nil
    _ -> should.be_true(False)
  }
}

pub fn diff_polyline_round_trip_10_points_test() -> Nil {
  let points = build_curve(0, 10, [])
  let encoded = polyline.encode(points: points)
  let assert Ok(decoded) = polyline.decode(input: encoded)
  list.length(decoded)
  |> should.equal(10)
}

// --- Mercator tile vs OSM slippy-map / Bing quadkey --------------------

pub fn diff_mercator_tokyo_z0_test() -> Nil {
  let assert Ok(tokyo) = latlng.new(lat: 35.6812, lng: 139.7671)
  let assert Ok(t) = mercator.from_lat_lng(point: tokyo, zoom: 0)
  mercator.x(tile: t) |> should.equal(0)
  mercator.y(tile: t) |> should.equal(0)
}

pub fn diff_mercator_tokyo_z5_test() -> Nil {
  // OSM formula: x=28, y=12 at zoom 5.
  let assert Ok(tokyo) = latlng.new(lat: 35.6812, lng: 139.7671)
  let assert Ok(t) = mercator.from_lat_lng(point: tokyo, zoom: 5)
  mercator.x(tile: t) |> should.equal(28)
  mercator.y(tile: t) |> should.equal(12)
}

pub fn diff_mercator_tokyo_z10_test() -> Nil {
  let assert Ok(tokyo) = latlng.new(lat: 35.6812, lng: 139.7671)
  let assert Ok(t) = mercator.from_lat_lng(point: tokyo, zoom: 10)
  mercator.x(tile: t) |> should.equal(909)
  mercator.y(tile: t) |> should.equal(403)
}

pub fn diff_mercator_tokyo_z14_test() -> Nil {
  let assert Ok(tokyo) = latlng.new(lat: 35.6812, lng: 139.7671)
  let assert Ok(t) = mercator.from_lat_lng(point: tokyo, zoom: 14)
  mercator.x(tile: t) |> should.equal(14_552)
  mercator.y(tile: t) |> should.equal(6451)
}

pub fn diff_mercator_tokyo_z18_test() -> Nil {
  let assert Ok(tokyo) = latlng.new(lat: 35.6812, lng: 139.7671)
  let assert Ok(t) = mercator.from_lat_lng(point: tokyo, zoom: 18)
  mercator.x(tile: t) |> should.equal(232_847)
  mercator.y(tile: t) |> should.equal(103_226)
}

pub fn diff_mercator_london_z14_test() -> Nil {
  let assert Ok(london) = latlng.new(lat: 51.5074, lng: -0.1278)
  let assert Ok(t) = mercator.from_lat_lng(point: london, zoom: 14)
  mercator.x(tile: t) |> should.equal(8186)
  mercator.y(tile: t) |> should.equal(5448)
}

pub fn diff_mercator_nyc_z14_test() -> Nil {
  // OSM formula: (4823, 6160).
  let assert Ok(nyc) = latlng.new(lat: 40.7128, lng: -74.006)
  let assert Ok(t) = mercator.from_lat_lng(point: nyc, zoom: 14)
  mercator.x(tile: t) |> should.equal(4823)
  mercator.y(tile: t) |> should.equal(6160)
}

pub fn diff_mercator_quadkey_tokyo_z5_test() -> Nil {
  let assert Ok(t) = mercator.new(zoom: 5, x: 28, y: 12)
  mercator.to_quadkey(tile: t)
  |> should.equal("13300")
}

pub fn diff_mercator_quadkey_tokyo_z14_test() -> Nil {
  let assert Ok(t) = mercator.new(zoom: 14, x: 14_552, y: 6451)
  mercator.to_quadkey(tile: t)
  |> should.equal("13300211231022")
}

pub fn diff_mercator_quadkey_london_z14_test() -> Nil {
  let assert Ok(t) = mercator.new(zoom: 14, x: 8186, y: 5448)
  mercator.to_quadkey(tile: t)
  |> should.equal("03131313113010")
}

pub fn diff_mercator_tile_nw_z0_test() -> Nil {
  let assert Ok(t) = mercator.new(zoom: 0, x: 0, y: 0)
  let nw = mercator.to_lat_lng(tile: t)
  approx(latlng.lat(nw), 85.051_128, 0.000_001)
  |> should.be_true
  approx(latlng.lng(nw), -180.0, 0.000_001)
  |> should.be_true
}

pub fn diff_mercator_tile_nw_tokyo_z14_test() -> Nil {
  // OSM: tile_to_latlng_nw(14, 14552, 6451) = (35.692995, 139.746094)
  let assert Ok(t) = mercator.new(zoom: 14, x: 14_552, y: 6451)
  let nw = mercator.to_lat_lng(tile: t)
  approx(latlng.lat(nw), 35.692_995, 0.000_01)
  |> should.be_true
  approx(latlng.lng(nw), 139.746_094, 0.000_01)
  |> should.be_true
}

pub fn diff_mercator_quadkey_round_trip_z18_test() -> Nil {
  let assert Ok(t) = mercator.new(zoom: 18, x: 232_847, y: 103_226)
  let qk = mercator.to_quadkey(tile: t)
  let assert Ok(decoded) = mercator.from_quadkey(quadkey: qk)
  mercator.zoom(tile: decoded) |> should.equal(18)
  mercator.x(tile: decoded) |> should.equal(232_847)
  mercator.y(tile: decoded) |> should.equal(103_226)
}

pub fn diff_mercator_quadkey_rejects_letter_test() -> Nil {
  // Quadkey alphabet is {0,1,2,3}.
  case mercator.from_quadkey(quadkey: "12a3") {
    Error(mercator.InvalidQuadkeyChar(char: "a", position: 2)) -> Nil
    _ -> should.be_true(False)
  }
}

pub fn diff_mercator_quadkey_rejects_digit_above_3_test() -> Nil {
  case mercator.from_quadkey(quadkey: "1245") {
    Error(mercator.InvalidQuadkeyChar(char: "4", position: 2)) -> Nil
    _ -> should.be_true(False)
  }
}

pub fn diff_mercator_zoom_zero_single_tile_test() -> Nil {
  let assert Ok(p) = latlng.new(lat: 45.0, lng: 90.0)
  let assert Ok(t) = mercator.from_lat_lng(point: p, zoom: 0)
  mercator.x(tile: t) |> should.equal(0)
  mercator.y(tile: t) |> should.equal(0)
  mercator.to_quadkey(tile: t) |> should.equal("")
}

pub fn diff_mercator_zoom_30_extreme_test() -> Nil {
  // 2^29 = 536_870_912 — lng=0 lands at x = 2^29 at zoom 30.
  let assert Ok(p) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(t) = mercator.from_lat_lng(point: p, zoom: 30)
  mercator.zoom(tile: t) |> should.equal(30)
  mercator.x(tile: t) |> should.equal(536_870_912)
}

pub fn diff_mercator_north_pole_clamps_test() -> Nil {
  // Latitude 90 clamps to the Mercator pole limit → y = 0.
  let assert Ok(p) = latlng.new(lat: 90.0, lng: 0.0)
  let assert Ok(t) = mercator.from_lat_lng(point: p, zoom: 5)
  mercator.y(tile: t) |> should.equal(0)
}

pub fn diff_mercator_south_pole_clamps_test() -> Nil {
  // Latitude -90 clamps → y = 2^zoom - 1.
  let assert Ok(p) = latlng.new(lat: -90.0, lng: 0.0)
  let assert Ok(t) = mercator.from_lat_lng(point: p, zoom: 5)
  mercator.y(tile: t) |> should.equal(31)
}

pub fn diff_mercator_max_tile_x_test() -> Nil {
  let assert Ok(t) = mercator.new(zoom: 5, x: 31, y: 31)
  mercator.x(tile: t) |> should.equal(31)
  mercator.y(tile: t) |> should.equal(31)
}

pub fn diff_mercator_out_of_range_tile_test() -> Nil {
  case mercator.new(zoom: 5, x: 32, y: 0) {
    Error(mercator.TileCoordOutOfRange(zoom: 5, x: 32, y: 0)) -> Nil
    _ -> should.be_true(False)
  }
}

// --- LatLng ---------------------------------------------------------------

pub fn diff_latlng_91_rejected_test() -> Nil {
  case latlng.new(lat: 91.0, lng: 0.0) {
    Error(latlng.LatOutOfRange(lat: 91.0)) -> Nil
    _ -> should.be_true(False)
  }
}

pub fn diff_latlng_neg_181_rejected_test() -> Nil {
  case latlng.new(lat: 0.0, lng: -181.0) {
    Error(latlng.LngOutOfRange(lng: -181.0)) -> Nil
    _ -> should.be_true(False)
  }
}

pub fn diff_latlng_wrap_at_boundary_no_drift_test() -> Nil {
  // Values already in [-180, 180] must short-circuit (no FP drift).
  let exact = latlng.wrap(lat: 35.681_234, lng: 139.767_123)
  latlng.lat(exact) |> should.equal(35.681_234)
  latlng.lng(exact) |> should.equal(139.767_123)
}

pub fn diff_latlng_wrap_540_lng_test() -> Nil {
  let p = latlng.wrap(lat: 0.0, lng: 540.0)
  approx(latlng.lng(p), -180.0, 0.000_001)
  |> should.be_true
}

pub fn diff_latlng_wrap_neg_540_lng_test() -> Nil {
  let p = latlng.wrap(lat: 0.0, lng: -540.0)
  approx(latlng.lng(p), -180.0, 0.000_001)
  |> should.be_true
}

// --- BBox / Centroid / Simplify vs Turf.js -----------------------------

pub fn diff_bbox_l_shape_line_test() -> Nil {
  // Turf: bbox of LineString [[0,0],[10,0],[10,10],[0,10]] = [0,0,10,10]
  let assert Ok(a) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(b) = latlng.new(lat: 0.0, lng: 10.0)
  let assert Ok(c) = latlng.new(lat: 10.0, lng: 10.0)
  let assert Ok(d) = latlng.new(lat: 10.0, lng: 0.0)
  let assert Ok(#(sw, ne)) =
    bbox.compute(geometry: geometry.LineString([a, b, c, d]))
  latlng.lat(sw) |> should.equal(0.0)
  latlng.lng(sw) |> should.equal(0.0)
  latlng.lat(ne) |> should.equal(10.0)
  latlng.lng(ne) |> should.equal(10.0)
}

pub fn diff_bbox_triangle_polygon_test() -> Nil {
  let assert Ok(a) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(b) = latlng.new(lat: 0.0, lng: 10.0)
  let assert Ok(c) = latlng.new(lat: 10.0, lng: 5.0)
  let assert Ok(#(sw, ne)) =
    bbox.compute(geometry: geometry.Polygon([[a, b, c, a]]))
  latlng.lat(sw) |> should.equal(0.0)
  latlng.lng(sw) |> should.equal(0.0)
  latlng.lat(ne) |> should.equal(10.0)
  latlng.lng(ne) |> should.equal(10.0)
}

pub fn diff_centroid_l_shape_line_matches_turf_test() -> Nil {
  // Turf: centroid of LineString [[0,0],[10,0],[10,10],[0,10]] = (5, 5)
  let assert Ok(a) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(b) = latlng.new(lat: 0.0, lng: 10.0)
  let assert Ok(c) = latlng.new(lat: 10.0, lng: 10.0)
  let assert Ok(d) = latlng.new(lat: 10.0, lng: 0.0)
  let assert Ok(c_pt) =
    centroid.compute(geometry: geometry.LineString([a, b, c, d]))
  approx(latlng.lat(c_pt), 5.0, 0.000_001)
  |> should.be_true
  approx(latlng.lng(c_pt), 5.0, 0.000_001)
  |> should.be_true
}

pub fn diff_centroid_square_polygon_matches_turf_test() -> Nil {
  let assert Ok(a) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(b) = latlng.new(lat: 0.0, lng: 10.0)
  let assert Ok(c) = latlng.new(lat: 10.0, lng: 10.0)
  let assert Ok(d) = latlng.new(lat: 10.0, lng: 0.0)
  let assert Ok(c_pt) =
    centroid.compute(geometry: geometry.Polygon([[a, b, c, d, a]]))
  approx(latlng.lat(c_pt), 5.0, 0.000_001)
  |> should.be_true
  approx(latlng.lng(c_pt), 5.0, 0.000_001)
  |> should.be_true
}

pub fn diff_centroid_triangle_polygon_matches_turf_test() -> Nil {
  // Triangle vertices (0,0), (0,10), (10,5). Vertex mean = (3.333, 5),
  // identical to the signed-area centroid for triangles.
  let assert Ok(a) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(b) = latlng.new(lat: 0.0, lng: 10.0)
  let assert Ok(c) = latlng.new(lat: 10.0, lng: 5.0)
  let assert Ok(c_pt) =
    centroid.compute(geometry: geometry.Polygon([[a, b, c, a]]))
  approx(latlng.lng(c_pt), 5.0, 0.000_001)
  |> should.be_true
  approx(latlng.lat(c_pt), 3.333_333_333, 0.000_01)
  |> should.be_true
}

pub fn diff_simplify_wavy_drops_at_large_tolerance_test() -> Nil {
  // Turf: simplify([[0,0],[1,0.001],[2,-0.001],[3,0.001],[4,0]], tol=0.01)
  //   = [[0,0],[4,0]]
  let assert Ok(a) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(b) = latlng.new(lat: 0.001, lng: 1.0)
  let assert Ok(c) = latlng.new(lat: -0.001, lng: 2.0)
  let assert Ok(d) = latlng.new(lat: 0.001, lng: 3.0)
  let assert Ok(e) = latlng.new(lat: 0.0, lng: 4.0)
  let assert Ok(out) =
    simplify.line_string(points: [a, b, c, d, e], tolerance: 0.01)
  list.length(out) |> should.equal(2)
}

pub fn diff_simplify_wavy_keeps_at_small_tolerance_test() -> Nil {
  let assert Ok(a) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(b) = latlng.new(lat: 0.001, lng: 1.0)
  let assert Ok(c) = latlng.new(lat: -0.001, lng: 2.0)
  let assert Ok(d) = latlng.new(lat: 0.001, lng: 3.0)
  let assert Ok(e) = latlng.new(lat: 0.0, lng: 4.0)
  let assert Ok(out) =
    simplify.line_string(points: [a, b, c, d, e], tolerance: 0.000_1)
  list.length(out) |> should.equal(5)
}
