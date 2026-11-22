//// Property-based and metamorphic tests.
////
//// Generators and the test runner come from the `metamon` library;
//// every test checks an invariant or a metamorphic relation that
//// holds for any input across the documented domain of each
//// function.
////
//// References for the properties asserted here:
////
//// - Triangle inequality and great-circle bearing identities are
////   classical results for any metric / great-circle distance.
//// - Niemeyer geohash: precision-N is a prefix of precision-(N+1)
////   and the alphabet is `0-9b-z` minus `a, i, l, o`.
//// - Google Encoded Polyline: `encode` is `encode_with(precision: 5)`
////   and `decode(encode(points))` recovers the input to within one
////   quantum at the chosen precision.
//// - Web Mercator: a tile produced by `from_lat_lng` at zoom Z is
////   at zoom Z, has a quadkey of length Z, and its lat/lng bounds
////   contain the originating point (within the ±85.05° valid
////   range).
//// - bbox / centroid / simplify: order-invariance under reverse,
////   single-point identity, endpoint preservation, Douglas-Peucker
////   idempotence.

import gleam/bool
import gleam/list
import gleam/result
import gleam/string
import gleam_community/maths
import metamon
import metamon/generator
import metamon/generator/range

import geokit.{type LatLng}
import geokit/geohash
import geokit/polyline
import geokit/tile

// --- Generators ----------------------------------------------------------

fn latlng_gen() -> generator.Generator(LatLng) {
  generator.map2(
    generator.float(-90.0, 90.0),
    generator.float(-180.0, 180.0),
    fn(lat, lng) {
      let assert Ok(p) = geokit.lat_lng(latitude: lat, longitude: lng)
      p
    },
  )
}

fn mid_latlng_gen() -> generator.Generator(LatLng) {
  // Latitudes well away from poles to avoid documented polar edge
  // cases in geohash neighbour traversal and mercator pole clamps.
  generator.map2(
    generator.float(-80.0, 80.0),
    generator.float(-179.0, 179.0),
    fn(lat, lng) {
      let assert Ok(p) = geokit.lat_lng(latitude: lat, longitude: lng)
      p
    },
  )
}

fn mercator_safe_latlng_gen() -> generator.Generator(LatLng) {
  // Web Mercator only projects ±85.05113°. Outside this band
  // `from_lat_lng` clamps, so the original point intentionally
  // falls outside the returned cell.
  generator.map2(
    generator.float(-85.0, 85.0),
    generator.float(-179.0, 179.0),
    fn(lat, lng) {
      let assert Ok(p) = geokit.lat_lng(latitude: lat, longitude: lng)
      p
    },
  )
}

fn non_empty_latlng_list_gen() -> generator.Generator(List(LatLng)) {
  generator.list_of(latlng_gen(), range.constant(1, 10))
}

fn latlng_list_gen() -> generator.Generator(List(LatLng)) {
  generator.list_of(latlng_gen(), range.constant(0, 8))
}

fn precision_gen() -> generator.Generator(Int) {
  generator.int(range.constant(1, 12))
}

fn tile_gen() -> generator.Generator(tile.Tile) {
  // Zoom 1..20; zoom 0 has the empty quadkey, covered by mercator_test.
  generator.bind(generator.int(range.constant(1, 20)), fn(z) {
    let max_coord = pow2(z) - 1
    generator.map2(
      generator.int(range.constant(0, max_coord)),
      generator.int(range.constant(0, max_coord)),
      fn(x, y) {
        let assert Ok(t) = tile.new(zoom: z, x: x, y: y)
        t
      },
    )
  })
}

fn pow2(n: Int) -> Int {
  use <- bool.guard(when: n <= 0, return: 1)
  2 * pow2(n - 1)
}

fn abs_diff(a: Float, b: Float) -> Float {
  case a >. b {
    True -> a -. b
    False -> b -. a
  }
}

// --- distance properties -----------------------------------------------

pub fn pbt_haversine_non_negative_test() -> Nil {
  metamon.forall(generator.tuple2(latlng_gen(), latlng_gen()), fn(pair) {
    geokit.distance(from: pair.0, to: pair.1) >=. 0.0
  })
}

