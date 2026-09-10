import gleam/list
import gleeunit/should

import geokit/geometry
import geokit/latlng.{type LatLng}
import geokit/point_in_polygon.{Inside, OnBoundary, Outside}

// --- helpers -------------------------------------------------------------

fn at(lat: Float, lng: Float) -> LatLng {
  latlng.new_or_panic(lat: lat, lng: lng)
}

/// Closed 10 × 10 square with corners at (0, 0) and (10, 10).
fn square_ring() -> List(LatLng) {
  [at(0.0, 0.0), at(0.0, 10.0), at(10.0, 10.0), at(10.0, 0.0), at(0.0, 0.0)]
}

/// Closed 4 × 4 hole centred inside `square_ring`.
fn hole_ring() -> List(LatLng) {
  [at(3.0, 3.0), at(7.0, 3.0), at(7.0, 7.0), at(3.0, 7.0), at(3.0, 3.0)]
}

fn square() -> geometry.Geometry {
  geometry.Polygon([square_ring()])
}

fn square_with_hole() -> geometry.Geometry {
  geometry.Polygon([square_ring(), hole_ring()])
}

fn locate(geometry: geometry.Geometry, lat: Float, lng: Float) {
  point_in_polygon.locate(geometry: geometry, point: at(lat, lng))
}

fn contains(geometry: geometry.Geometry, lat: Float, lng: Float) {
  point_in_polygon.contains(geometry: geometry, point: at(lat, lng))
}

// --- inside / outside ----------------------------------------------------

pub fn inside_square_test() -> Nil {
  locate(square(), 5.0, 5.0) |> should.equal(Ok(Inside))
  contains(square(), 5.0, 5.0) |> should.equal(Ok(True))
}

pub fn outside_square_test() -> Nil {
  locate(square(), 15.0, 5.0) |> should.equal(Ok(Outside))
  locate(square(), 5.0, -1.0) |> should.equal(Ok(Outside))
  locate(square(), -0.5, -0.5) |> should.equal(Ok(Outside))
  contains(square(), 15.0, 5.0) |> should.equal(Ok(False))
}

// --- boundary ------------------------------------------------------------

pub fn on_horizontal_edge_is_boundary_test() -> Nil {
  locate(square(), 0.0, 5.0) |> should.equal(Ok(OnBoundary))
  locate(square(), 10.0, 5.0) |> should.equal(Ok(OnBoundary))
}

pub fn on_vertical_edge_is_boundary_test() -> Nil {
  locate(square(), 5.0, 0.0) |> should.equal(Ok(OnBoundary))
  locate(square(), 5.0, 10.0) |> should.equal(Ok(OnBoundary))
}

pub fn on_diagonal_edge_is_boundary_test() -> Nil {
  let triangle =
    geometry.Polygon([[at(0.0, 0.0), at(0.0, 4.0), at(4.0, 0.0), at(0.0, 0.0)]])
  locate(triangle, 2.0, 2.0) |> should.equal(Ok(OnBoundary))
  locate(triangle, 1.0, 1.0) |> should.equal(Ok(Inside))
  locate(triangle, 3.0, 3.0) |> should.equal(Ok(Outside))
}

pub fn on_vertex_is_boundary_test() -> Nil {
  locate(square(), 0.0, 0.0) |> should.equal(Ok(OnBoundary))
  locate(square(), 10.0, 10.0) |> should.equal(Ok(OnBoundary))
  locate(square(), 0.0, 10.0) |> should.equal(Ok(OnBoundary))
  locate(square(), 10.0, 0.0) |> should.equal(Ok(OnBoundary))
}

pub fn contains_includes_boundary_test() -> Nil {
  // `contains` mirrors Turf's booleanPointInPolygon default: points on
  // the boundary count as contained.
  contains(square(), 0.0, 5.0) |> should.equal(Ok(True))
  contains(square(), 10.0, 10.0) |> should.equal(Ok(True))
}

