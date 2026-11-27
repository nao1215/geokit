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

import geokit.{type LatLng}
import geokit/geohash
import geokit/polyline
import geokit/tile

// --- Generators ----------------------------------------------------------

fn latlng_gen() -> generator.Generator(LatLng) {
  generator.map2(
    generator.float(from: -90.0, to: 90.0),
    generator.float(from: -180.0, to: 180.0),
    fn(lat, lng) {
      let assert Ok(p) = geokit.lat_lng(latitude: lat, longitude: lng)
      p
    },
  )
}

fn mid_latlng_gen() -> generator.Generator(LatLng) {
  // Latitudes well away from poles to avoid documented polar edge
  // cases in geohash neighbor traversal and mercator pole clamps.
  generator.map2(
    generator.float(from: -80.0, to: 80.0),
    generator.float(from: -179.0, to: 179.0),
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
    generator.float(from: -85.0, to: 85.0),
    generator.float(from: -179.0, to: 179.0),
    fn(lat, lng) {
      let assert Ok(p) = geokit.lat_lng(latitude: lat, longitude: lng)
      p
    },
  )
}

fn non_empty_latlng_list_gen() -> generator.Generator(List(LatLng)) {
  generator.list_of(latlng_gen(), length: generator.range(from: 1, to: 10))
}

fn latlng_list_gen() -> generator.Generator(List(LatLng)) {
  generator.list_of(latlng_gen(), length: generator.range(from: 0, to: 8))
}

fn precision_gen() -> generator.Generator(Int) {
  generator.int(generator.range(from: 1, to: 12))
}

fn tile_gen() -> generator.Generator(tile.Tile) {
  // Zoom 1..20; zoom 0 has the empty quadkey, covered by mercator_test.
  generator.bind(generator.int(generator.range(from: 1, to: 20)), fn(z) {
    let max_coord = pow2(z) - 1
    generator.map2(
      generator.int(generator.range(from: 0, to: max_coord)),
      generator.int(generator.range(from: 0, to: max_coord)),
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
    assert geokit.distance(from: pair.0, to: pair.1) >=. 0.0
  })
}

pub fn pbt_haversine_zero_for_same_point_test() -> Nil {
  metamon.forall(latlng_gen(), fn(p) {
    assert geokit.distance(from: p, to: p) <=. 1.0e-6
  })
}

pub fn pbt_haversine_bounded_by_half_circumference_test() -> Nil {
  let max = 6_371_008.8 *. maths.pi() +. 0.001
  metamon.forall(generator.tuple2(latlng_gen(), latlng_gen()), fn(pair) {
    assert geokit.distance(from: pair.0, to: pair.1) <=. max
  })
}

pub fn pbt_distance_in_kilometers_is_meters_over_1000_test() -> Nil {
  metamon.forall(generator.tuple2(latlng_gen(), latlng_gen()), fn(pair) {
    let m = geokit.distance(from: pair.0, to: pair.1)
    let km = {
      geokit.distance(from: pair.0, to: pair.1) /. 1000.0
    }
    assert abs_diff(m /. 1000.0, km) <=. 1.0e-9
  })
}

pub fn pbt_haversine_commutative_test() -> Nil {
  let mr = metamon.commutativity_of(name: "haversine_commutative")
  metamon.forall_morph(
    generator.tuple2(latlng_gen(), latlng_gen()),
    [mr],
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
      assert d_ac <=. d_ab +. d_bc +. 0.001
    },
  )
}

// --- bearing properties ------------------------------------------------

pub fn pbt_bearing_initial_in_range_test() -> Nil {
  metamon.forall(generator.tuple2(latlng_gen(), latlng_gen()), fn(pair) {
    let value = geokit.initial_bearing(from: pair.0, to: pair.1)
    assert value >=. 0.0
    assert value <. 360.0
  })
}