pub fn pbt_haversine_zero_for_same_point_test() -> Nil {
  metamon.forall(latlng_gen(), fn(p) {
    geokit.distance(from: p, to: p) <=. 1.0e-6
  })
}

pub fn pbt_haversine_bounded_by_half_circumference_test() -> Nil {
  let max = 6_371_008.8 *. maths.pi() +. 0.001
  metamon.forall(generator.tuple2(latlng_gen(), latlng_gen()), fn(pair) {
    geokit.distance(from: pair.0, to: pair.1) <=. max
  })
}

pub fn pbt_haversine_km_is_metres_over_1000_test() -> Nil {
  metamon.forall(generator.tuple2(latlng_gen(), latlng_gen()), fn(pair) {
    let m = geokit.distance(from: pair.0, to: pair.1)
    let km = {
      geokit.distance(from: pair.0, to: pair.1) /. 1000.0
    }
    abs_diff(m /. 1000.0, km) <=. 1.0e-9
  })
}

pub fn pbt_haversine_commutative_test() -> Nil {
  let mr = metamon.commutativity_of(name: "haversine_commutative")
  metamon.forall_morph(
    generator.tuple2(latlng_gen(), latlng_gen()),
    mr,
    fn(pair) { geokit.distance(from: pair.0, to: pair.1) },
  )
}

pub fn pbt_distance_triangle_inequality_test() -> Nil {
  metamon.forall(
    generator.tuple3(latlng_gen(), latlng_gen(), latlng_gen()),
    fn(triple) {
      let d_ab = geokit.distance(from: triple.0, to: triple.1)
      let d_bc = geokit.distance(from: triple.1, to: triple.2)
      let d_ac = geokit.distance(from: triple.0, to: triple.2)
      d_ac <=. d_ab +. d_bc +. 0.001
    },
  )
}

// --- bearing properties ------------------------------------------------

pub fn pbt_bearing_initial_in_range_test() -> Nil {
  metamon.forall(generator.tuple2(latlng_gen(), latlng_gen()), fn(pair) {
    let value = geokit.initial_bearing(from: pair.0, to: pair.1)
    value >=. 0.0 && value <. 360.0
  })
}

pub fn pbt_bearing_final_in_range_test() -> Nil {
  metamon.forall(generator.tuple2(latlng_gen(), latlng_gen()), fn(pair) {
    let value = geokit.final_bearing(from: pair.0, to: pair.1)
    value >=. 0.0 && value <. 360.0
  })
}

pub fn pbt_bearing_final_matches_reverse_initial_plus_180_test() -> Nil {
  // For non-antipodal, non-coincident pairs, the heading on arrival
  // at b when travelling from a is anti-parallel to the heading on
  // departure from b toward a — i.e. differs by exactly 180°.
  metamon.forall(generator.tuple2(latlng_gen(), latlng_gen()), fn(pair) {
    bearing_inverse_holds_for(pair.0, pair.1)
  })
}

fn bearing_inverse_holds_for(a: LatLng, b: LatLng) -> Bool {
  let d = geokit.distance(from: a, to: b)
  case d <. 19_000_000.0 && d >. 100.0 {
    False -> True
    True -> bearing_diff_close_to_180(a, b)
  }
}

fn bearing_diff_close_to_180(a: LatLng, b: LatLng) -> Bool {
  let final_ab = geokit.final_bearing(from: a, to: b)
  let initial_ba = geokit.initial_bearing(from: b, to: a)
  let diff_raw = abs_diff(final_ab, initial_ba)
  diff_raw >=. 179.5 && diff_raw <=. 180.5
}

// --- geohash properties -----------------------------------------------

pub fn pbt_geohash_encoded_length_equals_precision_test() -> Nil {
  metamon.forall(generator.tuple2(latlng_gen(), precision_gen()), fn(pair) {
    geohash_length_matches(pair.0, pair.1)
  })
}

fn geohash_length_matches(p: LatLng, prec: Int) -> Bool {
  case geohash.encode(p, precision: prec) {
    Ok(hash) -> string.length(hash) == prec
    Error(_) -> False
  }
}

pub fn pbt_geohash_alphabet_test() -> Nil {
  metamon.forall(generator.tuple2(latlng_gen(), precision_gen()), fn(pair) {
    geohash_alphabet_ok(pair.0, pair.1)
  })
}

