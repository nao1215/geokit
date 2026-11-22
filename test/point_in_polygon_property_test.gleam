//// Property-based and metamorphic tests for `geokit/point_in_polygon`.
////
//// Every generated coordinate is a whole number of degrees. The
//// classifier only subtracts and multiplies coordinates, and those
//// operations are exact on integer-valued floats of this magnitude,
//// so the relations below must hold exactly — including for points
//// that sit on a ring — rather than up to rounding.
////
//// - Translating the polygon and the point by the same offset, or
////   mirroring both across the equator / prime meridian, does not
////   change the answer.
//// - Ring orientation, the ring's starting vertex, and whether the
////   ring repeats its first vertex at the end do not change the
////   answer.
//// - Every vertex and every edge midpoint of a ring is on the
////   boundary; a point outside the bounding box is outside.
//// - Axis-aligned rectangles with a rectangular hole, and diamonds,
////   agree with a closed-form oracle.
//// - `contains` is `locate` with the boundary counted as inside, and
////   a `MultiPolygon` is the union of its members.

import gleam/float
import gleam/int
import gleam/list
import gleam/result
import metamon
import metamon/generator.{type Generator}
import metamon/generator/range

import geokit.{type LatLng, type Location, Inside, OnBoundary, Outside}

// --- Generators ----------------------------------------------------------

fn whole_degrees(lo: Int, hi: Int) -> Generator(Float) {
  generator.int(range.constant(lo, hi)) |> generator.map(int.to_float)
}

/// Points on a whole-degree grid well inside the valid domain, so a
/// translation by `offset_gen` stays inside it.
fn grid_point_gen() -> Generator(LatLng) {
  generator.map2(whole_degrees(-40, 40), whole_degrees(-80, 80), fn(lat, lng) {
    geokit.wrap_lat_lng(latitude: lat, longitude: lng)
  })
}

/// Arbitrary rings: unclosed, possibly self-intersecting, possibly
/// with repeated or collinear vertices.
fn ring_gen() -> Generator(List(LatLng)) {
  generator.list_of(grid_point_gen(), range.constant(3, 8))
}

/// An exterior ring plus zero to two arbitrary hole rings.
fn rings_gen() -> Generator(List(List(LatLng))) {
  generator.list_of(ring_gen(), range.constant(1, 3))
}

fn offset_gen() -> Generator(#(Float, Float)) {
  generator.tuple2(whole_degrees(-40, 40), whole_degrees(-80, 80))
}

// --- Helpers -------------------------------------------------------------

fn locate_in(rings: List(List(LatLng)), point: LatLng) -> Location {
  case geokit.locate(point, in: geokit.Polygon(rings)) {
    Ok(location) -> location
    Error(Nil) -> Outside
  }
}

fn map_rings(
  rings: List(List(LatLng)),
  transform: fn(LatLng) -> LatLng,
) -> List(List(LatLng)) {
  list.map(rings, fn(ring) { list.map(ring, transform) })
}

fn translate_by(offset: #(Float, Float)) -> fn(LatLng) -> LatLng {
  fn(point) {
    geokit.wrap_lat_lng(
      latitude: geokit.latitude(point) +. offset.0,
      longitude: geokit.longitude(point) +. offset.1,
    )
  }
}

fn mirror(point: LatLng) -> LatLng {
  geokit.wrap_lat_lng(
    latitude: 0.0 -. geokit.latitude(point),
    longitude: geokit.longitude(point),
  )
}

fn mirror_lng(point: LatLng) -> LatLng {
  geokit.wrap_lat_lng(
    latitude: geokit.latitude(point),
    longitude: 0.0 -. geokit.longitude(point),
  )
}

fn rotate(ring: List(LatLng), by: Int) -> List(LatLng) {
  let shift = by % int.max(list.length(ring), 1)
  list.append(list.drop(ring, shift), list.take(ring, shift))
}

fn close(ring: List(LatLng)) -> List(LatLng) {
  case ring {
    [] -> []
    [first, ..] -> list.append(ring, [first])
  }
}

fn midpoint(a: LatLng, b: LatLng) -> LatLng {
  geokit.wrap_lat_lng(
    latitude: { geokit.latitude(a) +. geokit.latitude(b) } /. 2.0,
    longitude: { geokit.longitude(a) +. geokit.longitude(b) } /. 2.0,
  )
}

fn edges(ring: List(LatLng)) -> List(#(LatLng, LatLng)) {
  list.zip(ring, rotate(ring, 1))
}

// --- Metamorphic relations on arbitrary polygons -------------------------

pub fn pbt_translation_invariant_test() -> Nil {
  metamon.forall(
    generator.tuple3(rings_gen(), grid_point_gen(), offset_gen()),
    fn(input) {
      let #(rings, point, offset) = input
      let shift = translate_by(offset)
      locate_in(rings, point)
      == locate_in(map_rings(rings, shift), shift(point))
    },
  )
}