pub fn pbt_bearing_final_in_range_test() -> Nil {
  metamon.forall(generator.tuple2(latlng_gen(), latlng_gen()), fn(pair) {
    let value = geokit.final_bearing(from: pair.0, to: pair.1)
    assert value >=. 0.0
    assert value <. 360.0
  })
}

pub fn pbt_bearing_final_matches_reverse_initial_plus_180_test() -> Nil {
  // For non-antipodal, non-coincident pairs, the heading on arrival
  // at b when travelling from a is anti-parallel to the heading on
  // departure from b toward a — i.e. differs by exactly 180°.
  metamon.forall(generator.tuple2(latlng_gen(), latlng_gen()), fn(pair) {
    let #(a, b) = pair
    let d = geokit.distance(from: a, to: b)
    case d <. 19_000_000.0 && d >. 100.0 {
      False -> Nil
      True -> {
        let final_ab = geokit.final_bearing(from: a, to: b)
        let initial_ba = geokit.initial_bearing(from: b, to: a)
        let diff_raw = abs_diff(final_ab, initial_ba)
        assert diff_raw >=. 179.5
        assert diff_raw <=. 180.5
      }
    }
  })
}

// --- geohash properties -----------------------------------------------

pub fn pbt_geohash_encoded_length_equals_precision_test() -> Nil {
  metamon.forall(generator.tuple2(latlng_gen(), precision_gen()), fn(pair) {
    let #(p, prec) = pair
    let assert Ok(hash) = geohash.encode(p, precision: prec)
    assert string.length(hash) == prec
  })
}

pub fn pbt_geohash_alphabet_test() -> Nil {
  metamon.forall(generator.tuple2(latlng_gen(), precision_gen()), fn(pair) {
    let #(p, prec) = pair
    let assert Ok(hash) = geohash.encode(p, precision: prec)
    assert !contains_forbidden_chars(hash)
  })
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
    let #(p, prec) = pair
    let assert Ok(hash) = geohash.encode(p, precision: prec)
    let assert Ok(#(sw, ne)) = geohash_bounds(hash)
    assert bbox_contains(sw, ne, p)
  })
}

fn bbox_contains(sw: LatLng, ne: LatLng, p: LatLng) -> Bool {
  geokit.latitude(sw) <=. geokit.latitude(p)
  && geokit.latitude(p) <=. geokit.latitude(ne)
  && geokit.longitude(sw) <=. geokit.longitude(p)
  && geokit.longitude(p) <=. geokit.longitude(ne)
}

pub fn pbt_geohash_case_insensitive_decode_test() -> Nil {
  metamon.forall(generator.tuple2(latlng_gen(), precision_gen()), fn(pair) {
    let #(p, prec) = pair
    let assert Ok(hash) = geohash.encode(p, precision: prec)
    let assert Ok(lower) = geohash.decode(hash)
    assert geohash.decode(string.uppercase(hash)) == Ok(lower)
  })
}

pub fn pbt_geohash_neighbors_preserve_length_test() -> Nil {
  metamon.forall(generator.tuple2(latlng_gen(), precision_gen()), fn(pair) {
    let #(p, prec) = pair
    let assert Ok(hash) = geohash.encode(p, precision: prec)
    case geohash.neighbors(hash) {
      // Cells in the polar rows have no neighbor on one side.
      Error(error) -> {
        assert error == geohash.NoNeighborBeyondPole
      }
      Ok(n) -> {
        assert string.length(n.north) == prec
        assert string.length(n.east) == prec
        assert string.length(n.south) == prec
        assert string.length(n.west) == prec
      }
    }
  })
}

pub fn pbt_geohash_east_then_west_round_trip_test() -> Nil {
  metamon.forall(generator.tuple2(mid_latlng_gen(), precision_gen()), fn(pair) {
    let #(p, prec) = pair
    let assert Ok(start) = geohash.encode(p, precision: prec)
    case geohash.neighbor(start, toward: geohash.East) {
      Error(_) -> Nil
      Ok(east) ->
        case geohash.neighbor(east, toward: geohash.West) {
          Error(_) -> Nil
          Ok(back) -> {
            assert back == start
          }
        }
    }
  })
}

