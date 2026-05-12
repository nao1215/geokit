//// dig-bug round 2: property-based + metamorphic testing.
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
import gleam/string
import gleam_community/maths
import metamon
import metamon/generator
import metamon/generator/range

import geokit/bbox
import geokit/bearing
import geokit/centroid
import geokit/distance
import geokit/geohash
import geokit/geometry
import geokit/latlng.{type LatLng}
import geokit/mercator
import geokit/polyline
import geokit/simplify

// --- Generators ----------------------------------------------------------

fn latlng_gen() -> generator.Generator(LatLng) {
  generator.map2(
    generator.float(-90.0, 90.0),
    generator.float(-180.0, 180.0),
    fn(lat, lng) {
      let assert Ok(p) = latlng.new(lat: lat, lng: lng)
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
      let assert Ok(p) = latlng.new(lat: lat, lng: lng)
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
      let assert Ok(p) = latlng.new(lat: lat, lng: lng)
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

fn tile_gen() -> generator.Generator(mercator.Tile) {
  // Zoom 1..20 (zoom 0 makes quadkey == "" which `from_quadkey`
  // rejects with EmptyQuadkey).
  generator.bind(generator.int(range.constant(1, 20)), fn(z) {
    let max_coord = pow2(z) - 1
    generator.map2(
      generator.int(range.constant(0, max_coord)),
      generator.int(range.constant(0, max_coord)),
      fn(x, y) {
        let assert Ok(t) = mercator.new(zoom: z, x: x, y: y)
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
    distance.haversine(a: pair.0, b: pair.1) >=. 0.0
  })
}

pub fn pbt_haversine_zero_for_same_point_test() -> Nil {
  metamon.forall(latlng_gen(), fn(p) {
    distance.haversine(a: p, b: p) <=. 1.0e-6
  })
}

pub fn pbt_haversine_bounded_by_half_circumference_test() -> Nil {
  let max = 6_371_008.8 *. maths.pi() +. 0.001
  metamon.forall(generator.tuple2(latlng_gen(), latlng_gen()), fn(pair) {
    distance.haversine(a: pair.0, b: pair.1) <=. max
  })
}

pub fn pbt_haversine_km_is_metres_over_1000_test() -> Nil {
  metamon.forall(generator.tuple2(latlng_gen(), latlng_gen()), fn(pair) {
    let m = distance.haversine(a: pair.0, b: pair.1)
    let km = distance.haversine_km(a: pair.0, b: pair.1)
    abs_diff(m /. 1000.0, km) <=. 1.0e-9
  })
}

pub fn pbt_haversine_commutative_test() -> Nil {
  let mr = metamon.commutativity_of(name: "haversine_commutative")
  metamon.forall_morph(
    generator.tuple2(latlng_gen(), latlng_gen()),
    mr,
    fn(pair) { distance.haversine(a: pair.0, b: pair.1) },
  )
}

pub fn pbt_distance_triangle_inequality_test() -> Nil {
  metamon.forall(
    generator.tuple3(latlng_gen(), latlng_gen(), latlng_gen()),
    fn(triple) {
      let d_ab = distance.haversine(a: triple.0, b: triple.1)
      let d_bc = distance.haversine(a: triple.1, b: triple.2)
      let d_ac = distance.haversine(a: triple.0, b: triple.2)
      d_ac <=. d_ab +. d_bc +. 0.001
    },
  )
}

// --- bearing properties ------------------------------------------------

pub fn pbt_bearing_initial_in_range_test() -> Nil {
  metamon.forall(generator.tuple2(latlng_gen(), latlng_gen()), fn(pair) {
    let value = bearing.initial(from: pair.0, to: pair.1)
    value >=. 0.0 && value <. 360.0
  })
}

pub fn pbt_bearing_final_in_range_test() -> Nil {
  metamon.forall(generator.tuple2(latlng_gen(), latlng_gen()), fn(pair) {
    let value = bearing.final(from: pair.0, to: pair.1)
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
  let d = distance.haversine(a: a, b: b)
  case d <. 19_000_000.0 && d >. 100.0 {
    False -> True
    True -> bearing_diff_close_to_180(a, b)
  }
}

fn bearing_diff_close_to_180(a: LatLng, b: LatLng) -> Bool {
  let final_ab = bearing.final(from: a, to: b)
  let initial_ba = bearing.initial(from: b, to: a)
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
  case geohash.encode(point: p, precision: prec) {
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
  case geohash.encode(point: p, precision: prec) {
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
  case geohash.encode(point: p, precision: prec) {
    Error(_) -> False
    Ok(hash) -> check_geohash_bounds(hash, p)
  }
}

fn check_geohash_bounds(hash: String, p: LatLng) -> Bool {
  case geohash.decode_bounds(hash: hash) {
    Error(_) -> False
    Ok(pair) -> bbox_contains(pair.0, pair.1, p)
  }
}

fn bbox_contains(sw: LatLng, ne: LatLng, p: LatLng) -> Bool {
  latlng.lat(sw) <=. latlng.lat(p)
  && latlng.lat(p) <=. latlng.lat(ne)
  && latlng.lng(sw) <=. latlng.lng(p)
  && latlng.lng(p) <=. latlng.lng(ne)
}

pub fn pbt_geohash_case_insensitive_decode_test() -> Nil {
  metamon.forall(generator.tuple2(latlng_gen(), precision_gen()), fn(pair) {
    geohash_case_agreement(pair.0, pair.1)
  })
}

fn geohash_case_agreement(p: LatLng, prec: Int) -> Bool {
  case geohash.encode(point: p, precision: prec) {
    Error(_) -> False
    Ok(hash) -> decode_lower_equals_upper(hash)
  }
}

fn decode_lower_equals_upper(hash: String) -> Bool {
  let upper = string.uppercase(hash)
  case geohash.decode(hash), geohash.decode(upper) {
    Ok(lo), Ok(up) -> latlng.equal(lo, up)
    _, _ -> False
  }
}

pub fn pbt_geohash_neighbors_preserve_length_test() -> Nil {
  metamon.forall(generator.tuple2(latlng_gen(), precision_gen()), fn(pair) {
    geohash_neighbors_length_ok(pair.0, pair.1)
  })
}

fn geohash_neighbors_length_ok(p: LatLng, prec: Int) -> Bool {
  case geohash.encode(point: p, precision: prec) {
    Error(_) -> False
    Ok(hash) -> neighbors_all_length(hash, prec)
  }
}

fn neighbors_all_length(hash: String, prec: Int) -> Bool {
  case geohash.neighbors(hash: hash) {
    // Polar boundaries can return EmptyHash by design — treat as
    // out-of-scope, not a failure.
    Error(_) -> True
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
  case geohash.encode(point: p, precision: prec) {
    Error(_) -> False
    Ok(start) -> step_east_then_west(start)
  }
}

fn step_east_then_west(start: String) -> Bool {
  case geohash.neighbor(hash: start, direction: geohash.East) {
    Error(_) -> True
    Ok(east) -> step_back_west(east, start)
  }
}

fn step_back_west(east: String, start: String) -> Bool {
  case geohash.neighbor(hash: east, direction: geohash.West) {
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
  case
    geohash.encode(point: p, precision: n),
    geohash.encode(point: p, precision: n + 1)
  {
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
  let encoded = polyline.encode_with(points: points, precision: precision)
  case polyline.decode_with(input: encoded, precision: precision) {
    Error(_) -> False
    Ok(decoded) -> lists_close_enough(points, decoded, tol)
  }
}

pub fn pbt_polyline_decode_round_trip_length_test() -> Nil {
  metamon.forall(latlng_list_gen(), fn(points) {
    polyline_round_trip_keeps_length(points)
  })
}

fn polyline_round_trip_keeps_length(points: List(LatLng)) -> Bool {
  let encoded = polyline.encode(points: points)
  case polyline.decode(input: encoded) {
    Error(_) -> False
    Ok(decoded) -> list.length(decoded) == list.length(points)
  }
}

pub fn pbt_polyline_encode_default_matches_precision_5_test() -> Nil {
  metamon.forall(
    generator.list_of(latlng_gen(), range.constant(0, 6)),
    fn(points) {
      polyline.encode(points: points)
      == polyline.encode_with(points: points, precision: 5)
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
  let lat_diff = abs_diff(latlng.lat(a), latlng.lat(b))
  let lng_diff = abs_diff(latlng.lng(a), latlng.lng(b))
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

fn quadkey_round_trip_ok(t: mercator.Tile) -> Bool {
  let qk = mercator.to_quadkey(tile: t)
  case mercator.from_quadkey(quadkey: qk) {
    Ok(decoded) ->
      mercator.zoom(tile: decoded) == mercator.zoom(tile: t)
      && mercator.x(tile: decoded) == mercator.x(tile: t)
      && mercator.y(tile: decoded) == mercator.y(tile: t)
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
  case mercator.from_lat_lng(point: p, zoom: z) {
    Ok(t) -> mercator.zoom(tile: t) == z
    Error(_) -> False
  }
}

pub fn pbt_mercator_quadkey_length_equals_zoom_test() -> Nil {
  metamon.forall(tile_gen(), fn(t) {
    string.length(mercator.to_quadkey(tile: t)) == mercator.zoom(tile: t)
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
  case mercator.from_lat_lng(point: p, zoom: z) {
    Error(_) -> False
    Ok(t) -> tile_contains_point(t, p)
  }
}

fn tile_contains_point(t: mercator.Tile, p: LatLng) -> Bool {
  let nw = mercator.to_lat_lng(tile: t)
  let pair = mercator.bounds(tile: t)
  let lat_in =
    latlng.lat(pair.0) -. 0.0001 <=. latlng.lat(p)
    && latlng.lat(p) <=. latlng.lat(nw) +. 0.0001
  let lng_in =
    latlng.lng(nw) -. 0.0001 <=. latlng.lng(p)
    && latlng.lng(p) <=. latlng.lng(pair.1) +. 0.0001
  lat_in && lng_in
}

// --- bbox properties ---------------------------------------------------

pub fn pbt_bbox_sw_le_ne_test() -> Nil {
  metamon.forall(non_empty_latlng_list_gen(), fn(points) {
    bbox_well_ordered(points)
  })
}

fn bbox_well_ordered(points: List(LatLng)) -> Bool {
  case bbox.compute(geometry: geometry.LineString(points)) {
    Error(_) -> False
    Ok(pair) ->
      latlng.lat(pair.0) <=. latlng.lat(pair.1)
      && latlng.lng(pair.0) <=. latlng.lng(pair.1)
  }
}

pub fn pbt_bbox_contains_every_point_test() -> Nil {
  metamon.forall(non_empty_latlng_list_gen(), fn(points) {
    bbox_contains_all(points)
  })
}

fn bbox_contains_all(points: List(LatLng)) -> Bool {
  case bbox.compute(geometry: geometry.LineString(points)) {
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
  let original = geometry.LineString(points)
  let reversed = geometry.LineString(list.reverse(points))
  case bbox.compute(geometry: original), bbox.compute(geometry: reversed) {
    Ok(a), Ok(b) -> bbox_equal(a.0, a.1, b.0, b.1)
    _, _ -> False
  }
}

fn bbox_equal(sw1: LatLng, ne1: LatLng, sw2: LatLng, ne2: LatLng) -> Bool {
  latlng.lat(sw1) == latlng.lat(sw2)
  && latlng.lng(sw1) == latlng.lng(sw2)
  && latlng.lat(ne1) == latlng.lat(ne2)
  && latlng.lng(ne1) == latlng.lng(ne2)
}

// --- centroid properties ----------------------------------------------

pub fn pbt_centroid_inside_bbox_test() -> Nil {
  metamon.forall(non_empty_latlng_list_gen(), fn(points) {
    centroid_within_bbox(points)
  })
}

fn centroid_within_bbox(points: List(LatLng)) -> Bool {
  let geom = geometry.LineString(points)
  case bbox.compute(geometry: geom), centroid.compute(geometry: geom) {
    Ok(pair), Ok(c) -> bbox_contains(pair.0, pair.1, c)
    _, _ -> False
  }
}

pub fn pbt_centroid_of_single_point_is_point_test() -> Nil {
  metamon.forall(latlng_gen(), fn(p) {
    case centroid.compute(geometry: geometry.Point(p)) {
      Ok(c) -> latlng.equal(c, p)
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
  case simplify.line_string(points: points, tolerance: tolerance) {
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
    simplify.line_string(points: points, tolerance: tolerance)
  {
    Ok(first), Ok(last), Ok(out) -> endpoints_match(first, last, out)
    _, _, _ -> False
  }
}

fn endpoints_match(first: LatLng, last: LatLng, out: List(LatLng)) -> Bool {
  case list.first(out), list.last(out) {
    Ok(of), Ok(ol) -> latlng.equal(of, first) && latlng.equal(ol, last)
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
  case simplify.line_string(points: points, tolerance: 0.1) {
    Error(_) -> False
    Ok(once) -> simplify_again_same_length(once)
  }
}

fn simplify_again_same_length(once: List(LatLng)) -> Bool {
  case simplify.line_string(points: once, tolerance: 0.1) {
    Error(_) -> False
    Ok(twice) -> list.length(twice) == list.length(once)
  }
}