pub fn pbt_mirror_invariant_test() -> Nil {
  // Mirroring flips the ring's orientation and turns the ray-casting
  // tie-break for vertices upside down; the answer must not move.
  metamon.forall(generator.tuple2(rings_gen(), grid_point_gen()), fn(input) {
    let #(rings, point) = input
    let original = locate_in(rings, point)
    original == locate_in(map_rings(rings, mirror), mirror(point))
    && original == locate_in(map_rings(rings, mirror_lng), mirror_lng(point))
  })
}

pub fn pbt_orientation_invariant_test() -> Nil {
  metamon.forall(generator.tuple2(rings_gen(), grid_point_gen()), fn(input) {
    let #(rings, point) = input
    locate_in(rings, point) == locate_in(list.map(rings, list.reverse), point)
  })
}

pub fn pbt_start_vertex_invariant_test() -> Nil {
  metamon.forall(
    generator.tuple3(
      rings_gen(),
      grid_point_gen(),
      generator.int(range.constant(0, 7)),
    ),
    fn(input) {
      let #(rings, point, shift) = input
      let rotated = list.map(rings, fn(ring) { rotate(ring, shift) })
      locate_in(rings, point) == locate_in(rotated, point)
    },
  )
}

pub fn pbt_closing_vertex_invariant_test() -> Nil {
  metamon.forall(generator.tuple2(rings_gen(), grid_point_gen()), fn(input) {
    let #(rings, point) = input
    locate_in(rings, point) == locate_in(list.map(rings, close), point)
  })
}

// --- Invariants ----------------------------------------------------------

pub fn pbt_vertices_are_on_boundary_test() -> Nil {
  metamon.forall(ring_gen(), fn(ring) {
    list.all(ring, fn(vertex) { locate_in([ring], vertex) == OnBoundary })
  })
}

pub fn pbt_edge_midpoints_are_on_boundary_test() -> Nil {
  // Includes the implicit closing edge from the last vertex back to
  // the first.
  metamon.forall(ring_gen(), fn(ring) {
    list.all(edges(ring), fn(edge) {
      locate_in([ring], midpoint(edge.0, edge.1)) == OnBoundary
    })
  })
}