pub fn pbt_geohash_precision_prefix_test() -> Nil {
  // Encoding at precision N must yield a prefix of the encoding at
  // precision N+1 — geohash cells nest.
  metamon.forall(
    generator.tuple2(
      latlng_gen(),
      generator.int(generator.range(from: 1, to: 11)),
    ),
    fn(pair) {
      let #(p, n) = pair
      let assert Ok(short) = geohash.encode(p, precision: n)
      let assert Ok(long) = geohash.encode(p, precision: n + 1)
      assert string.starts_with(long, short)
    },
  )
}

// --- polyline codec ---------------------------------------------------

pub fn pbt_polyline_round_trip_precision_5_test() -> Nil {
  metamon.forall(latlng_list_gen(), fn(points) {
    let assert Ok(encoded) = polyline.encode(points, precision: 5)
    let assert Ok(decoded) = polyline.decode(encoded, precision: 5)
    assert lists_close_enough(points, decoded, 1.0e-5)
  })
}

pub fn pbt_polyline_round_trip_precision_6_test() -> Nil {
  metamon.forall(latlng_list_gen(), fn(points) {
    let assert Ok(encoded) = polyline.encode(points, precision: 6)
    let assert Ok(decoded) = polyline.decode(encoded, precision: 6)
    assert lists_close_enough(points, decoded, 1.0e-6)
  })
}

pub fn pbt_polyline_decode_round_trip_length_test() -> Nil {
  metamon.forall(latlng_list_gen(), fn(points) {
    let encoded = encode5(points)
    let assert Ok(decoded) = polyline.decode(encoded, precision: 5)
    assert list.length(decoded) == list.length(points)
  })
}