pub fn boundary_excluded_via_locate_test() -> Nil {
  // Turf's `ignoreBoundary: true` is `locate(...) == Ok(Inside)`.
  { locate(square(), 0.0, 5.0) == Ok(Inside) } |> should.be_false
  { locate(square(), 5.0, 5.0) == Ok(Inside) } |> should.be_true
}

// --- holes ---------------------------------------------------------------

pub fn inside_hole_is_outside_test() -> Nil {
  locate(square_with_hole(), 5.0, 5.0) |> should.equal(Ok(Outside))
  contains(square_with_hole(), 5.0, 5.0) |> should.equal(Ok(False))
}

pub fn between_exterior_and_hole_is_inside_test() -> Nil {
  locate(square_with_hole(), 1.0, 1.0) |> should.equal(Ok(Inside))
  locate(square_with_hole(), 5.0, 8.5) |> should.equal(Ok(Inside))
  locate(square_with_hole(), 5.0, 1.5) |> should.equal(Ok(Inside))
}

pub fn on_hole_edge_is_boundary_test() -> Nil {
  locate(square_with_hole(), 3.0, 5.0) |> should.equal(Ok(OnBoundary))
  locate(square_with_hole(), 5.0, 7.0) |> should.equal(Ok(OnBoundary))
  contains(square_with_hole(), 3.0, 5.0) |> should.equal(Ok(True))
}

pub fn on_hole_vertex_is_boundary_test() -> Nil {
  locate(square_with_hole(), 3.0, 3.0) |> should.equal(Ok(OnBoundary))
  locate(square_with_hole(), 7.0, 7.0) |> should.equal(Ok(OnBoundary))
}

pub fn hole_outside_exterior_is_ignored_test() -> Nil {
  // An invalid "hole" lying outside the exterior ring removes nothing
  // and adds nothing: a point is only inside when it is inside the
  // exterior ring and not inside any hole.
  let stray_hole = [
    at(20.0, 20.0),
    at(20.0, 30.0),
    at(30.0, 30.0),
    at(30.0, 20.0),
    at(20.0, 20.0),
  ]
  let polygon = geometry.Polygon([square_ring(), stray_hole])
  locate(polygon, 25.0, 25.0) |> should.equal(Ok(Outside))
  locate(polygon, 20.0, 25.0) |> should.equal(Ok(Outside))
  locate(polygon, 5.0, 5.0) |> should.equal(Ok(Inside))
}

// --- concave polygons ----------------------------------------------------

/// A "U": the notch between the two arms spans lat 3..10, lng 3..7.
fn u_shape() -> geometry.Geometry {
  geometry.Polygon([
    [
      at(0.0, 0.0),
      at(0.0, 10.0),
      at(10.0, 10.0),
      at(10.0, 7.0),
      at(3.0, 7.0),
      at(3.0, 3.0),
      at(10.0, 3.0),
      at(10.0, 0.0),
      at(0.0, 0.0),
    ],
  ])
}

pub fn concave_notch_is_outside_test() -> Nil {
  // The eastward ray from the notch crosses the right arm twice.
  locate(u_shape(), 5.0, 5.0) |> should.equal(Ok(Outside))
  locate(u_shape(), 9.0, 5.0) |> should.equal(Ok(Outside))
}

pub fn concave_arms_are_inside_test() -> Nil {
  locate(u_shape(), 5.0, 1.5) |> should.equal(Ok(Inside))
  locate(u_shape(), 5.0, 8.5) |> should.equal(Ok(Inside))
  locate(u_shape(), 1.0, 5.0) |> should.equal(Ok(Inside))
}

pub fn concave_notch_edges_are_boundary_test() -> Nil {
  locate(u_shape(), 3.0, 5.0) |> should.equal(Ok(OnBoundary))
  locate(u_shape(), 5.0, 3.0) |> should.equal(Ok(OnBoundary))
  locate(u_shape(), 5.0, 7.0) |> should.equal(Ok(OnBoundary))
}