pub fn pbt_outside_bbox_is_outside_test() -> Nil {
  metamon.forall(generator.tuple2(rings_gen(), grid_point_gen()), fn(input) {
    let #(rings, point) = input
    case bbox(geokit.Polygon(rings)) {
      Error(Nil) -> locate_in(rings, point) == Outside
      Ok(#(sw, ne)) ->
        within(point, sw, ne) || locate_in(rings, point) == Outside
    }
  })
}

fn within(point: LatLng, sw: LatLng, ne: LatLng) -> Bool {
  geokit.latitude(sw) <=. geokit.latitude(point)
  && geokit.latitude(point) <=. geokit.latitude(ne)
  && geokit.longitude(sw) <=. geokit.longitude(point)
  && geokit.longitude(point) <=. geokit.longitude(ne)
}

pub fn pbt_contains_is_locate_with_boundary_test() -> Nil {
  metamon.forall(generator.tuple2(rings_gen(), grid_point_gen()), fn(input) {
    let #(rings, point) = input
    let polygon = geokit.Polygon(rings)
    contains_point(point, in: polygon) == Ok(locate_in(rings, point) != Outside)
  })
}

// --- MultiPolygon is the union of its members ----------------------------

pub fn pbt_single_member_multipolygon_matches_polygon_test() -> Nil {
  metamon.forall(generator.tuple2(rings_gen(), grid_point_gen()), fn(input) {
    let #(rings, point) = input
    geokit.locate(point, in: geokit.MultiPolygon([rings]))
    == Ok(locate_in(rings, point))
  })
}

pub fn pbt_multipolygon_contains_is_union_test() -> Nil {
  metamon.forall(
    generator.tuple3(rings_gen(), rings_gen(), grid_point_gen()),
    fn(input) {
      let #(first, second, point) = input
      let union = geokit.MultiPolygon([first, second])
      let expected =
        locate_in(first, point) != Outside
        || locate_in(second, point) != Outside
      contains_point(point, in: union) == Ok(expected)
    },
  )
}

pub fn pbt_multipolygon_member_order_invariant_test() -> Nil {
  metamon.forall(
    generator.tuple3(rings_gen(), rings_gen(), grid_point_gen()),
    fn(input) {
      let #(first, second, point) = input
      geokit.locate(point, in: geokit.MultiPolygon([first, second]))
      == geokit.locate(point, in: geokit.MultiPolygon([second, first]))
    },
  )
}

// --- Closed-form oracles -------------------------------------------------

/// Axis-aligned rectangle bounded by two parallels and two meridians.
type Rect {
  Rect(south: Float, west: Float, north: Float, east: Float)
}

fn rect_ring(rect: Rect) -> List(LatLng) {
  [
    geokit.wrap_lat_lng(latitude: rect.south, longitude: rect.west),
    geokit.wrap_lat_lng(latitude: rect.south, longitude: rect.east),
    geokit.wrap_lat_lng(latitude: rect.north, longitude: rect.east),
    geokit.wrap_lat_lng(latitude: rect.north, longitude: rect.west),
    geokit.wrap_lat_lng(latitude: rect.south, longitude: rect.west),
  ]
}

fn exterior_gen() -> Generator(Rect) {
  generator.map4(
    whole_degrees(-40, -10),
    whole_degrees(-80, -20),
    whole_degrees(10, 40),
    whole_degrees(20, 80),
    Rect,
  )
}

/// A hole that always lies strictly inside every `exterior_gen` value.
fn hole_gen() -> Generator(Rect) {
  generator.map4(
    whole_degrees(-8, -1),
    whole_degrees(-15, -1),
    whole_degrees(1, 8),
    whole_degrees(1, 15),
    Rect,
  )
}

fn probe_gen() -> Generator(LatLng) {
  generator.map2(whole_degrees(-45, 45), whole_degrees(-85, 85), fn(lat, lng) {
    geokit.wrap_lat_lng(latitude: lat, longitude: lng)
  })
}

fn rect_location(rect: Rect, point: LatLng) -> Location {
  let lat = geokit.latitude(point)
  let lng = geokit.longitude(point)
  let in_lat = rect.south <=. lat && lat <=. rect.north
  let in_lng = rect.west <=. lng && lng <=. rect.east
  let on_edge =
    lat == rect.south
    || lat == rect.north
    || lng == rect.west
    || lng == rect.east
  case in_lat && in_lng, on_edge {
    False, _ -> Outside
    True, True -> OnBoundary
    True, False -> Inside
  }
}

fn rect_with_hole_location(
  exterior: Rect,
  hole: Rect,
  point: LatLng,
) -> Location {
  case rect_location(exterior, point), rect_location(hole, point) {
    Outside, _ -> Outside
    OnBoundary, _ -> OnBoundary
    Inside, Outside -> Inside
    Inside, OnBoundary -> OnBoundary
    Inside, Inside -> Outside
  }
}

pub fn pbt_rectangle_with_hole_matches_oracle_test() -> Nil {
  metamon.forall(
    generator.tuple4(exterior_gen(), hole_gen(), probe_gen(), generator.bool()),
    fn(input) {
      let #(exterior, hole, point, clockwise) = input
      let orient = case clockwise {
        True -> list.reverse
        False -> fn(ring) { ring }
      }
      let rings = [orient(rect_ring(exterior)), orient(rect_ring(hole))]
      locate_in(rings, point) == rect_with_hole_location(exterior, hole, point)
    },
  )
}

pub fn pbt_diamond_matches_oracle_test() -> Nil {
  // A diamond (a square rotated 45°) centred at `centre` with
  // "radius" `radius`: the Manhattan distance from the centre decides
  // the answer. Its east and west vertices share the centre's
  // latitude, so rays through vertices are exercised constantly.
  metamon.forall(
    generator.tuple3(
      grid_point_gen(),
      whole_degrees(1, 9),
      generator.tuple2(whole_degrees(-10, 10), whole_degrees(-10, 10)),
    ),
    fn(input) {
      let #(centre, radius, delta) = input
      let lat = geokit.latitude(centre)
      let lng = geokit.longitude(centre)
      let ring = [
        geokit.wrap_lat_lng(latitude: lat -. radius, longitude: lng),
        geokit.wrap_lat_lng(latitude: lat, longitude: lng +. radius),
        geokit.wrap_lat_lng(latitude: lat +. radius, longitude: lng),
        geokit.wrap_lat_lng(latitude: lat, longitude: lng -. radius),
      ]
      let point = translate_by(delta)(centre)
      let manhattan =
        float.absolute_value(delta.0) +. float.absolute_value(delta.1)
      let expected = case manhattan <. radius, manhattan == radius {
        True, _ -> Inside
        False, True -> OnBoundary
        False, False -> Outside
      }
      locate_in([ring], point) == expected
    },
  )
}

// --- API adapters ----------------------------------------------------------

fn contains_point(
  point: LatLng,
  in geometry: geokit.Geometry,
) -> Result(Bool, Nil) {
  geokit.locate(point, in: geometry)
  |> result.map(fn(location) { location != geokit.Outside })
}

fn bbox(geometry: geokit.Geometry) -> Result(#(LatLng, LatLng), Nil) {
  geokit.bounding_box(geometry)
  |> result.map(fn(box) { #(box.south_west, box.north_east) })
}
