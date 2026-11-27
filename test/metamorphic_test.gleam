//// Metamorphic tests: relations between two runs whose exact output the
//// test cannot state on its own.
////
//// - Great-circle distance does not change when both points are moved by
////   the same longitude, or mirrored across the equator or the prime
////   meridian together.
//// - Mirroring both points across the prime meridian mirrors the initial
////   bearing (b -> 360 - b); mirroring across the equator turns it into
////   180 - b.
//// - The Web Mercator tile of a point at zoom z + 1 is a child of its tile
////   at zoom z, so its quadkey extends the parent's quadkey by one digit.
//// - Douglas-Peucker with a larger tolerance keeps a subsequence of the
////   points it keeps with a smaller tolerance.
////
//// The nightly workflow runs these with METAMON_RUNS_MULTIPLIER as well.

import gleam/float
import gleam/list
import gleam/string
import metamon
import metamon/generator

import geokit.{type LatLng}
import geokit/tile

type Pair =
  #(LatLng, LatLng)

fn point() -> generator.Generator(LatLng) {
  generator.map2(
    generator.float(from: -90.0, to: 90.0),
    generator.float(from: -180.0, to: 180.0),
    fn(lat, lng) { geokit.wrap_lat_lng(latitude: lat, longitude: lng) },
  )
}

fn pair() -> generator.Generator(Pair) {
  generator.tuple2(point(), point())
}

fn shift_lng(p: LatLng, by: Float) -> LatLng {
  geokit.wrap_lat_lng(
    latitude: geokit.latitude(p),
    longitude: geokit.longitude(p) +. by,
  )
}

fn mirror_lat(p: LatLng) -> LatLng {
  geokit.wrap_lat_lng(
    latitude: 0.0 -. geokit.latitude(p),
    longitude: geokit.longitude(p),
  )
}

fn mirror_lng(p: LatLng) -> LatLng {
  geokit.wrap_lat_lng(
    latitude: geokit.latitude(p),
    longitude: 0.0 -. geokit.longitude(p),
  )
}