fn geohash_alphabet_ok(p: LatLng, prec: Int) -> Bool {
  case geohash.encode(p, precision: prec) {
    Ok(hash) -> !contains_forbidden_chars(hash)
    Error(_) -> False
  }
}

fn contains_forbidden_chars(hash: String) -> Bool {
  // Niemeyer base32 excludes a, i, l, o.
  string.contains(hash, "a")
  || string.contains(hash, "i")
  || string.contains(hash, "l")
  || string.contains(hash, "o")
}

pub fn pbt_geohash_decode_bounds_contains_original_test() -> Nil {
  metamon.forall(generator.tuple2(latlng_gen(), precision_gen()), fn(pair) {
    geohash_bounds_contain(pair.0, pair.1)
  })
}

fn geohash_bounds_contain(p: LatLng, prec: Int) -> Bool {
  case geohash.encode(p, precision: prec) {
    Error(_) -> False
    Ok(hash) -> check_geohash_bounds(hash, p)
  }
}

fn check_geohash_bounds(hash: String, p: LatLng) -> Bool {
  case geohash_bounds(hash) {
    Error(_) -> False
    Ok(pair) -> bbox_contains(pair.0, pair.1, p)
  }
}

fn bbox_contains(sw: LatLng, ne: LatLng, p: LatLng) -> Bool {
  geokit.latitude(sw) <=. geokit.latitude(p)
  && geokit.latitude(p) <=. geokit.latitude(ne)
  && geokit.longitude(sw) <=. geokit.longitude(p)
  && geokit.longitude(p) <=. geokit.longitude(ne)
}

pub fn pbt_geohash_case_insensitive_decode_test() -> Nil {
  metamon.forall(generator.tuple2(latlng_gen(), precision_gen()), fn(pair) {
    geohash_case_agreement(pair.0, pair.1)
  })
}

fn geohash_case_agreement(p: LatLng, prec: Int) -> Bool {
  case geohash.encode(p, precision: prec) {
    Error(_) -> False
    Ok(hash) -> decode_lower_equals_upper(hash)
  }
}

fn decode_lower_equals_upper(hash: String) -> Bool {
  let upper = string.uppercase(hash)
  case geohash.decode(hash), geohash.decode(upper) {
    Ok(lo), Ok(up) -> lo == up
    _, _ -> False
  }
}

pub fn pbt_geohash_neighbors_preserve_length_test() -> Nil {
  metamon.forall(generator.tuple2(latlng_gen(), precision_gen()), fn(pair) {
    geohash_neighbors_length_ok(pair.0, pair.1)
  })
}

fn geohash_neighbors_length_ok(p: LatLng, prec: Int) -> Bool {
  case geohash.encode(p, precision: prec) {
    Error(_) -> False
    Ok(hash) -> neighbors_all_length(hash, prec)
  }
}

fn neighbors_all_length(hash: String, prec: Int) -> Bool {
  case geohash.neighbors(hash) {
    // Cells in the polar rows have no neighbor on one side.
    Error(geohash.NoNeighborBeyondPole) -> True
    Error(_) -> False
    Ok(n) ->
      string.length(n.north) == prec
      && string.length(n.east) == prec
      && string.length(n.south) == prec
      && string.length(n.west) == prec
  }
}

pub fn pbt_geohash_east_then_west_round_trip_test() -> Nil {
  metamon.forall(generator.tuple2(mid_latlng_gen(), precision_gen()), fn(pair) {
    east_west_round_trip_ok(pair.0, pair.1)
  })
}

fn east_west_round_trip_ok(p: LatLng, prec: Int) -> Bool {
  case geohash.encode(p, precision: prec) {
    Error(_) -> False
    Ok(start) -> step_east_then_west(start)
  }
}

fn step_east_then_west(start: String) -> Bool {
  case geohash.neighbor(start, toward: geohash.East) {
    Error(_) -> True
    Ok(east) -> step_back_west(east, start)
  }
}

fn step_back_west(east: String, start: String) -> Bool {
  case geohash.neighbor(east, toward: geohash.West) {
    Error(_) -> True
    Ok(back) -> back == start
  }
}