/// An "L": the missing north-east quadrant is lat 5..10, lng 5..10.
fn l_shape() -> geometry.Geometry {
  geometry.Polygon([
    [
      at(0.0, 0.0),
      at(0.0, 10.0),
      at(5.0, 10.0),
      at(5.0, 5.0),
      at(10.0, 5.0),
      at(10.0, 0.0),
      at(0.0, 0.0),
    ],
  ])
}

pub fn ray_along_horizontal_edge_test() -> Nil {
  // The eastward ray from (5, 2) runs along the horizontal edge
  // (5, 5)-(5, 10) and through both of its vertices.
  locate(l_shape(), 5.0, 2.0) |> should.equal(Ok(Inside))
  locate(l_shape(), 5.0, -2.0) |> should.equal(Ok(Outside))
  locate(l_shape(), 5.0, 12.0) |> should.equal(Ok(Outside))
  locate(l_shape(), 5.0, 7.0) |> should.equal(Ok(OnBoundary))
  locate(l_shape(), 7.0, 7.0) |> should.equal(Ok(Outside))
  locate(l_shape(), 7.0, 2.0) |> should.equal(Ok(Inside))
}

// --- ray-casting pitfalls ------------------------------------------------

pub fn left_and_right_of_vertical_edges_test() -> Nil {
  locate(square(), 5.0, -1.0) |> should.equal(Ok(Outside))
  locate(square(), 5.0, 0.5) |> should.equal(Ok(Inside))
  locate(square(), 5.0, 9.5) |> should.equal(Ok(Inside))
  locate(square(), 5.0, 11.0) |> should.equal(Ok(Outside))
  // Just either side of the edge, not on it.
  locate(square(), 5.0, 1.0e-9) |> should.equal(Ok(Inside))
  locate(square(), 5.0, -1.0e-9) |> should.equal(Ok(Outside))
}

/// A diamond whose east and west vertices share the latitude of its
/// centre, so an eastward ray from the centre row passes through a
/// vertex.
fn diamond() -> geometry.Geometry {
  geometry.Polygon([
    [at(0.0, 5.0), at(5.0, 10.0), at(10.0, 5.0), at(5.0, 0.0), at(0.0, 5.0)],
  ])
}

pub fn ray_through_vertex_test() -> Nil {
  locate(diamond(), 5.0, 2.0) |> should.equal(Ok(Inside))
  locate(diamond(), 5.0, 5.0) |> should.equal(Ok(Inside))
  // Rays through both the west and the east vertex.
  locate(diamond(), 5.0, -2.0) |> should.equal(Ok(Outside))
  locate(diamond(), 5.0, 12.0) |> should.equal(Ok(Outside))
}

pub fn ray_grazing_top_and_bottom_vertex_test() -> Nil {
  // The eastward rays touch the diamond only at its north / south
  // vertex without entering it.
  locate(diamond(), 10.0, 2.0) |> should.equal(Ok(Outside))
  locate(diamond(), 0.0, 2.0) |> should.equal(Ok(Outside))
  locate(diamond(), 10.0, 5.0) |> should.equal(Ok(OnBoundary))
  locate(diamond(), 0.0, 5.0) |> should.equal(Ok(OnBoundary))
}

// --- ring shape ----------------------------------------------------------

pub fn unclosed_ring_matches_closed_ring_test() -> Nil {
  let unclosed =
    geometry.Polygon([
      [at(0.0, 0.0), at(0.0, 10.0), at(10.0, 10.0), at(10.0, 0.0)],
    ])
  let probes = [
    #(5.0, 5.0),
    #(15.0, 5.0),
    #(5.0, 0.0),
    #(0.0, 5.0),
    #(0.0, 0.0),
    #(5.0, 0.5),
  ]
  list.each(probes, fn(probe) {
    locate(unclosed, probe.0, probe.1)
    |> should.equal(locate(square(), probe.0, probe.1))
  })
  // The implicit closing edge (10, 0)-(0, 0) is part of the boundary.
  locate(unclosed, 5.0, 0.0) |> should.equal(Ok(OnBoundary))
}