fn both(f: fn(LatLng) -> LatLng) -> fn(Pair) -> Pair {
  fn(input: Pair) { #(f(input.0), f(input.1)) }
}

/// Equal up to the rounding of the trigonometric calls: within 1 cm, or
/// 1e-9 of distances up to half the circumference (about 2.0e7 m). The
/// absolute part covers the poles, where cos(90 degrees) is about 6e-17
/// rather than 0 and two spellings of the same pole are a few millimeters
/// apart.
fn close_meters() -> metamon.Relation(Float) {
  metamon.Relation(name: "within 1 cm or 1e-9 relative", holds: fn(a, b) {
    let diff = float.absolute_value(a -. b)
    diff <=. 1.0e-2 || diff <=. 1.0e-9 *. float.max(a, b)
  })
}

pub fn distance_is_invariant_under_shared_moves_test() -> Nil {
  let rel = close_meters()
  let haversine = fn(input: Pair) {
    geokit.distance(from: input.0, to: input.1)
  }
  metamon.forall_morph(
    pair(),
    [
      metamon.Morph(
        name: "shift both longitudes by 37.5",
        transform: metamon.Transform(
          name: "shift 37.5",
          apply: both(shift_lng(_, 37.5)),
        ),
        relation: rel,
      ),
      metamon.Morph(
        name: "shift both longitudes by -123.25",
        transform: metamon.Transform(
          name: "shift -123.25",
          apply: both(shift_lng(_, -123.25)),
        ),
        relation: rel,
      ),
      metamon.Morph(
        name: "mirror both across the equator",
        transform: metamon.Transform(
          name: "mirror lat",
          apply: both(mirror_lat),
        ),
        relation: rel,
      ),
      metamon.Morph(
        name: "mirror both across the prime meridian",
        transform: metamon.Transform(
          name: "mirror lng",
          apply: both(mirror_lng),
        ),
        relation: rel,
      ),
    ],
    haversine,
  )
}

/// Angular difference of two bearings in degrees, in [0, 180].
fn angle_between(a: Float, b: Float) -> Float {
  let d = float.absolute_value(a -. b)
  case d >. 180.0 {
    True -> 360.0 -. d
    False -> d
  }
}

fn normalize(b: Float) -> Float {
  case b <. 0.0, b >=. 360.0 {
    True, _ -> b +. 360.0
    _, True -> b -. 360.0
    _, _ -> b
  }
}

/// Pairs whose bearing is well defined: the points are not the same, not
/// antipodal and not at a pole, where the bearing has no unique value and
/// rounding decides it.
fn bearing_pair() -> generator.Generator(Pair) {
  let p =
    generator.map2(
      generator.float(from: -80.0, to: 80.0),
      generator.float(from: -180.0, to: 180.0),
      fn(lat, lng) { geokit.wrap_lat_lng(latitude: lat, longitude: lng) },
    )
  generator.tuple2(p, p)
  |> generator.filter(fn(input) {
    let d = geokit.distance(from: input.0, to: input.1)
    d >. 1000.0 && d <. 1.99e7
  })
}

pub fn bearing_mirrors_with_the_points_test() -> Nil {
  let initial = fn(input: Pair) {
    geokit.initial_bearing(from: input.0, to: input.1)
  }
  let close =
    metamon.Relation(
      name: "same direction within 1e-6 degrees",
      holds: fn(a, b) { angle_between(a, b) <=. 1.0e-6 },
    )
  metamon.forall_morph(
    bearing_pair(),
    [
      metamon.Equivariant(
        name: "mirror across the prime meridian gives 360 - b",
        input: metamon.Transform(name: "mirror lng", apply: both(mirror_lng)),
        output: metamon.Transform(name: "360 - b", apply: fn(b) {
          normalize(360.0 -. b)
        }),
        relation: close,
      ),
      metamon.Equivariant(
        name: "mirror across the equator gives 180 - b",
        input: metamon.Transform(name: "mirror lat", apply: both(mirror_lat)),
        output: metamon.Transform(name: "180 - b", apply: fn(b) {
          normalize(180.0 -. b)
        }),
        relation: close,
      ),
    ],
    initial,
  )
}

pub fn child_tile_extends_the_parent_quadkey_test() -> Nil {
  metamon.forall(
    generator.tuple2(point(), generator.int(generator.range(from: 0, to: 22))),
    fn(input) {
      let #(p, zoom) = input
      let assert Ok(parent) = tile.from_lat_lng(p, zoom: zoom)
      let assert Ok(child) = tile.from_lat_lng(p, zoom: zoom + 1)
      let parent_key = tile.to_quadkey(parent)
      let child_key = tile.to_quadkey(child)
      assert tile.x(child) / 2 == tile.x(parent)
      assert tile.y(child) / 2 == tile.y(parent)
      assert string.starts_with(child_key, parent_key)
      assert string.length(child_key) == string.length(parent_key) + 1
    },
  )
}

fn is_subsequence(small: List(LatLng), of large: List(LatLng)) -> Bool {
  case small, large {
    [], _ -> True
    _, [] -> False
    [s, ..small_rest], [l, ..large_rest] ->
      case s == l {
        True -> is_subsequence(small_rest, of: large_rest)
        False -> is_subsequence(small, of: large_rest)
      }
  }
}

pub fn larger_tolerance_keeps_a_subsequence_test() -> Nil {
  let route =
    generator.list_of(
      generator.map2(
        generator.float(from: -10.0, to: 10.0),
        generator.float(from: -10.0, to: 10.0),
        fn(lat, lng) { geokit.wrap_lat_lng(latitude: lat, longitude: lng) },
      ),
      length: generator.range(from: 0, to: 25),
    )
  metamon.forall(
    generator.tuple3(
      route,
      generator.float(from: 0.0, to: 2.0),
      generator.float(from: 0.0, to: 3.0),
    ),
    fn(input) {
      let #(points, small, extra) = input
      let assert Ok(fine) = simplify_line(points, tolerance: small)
      let assert Ok(coarse) = simplify_line(points, tolerance: small +. extra)
      assert is_subsequence(coarse, of: fine)
      assert list.length(coarse) <= list.length(fine)
    },
  )
}

// --- API adapters ----------------------------------------------------------

fn simplify_line(
  points: List(LatLng),
  tolerance tolerance: Float,
) -> Result(List(LatLng), Nil) {
  case geokit.simplify(geokit.LineString(points), tolerance:) {
    Ok(geokit.LineString(simplified)) -> Ok(simplified)
    _ -> Error(Nil)
  }
}