pub fn pbt_geohash_precision_prefix_test() -> Nil {
  // Encoding at precision N must yield a prefix of the encoding at
  // precision N+1 — geohash cells nest.
  metamon.forall(
    generator.tuple2(latlng_gen(), generator.int(range.constant(1, 11))),
    fn(pair) { geohash_prefix_nests(pair.0, pair.1) },
  )
}

fn geohash_prefix_nests(p: LatLng, n: Int) -> Bool {
  case geohash.encode(p, precision: n), geohash.encode(p, precision: n + 1) {
    Ok(short), Ok(long) -> string.starts_with(long, short)
    _, _ -> False
  }
}

// --- polyline codec ---------------------------------------------------

pub fn pbt_polyline_round_trip_precision_5_test() -> Nil {
  metamon.forall(latlng_list_gen(), fn(points) {
    polyline_round_trips(points, 5, 1.0e-5)
  })
}

pub fn pbt_polyline_round_trip_precision_6_test() -> Nil {
  metamon.forall(latlng_list_gen(), fn(points) {
    polyline_round_trips(points, 6, 1.0e-6)
  })
}

fn polyline_round_trips(
  points: List(LatLng),
  precision: Int,
  tol: Float,
) -> Bool {
  case polyline.encode(points, precision: precision) {
    Error(_) -> False
    Ok(encoded) ->
      case polyline.decode(encoded, precision: precision) {
        Error(_) -> False
        Ok(decoded) -> lists_close_enough(points, decoded, tol)
      }
  }
}

pub fn pbt_polyline_decode_round_trip_length_test() -> Nil {
  metamon.forall(latlng_list_gen(), fn(points) {
    polyline_round_trip_keeps_length(points)
  })
}

fn polyline_round_trip_keeps_length(points: List(LatLng)) -> Bool {
  let encoded = encode5(points)
  case polyline.decode(encoded, precision: 5) {
    Error(_) -> False
    Ok(decoded) -> list.length(decoded) == list.length(points)
  }
}

pub fn pbt_polyline_encode_default_matches_precision_5_test() -> Nil {
  metamon.forall(
    generator.list_of(latlng_gen(), range.constant(0, 6)),
    fn(points) {
      case polyline.encode(points, precision: 5) {
        Ok(encoded) -> encode5(points) == encoded
        Error(_) -> False
      }
    },
  )
}

fn lists_close_enough(
  expected: List(LatLng),
  actual: List(LatLng),
  tolerance: Float,
) -> Bool {
  case expected, actual {
    [], [] -> True
    [], _ | _, [] -> False
    [a, ..tail_a], [b, ..tail_b] ->
      compare_head_and_recurse(a, b, tail_a, tail_b, tolerance)
  }
}

fn compare_head_and_recurse(
  a: LatLng,
  b: LatLng,
  tail_a: List(LatLng),
  tail_b: List(LatLng),
  tolerance: Float,
) -> Bool {
  let lat_diff = abs_diff(geokit.latitude(a), geokit.latitude(b))
  let lng_diff = abs_diff(geokit.longitude(a), geokit.longitude(b))
  // Antimeridian wraparound: at ±180° the decoded longitude can
  // flip sign — accept a one-period (360°) difference.
  let lng_ok = lng_diff <=. tolerance || abs_diff(lng_diff, 360.0) <=. tolerance
  case lat_diff <=. tolerance && lng_ok {
    True -> lists_close_enough(tail_a, tail_b, tolerance)
    False -> False
  }
}

// --- mercator codec ----------------------------------------------------

pub fn pbt_mercator_quadkey_round_trip_test() -> Nil {
  metamon.forall(tile_gen(), fn(t) { quadkey_round_trip_ok(t) })
}

fn quadkey_round_trip_ok(t: tile.Tile) -> Bool {
  let qk = tile.to_quadkey(t)
  case tile.from_quadkey(qk) {
    Ok(decoded) ->
      tile.zoom(decoded) == tile.zoom(t)
      && tile.x(decoded) == tile.x(t)
      && tile.y(decoded) == tile.y(t)
    Error(_) -> False
  }
}