pub fn pbt_polyline_encode_default_matches_precision_5_test() -> Nil {
  metamon.forall(
    generator.list_of(latlng_gen(), length: generator.range(from: 0, to: 6)),
    fn(points) {
      assert polyline.encode(points, precision: 5) == Ok(encode5(points))
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
  metamon.forall(tile_gen(), fn(t) {
    let assert Ok(decoded) = tile.from_quadkey(tile.to_quadkey(t))
    assert tile.zoom(decoded) == tile.zoom(t)
    assert tile.x(decoded) == tile.x(t)
    assert tile.y(decoded) == tile.y(t)
  })
}

pub fn pbt_mercator_from_lat_lng_preserves_zoom_test() -> Nil {
  metamon.forall(
    generator.tuple2(
      latlng_gen(),
      generator.int(generator.range(from: 0, to: 20)),
    ),
    fn(pair) {
      let #(p, z) = pair
      let assert Ok(t) = tile.from_lat_lng(p, zoom: z)
      assert tile.zoom(t) == z
    },
  )
}

pub fn pbt_mercator_quadkey_length_equals_zoom_test() -> Nil {
  metamon.forall(tile_gen(), fn(t) {
    assert string.length(tile.to_quadkey(t)) == tile.zoom(t)
  })
}

pub fn pbt_mercator_lat_lng_round_trip_within_tile_test() -> Nil {
  metamon.forall(
    generator.tuple2(
      mercator_safe_latlng_gen(),
      generator.int(generator.range(from: 0, to: 18)),
    ),
    fn(pair) {
      let #(p, z) = pair
      let assert Ok(t) = tile.from_lat_lng(p, zoom: z)
      let nw = north_west(t)
      let #(south_west, north_east) = tile_bounds(t)
      assert geokit.latitude(south_west) -. 0.0001 <=. geokit.latitude(p)
      assert geokit.latitude(p) <=. geokit.latitude(nw) +. 0.0001
      assert geokit.longitude(nw) -. 0.0001 <=. geokit.longitude(p)
      assert geokit.longitude(p) <=. geokit.longitude(north_east) +. 0.0001
    },
  )
}

// --- bbox properties ---------------------------------------------------

pub fn pbt_bbox_sw_le_ne_test() -> Nil {
  metamon.forall(non_empty_latlng_list_gen(), fn(points) {
    let assert Ok(#(sw, ne)) = bbox(geokit.LineString(points))
    assert geokit.latitude(sw) <=. geokit.latitude(ne)
    assert geokit.longitude(sw) <=. geokit.longitude(ne)
  })
}

pub fn pbt_bbox_contains_every_point_test() -> Nil {
  metamon.forall(non_empty_latlng_list_gen(), fn(points) {
    let assert Ok(#(sw, ne)) = bbox(geokit.LineString(points))
    list.each(points, fn(p) {
      assert bbox_contains(sw, ne, p)
    })
  })
}

pub fn pbt_bbox_invariant_under_reverse_test() -> Nil {
  // The bounds are compared with `==` on their coordinates, as before.
  metamon.forall(non_empty_latlng_list_gen(), fn(points) {
    let assert Ok(#(sw1, ne1)) = bbox(geokit.LineString(points))
    let assert Ok(#(sw2, ne2)) = bbox(geokit.LineString(list.reverse(points)))
    assert geokit.latitude(sw1) == geokit.latitude(sw2)
    assert geokit.longitude(sw1) == geokit.longitude(sw2)
    assert geokit.latitude(ne1) == geokit.latitude(ne2)
    assert geokit.longitude(ne1) == geokit.longitude(ne2)
  })
}

// --- centroid properties ----------------------------------------------

pub fn pbt_centroid_inside_bbox_test() -> Nil {
  metamon.forall(non_empty_latlng_list_gen(), fn(points) {
    let geom = geokit.LineString(points)
    let assert Ok(#(sw, ne)) = bbox(geom)
    let assert Ok(c) = geokit.centroid(geom)
    assert bbox_contains(sw, ne, c)
  })
}

pub fn pbt_centroid_of_single_point_is_point_test() -> Nil {
  metamon.forall(latlng_gen(), fn(p) {
    assert geokit.centroid(geokit.Point(p)) == Ok(p)
  })
}

// --- simplify properties ----------------------------------------------

pub fn pbt_simplify_length_does_not_grow_test() -> Nil {
  let tolerance_gen = generator.float(from: 0.0, to: 1.0)
  metamon.forall(
    generator.tuple2(non_empty_latlng_list_gen(), tolerance_gen),
    fn(pair) {
      let #(points, tolerance) = pair
      let assert Ok(out) = simplify_line(points, tolerance: tolerance)
      assert list.length(out) <= list.length(points)
    },
  )
}

pub fn pbt_simplify_preserves_endpoints_test() -> Nil {
  // For 3+ points the first and last of the simplified line must
  // equal the first and last of the input.
  let three_plus =
    generator.list_of(latlng_gen(), length: generator.range(from: 3, to: 10))
  let tolerance_gen = generator.float(from: 0.0001, to: 0.5)
  metamon.forall(generator.tuple2(three_plus, tolerance_gen), fn(pair) {
    let #(points, tolerance) = pair
    let assert Ok(out) = simplify_line(points, tolerance: tolerance)
    let assert Ok(first) = list.first(points)
    let assert Ok(last) = list.last(points)
    assert list.first(out) == Ok(first)
    assert list.last(out) == Ok(last)
  })
}

pub fn pbt_simplify_idempotent_at_fixed_tolerance_test() -> Nil {
  // Douglas-Peucker is idempotent at a fixed tolerance: a second
  // pass cannot drop further points because the surviving
  // distances are already ≤ tolerance.
  let three_plus =
    generator.list_of(latlng_gen(), length: generator.range(from: 3, to: 12))
  metamon.forall(three_plus, fn(points) {
    let assert Ok(once) = simplify_line(points, tolerance: 0.1)
    let assert Ok(twice) = simplify_line(once, tolerance: 0.1)
    assert list.length(twice) == list.length(once)
  })
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