pub fn ring_orientation_does_not_matter_test() -> Nil {
  let clockwise = geometry.Polygon([list.reverse(square_ring())])
  locate(clockwise, 5.0, 5.0) |> should.equal(Ok(Inside))
  locate(clockwise, 15.0, 5.0) |> should.equal(Ok(Outside))
  locate(clockwise, 0.0, 5.0) |> should.equal(Ok(OnBoundary))
}

pub fn empty_polygon_contains_nothing_test() -> Nil {
  locate(geometry.Polygon([]), 0.0, 0.0) |> should.equal(Ok(Outside))
  locate(geometry.Polygon([[]]), 0.0, 0.0) |> should.equal(Ok(Outside))
  contains(geometry.Polygon([]), 0.0, 0.0) |> should.equal(Ok(False))
}

pub fn two_point_ring_has_no_interior_test() -> Nil {
  let sliver = geometry.Polygon([[at(0.0, 0.0), at(0.0, 10.0)]])
  locate(sliver, 0.0, 5.0) |> should.equal(Ok(OnBoundary))
  locate(sliver, 1.0, 5.0) |> should.equal(Ok(Outside))
  locate(sliver, 0.0, 11.0) |> should.equal(Ok(Outside))
}

pub fn collinear_ring_has_no_interior_test() -> Nil {
  let flat =
    geometry.Polygon([
      [at(0.0, 0.0), at(5.0, 5.0), at(10.0, 10.0), at(0.0, 0.0)],
    ])
  locate(flat, 2.0, 2.0) |> should.equal(Ok(OnBoundary))
  locate(flat, 2.0, 3.0) |> should.equal(Ok(Outside))
  locate(flat, 11.0, 11.0) |> should.equal(Ok(Outside))
}

pub fn repeated_vertices_are_harmless_test() -> Nil {
  let stuttering =
    geometry.Polygon([
      [
        at(0.0, 0.0),
        at(0.0, 0.0),
        at(0.0, 10.0),
        at(10.0, 10.0),
        at(10.0, 10.0),
        at(10.0, 0.0),
        at(0.0, 0.0),
      ],
    ])
  locate(stuttering, 5.0, 5.0) |> should.equal(Ok(Inside))
  locate(stuttering, 10.0, 5.0) |> should.equal(Ok(OnBoundary))
  locate(stuttering, 5.0, 11.0) |> should.equal(Ok(Outside))
}

// --- real-world coordinates ---------------------------------------------

pub fn tokyo_station_inside_chiyoda_box_test() -> Nil {
  let chiyoda =
    geometry.Polygon([
      [
        at(35.67, 139.74),
        at(35.67, 139.78),
        at(35.705, 139.78),
        at(35.705, 139.74),
        at(35.67, 139.74),
      ],
    ])
  locate(chiyoda, 35.6812, 139.7671) |> should.equal(Ok(Inside))
  locate(chiyoda, 34.6937, 135.5023) |> should.equal(Ok(Outside))
}

// --- antimeridian --------------------------------------------------------

pub fn ring_across_antimeridian_is_read_as_planar_test() -> Nil {
  // The ring is interpreted on the flat lng/lat plane, so a ring
  // with vertices at lng 170 and lng -170 encloses the wide band
  // through lng 0, not the narrow band across lng 180.
  let band =
    geometry.Polygon([
      [
        at(0.0, 170.0),
        at(0.0, -170.0),
        at(10.0, -170.0),
        at(10.0, 170.0),
        at(0.0, 170.0),
      ],
    ])
  locate(band, 5.0, 0.0) |> should.equal(Ok(Inside))
  locate(band, 5.0, 179.0) |> should.equal(Ok(Outside))
}