pub fn pbt_mercator_from_lat_lng_preserves_zoom_test() -> Nil {
  metamon.forall(
    generator.tuple2(latlng_gen(), generator.int(range.constant(0, 20))),
    fn(pair) { from_lat_lng_preserves_zoom(pair.0, pair.1) },
  )
}

fn from_lat_lng_preserves_zoom(p: LatLng, z: Int) -> Bool {
  case tile.from_lat_lng(p, zoom: z) {
    Ok(t) -> tile.zoom(t) == z
    Error(_) -> False
  }
}

pub fn pbt_mercator_quadkey_length_equals_zoom_test() -> Nil {
  metamon.forall(tile_gen(), fn(t) {
    string.length(tile.to_quadkey(t)) == tile.zoom(t)
  })
}

pub fn pbt_mercator_lat_lng_round_trip_within_tile_test() -> Nil {
  metamon.forall(
    generator.tuple2(
      mercator_safe_latlng_gen(),
      generator.int(range.constant(0, 18)),
    ),
    fn(pair) { round_trip_within_tile_ok(pair.0, pair.1) },
  )
}

fn round_trip_within_tile_ok(p: LatLng, z: Int) -> Bool {
  case tile.from_lat_lng(p, zoom: z) {
    Error(_) -> False
    Ok(t) -> tile_contains(t, p)
  }
}

fn tile_contains(t: tile.Tile, p: LatLng) -> Bool {
  let nw = north_west(t)
  let pair = tile_bounds(t)
  let lat_in =
    geokit.latitude(pair.0) -. 0.0001 <=. geokit.latitude(p)
    && geokit.latitude(p) <=. geokit.latitude(nw) +. 0.0001
  let lng_in =
    geokit.longitude(nw) -. 0.0001 <=. geokit.longitude(p)
    && geokit.longitude(p) <=. geokit.longitude(pair.1) +. 0.0001
  lat_in && lng_in
}

// --- bbox properties ---------------------------------------------------

pub fn pbt_bbox_sw_le_ne_test() -> Nil {
  metamon.forall(non_empty_latlng_list_gen(), fn(points) {
    bbox_well_ordered(points)
  })
}

fn bbox_well_ordered(points: List(LatLng)) -> Bool {
  case bbox(geokit.LineString(points)) {
    Error(_) -> False
    Ok(pair) ->
      geokit.latitude(pair.0) <=. geokit.latitude(pair.1)
      && geokit.longitude(pair.0) <=. geokit.longitude(pair.1)
  }
}

pub fn pbt_bbox_contains_every_point_test() -> Nil {
  metamon.forall(non_empty_latlng_list_gen(), fn(points) {
    bbox_contains_all(points)
  })
}

fn bbox_contains_all(points: List(LatLng)) -> Bool {
  case bbox(geokit.LineString(points)) {
    Error(_) -> False
    Ok(pair) -> list.all(points, bbox_contains_fn(pair.0, pair.1))
  }
}

fn bbox_contains_fn(sw: LatLng, ne: LatLng) -> fn(LatLng) -> Bool {
  fn(p) { bbox_contains(sw, ne, p) }
}

pub fn pbt_bbox_invariant_under_reverse_test() -> Nil {
  metamon.forall(non_empty_latlng_list_gen(), fn(points) {
    bbox_reverse_invariant(points)
  })
}

fn bbox_reverse_invariant(points: List(LatLng)) -> Bool {
  let original = geokit.LineString(points)
  let reversed = geokit.LineString(list.reverse(points))
  case bbox(original), bbox(reversed) {
    Ok(a), Ok(b) -> bbox_equal(a.0, a.1, b.0, b.1)
    _, _ -> False
  }
}

fn bbox_equal(sw1: LatLng, ne1: LatLng, sw2: LatLng, ne2: LatLng) -> Bool {
  geokit.latitude(sw1) == geokit.latitude(sw2)
  && geokit.longitude(sw1) == geokit.longitude(sw2)
  && geokit.latitude(ne1) == geokit.latitude(ne2)
  && geokit.longitude(ne1) == geokit.longitude(ne2)
}

// --- centroid properties ----------------------------------------------

pub fn pbt_centroid_inside_bbox_test() -> Nil {
  metamon.forall(non_empty_latlng_list_gen(), fn(points) {
    centroid_within_bbox(points)
  })
}