pub fn antimeridian_split_multipolygon_test() -> Nil {
  // The RFC 7946 §3.1.9 way: cut the shape at the antimeridian.
  let split =
    geometry.MultiPolygon([
      [
        [
          at(0.0, 170.0),
          at(0.0, 180.0),
          at(10.0, 180.0),
          at(10.0, 170.0),
          at(0.0, 170.0),
        ],
      ],
      [
        [
          at(0.0, -180.0),
          at(0.0, -170.0),
          at(10.0, -170.0),
          at(10.0, -180.0),
          at(0.0, -180.0),
        ],
      ],
    ])
  locate(split, 5.0, 179.0) |> should.equal(Ok(Inside))
  locate(split, 5.0, -179.0) |> should.equal(Ok(Inside))
  locate(split, 5.0, 180.0) |> should.equal(Ok(OnBoundary))
  locate(split, 5.0, 0.0) |> should.equal(Ok(Outside))
}

// --- multipolygon --------------------------------------------------------

fn far_square_rings() -> List(List(LatLng)) {
  [
    [
      at(20.0, 20.0),
      at(20.0, 30.0),
      at(30.0, 30.0),
      at(30.0, 20.0),
      at(20.0, 20.0),
    ],
  ]
}

pub fn multipolygon_inside_any_member_test() -> Nil {
  let both = geometry.MultiPolygon([[square_ring()], far_square_rings()])
  locate(both, 5.0, 5.0) |> should.equal(Ok(Inside))
  locate(both, 25.0, 25.0) |> should.equal(Ok(Inside))
  locate(both, 15.0, 15.0) |> should.equal(Ok(Outside))
  locate(both, 20.0, 25.0) |> should.equal(Ok(OnBoundary))
  contains(both, 15.0, 15.0) |> should.equal(Ok(False))
}

pub fn multipolygon_island_inside_hole_test() -> Nil {
  // A lake (hole) with an island (second polygon) inside it.
  let island = [
    [at(4.0, 4.0), at(4.0, 6.0), at(6.0, 6.0), at(6.0, 4.0), at(4.0, 4.0)],
  ]
  let lake_with_island =
    geometry.MultiPolygon([[square_ring(), hole_ring()], island])
  locate(lake_with_island, 5.0, 5.0) |> should.equal(Ok(Inside))
  locate(lake_with_island, 3.5, 3.5) |> should.equal(Ok(Outside))
  locate(lake_with_island, 1.0, 1.0) |> should.equal(Ok(Inside))
  locate(lake_with_island, 4.0, 5.0) |> should.equal(Ok(OnBoundary))
}

pub fn multipolygon_members_touching_at_edge_test() -> Nil {
  // Two squares sharing the edge lng = 10: a point on the shared edge
  // is on the boundary of both members.
  let east = [
    [
      at(0.0, 10.0),
      at(0.0, 20.0),
      at(10.0, 20.0),
      at(10.0, 10.0),
      at(0.0, 10.0),
    ],
  ]
  let pair = geometry.MultiPolygon([[square_ring()], east])
  locate(pair, 5.0, 10.0) |> should.equal(Ok(OnBoundary))
  locate(pair, 5.0, 15.0) |> should.equal(Ok(Inside))
}

pub fn empty_multipolygon_contains_nothing_test() -> Nil {
  locate(geometry.MultiPolygon([]), 0.0, 0.0) |> should.equal(Ok(Outside))
  contains(geometry.MultiPolygon([]), 0.0, 0.0) |> should.equal(Ok(False))
}

// --- non-areal geometries ------------------------------------------------

pub fn non_polygon_geometries_are_rejected_test() -> Nil {
  let p = at(0.0, 0.0)
  let rejected = [
    geometry.Point(p),
    geometry.MultiPoint([p]),
    geometry.LineString([p, at(1.0, 1.0)]),
  ]
  list.each(rejected, fn(geometry) {
    point_in_polygon.locate(geometry: geometry, point: p)
    |> should.equal(Error(point_in_polygon.NotAPolygon))
    point_in_polygon.contains(geometry: geometry, point: p)
    |> should.equal(Error(point_in_polygon.NotAPolygon))
  })
}