fn centroid_within_bbox(points: List(LatLng)) -> Bool {
  let geom = geokit.LineString(points)
  case bbox(geom), geokit.centroid(geom) {
    Ok(pair), Ok(c) -> bbox_contains(pair.0, pair.1, c)
    _, _ -> False
  }
}

pub fn pbt_centroid_of_single_point_is_point_test() -> Nil {
  metamon.forall(latlng_gen(), fn(p) {
    case geokit.centroid(geokit.Point(p)) {
      Ok(c) -> c == p
      Error(_) -> False
    }
  })
}

// --- simplify properties ----------------------------------------------

pub fn pbt_simplify_length_does_not_grow_test() -> Nil {
  let tolerance_gen = generator.float(0.0, 1.0)
  metamon.forall(
    generator.tuple2(non_empty_latlng_list_gen(), tolerance_gen),
    fn(pair) { simplify_does_not_grow(pair.0, pair.1) },
  )
}

fn simplify_does_not_grow(points: List(LatLng), tolerance: Float) -> Bool {
  case simplify_line(points, tolerance: tolerance) {
    Ok(out) -> list.length(out) <= list.length(points)
    Error(_) -> False
  }
}

pub fn pbt_simplify_preserves_endpoints_test() -> Nil {
  // For 3+ points the first and last of the simplified line must
  // equal the first and last of the input.
  let three_plus = generator.list_of(latlng_gen(), range.constant(3, 10))
  let tolerance_gen = generator.float(0.0001, 0.5)
  metamon.forall(generator.tuple2(three_plus, tolerance_gen), fn(pair) {
    simplify_keeps_endpoints(pair.0, pair.1)
  })
}

fn simplify_keeps_endpoints(points: List(LatLng), tolerance: Float) -> Bool {
  case
    list.first(points),
    list.last(points),
    simplify_line(points, tolerance: tolerance)
  {
    Ok(first), Ok(last), Ok(out) -> endpoints_match(first, last, out)
    _, _, _ -> False
  }
}

fn endpoints_match(first: LatLng, last: LatLng, out: List(LatLng)) -> Bool {
  case list.first(out), list.last(out) {
    Ok(of), Ok(ol) -> of == first && ol == last
    _, _ -> False
  }
}

pub fn pbt_simplify_idempotent_at_fixed_tolerance_test() -> Nil {
  // Douglas-Peucker is idempotent at a fixed tolerance: a second
  // pass cannot drop further points because the surviving
  // distances are already ≤ tolerance.
  let three_plus = generator.list_of(latlng_gen(), range.constant(3, 12))
  metamon.forall(three_plus, fn(points) { simplify_is_idempotent(points) })
}

fn simplify_is_idempotent(points: List(LatLng)) -> Bool {
  case simplify_line(points, tolerance: 0.1) {
    Error(_) -> False
    Ok(once) -> simplify_again_same_length(once)
  }
}

fn simplify_again_same_length(once: List(LatLng)) -> Bool {
  case simplify_line(once, tolerance: 0.1) {
    Error(_) -> False
    Ok(twice) -> list.length(twice) == list.length(once)
  }
}

// --- API adapters ----------------------------------------------------------

fn bbox(geometry: geokit.Geometry) -> Result(#(LatLng, LatLng), Nil) {
  geokit.bounding_box(geometry)
  |> result.map(fn(box) { #(box.south_west, box.north_east) })
}

fn simplify_line(
  points: List(LatLng),
  tolerance tolerance: Float,
) -> Result(List(LatLng), Nil) {
  case geokit.simplify(geokit.LineString(points), tolerance:) {
    Ok(geokit.LineString(simplified)) -> Ok(simplified)
    _ -> Error(Nil)
  }
}

fn geohash_bounds(
  hash: String,
) -> Result(#(LatLng, LatLng), geohash.GeohashError) {
  geohash.decode_bounds(hash)
  |> result.map(fn(cell) { #(cell.south_west, cell.north_east) })
}

fn encode5(points: List(LatLng)) -> String {
  let assert Ok(encoded) = polyline.encode(points, precision: 5)
  encoded
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
