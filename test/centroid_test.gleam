import gleam/int
import gleam/list
import gleeunit/should

import geokit/centroid
import geokit/geometry
import geokit/latlng

fn approx_equal(a: Float, b: Float, tolerance: Float) -> Bool {
  let delta = case a >. b {
    True -> a -. b
    False -> b -. a
  }
  delta <=. tolerance
}

// --- point ---------------------------------------------------------------

pub fn centroid_of_point_test() -> Nil {
  let assert Ok(p) = latlng.new(lat: 35.6812, lng: 139.7671)
  let assert Ok(c) = centroid.compute(geometry: geometry.Point(p))
  latlng.equal(c, p)
  |> should.be_true
}

// --- line string ---------------------------------------------------------

pub fn centroid_of_line_string_test() -> Nil {
  // Mean of (0,0), (0,2), (2,0), (2,2) is (1,1).
  let assert Ok(a) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(b) = latlng.new(lat: 0.0, lng: 2.0)
  let assert Ok(c) = latlng.new(lat: 2.0, lng: 0.0)
  let assert Ok(d) = latlng.new(lat: 2.0, lng: 2.0)
  let assert Ok(centre) =
    centroid.compute(geometry: geometry.LineString([a, b, c, d]))
  latlng.lat(centre)
  |> should.equal(1.0)
  latlng.lng(centre)
  |> should.equal(1.0)
}

// --- polygon (unit square) ----------------------------------------------

pub fn centroid_of_unit_square_test() -> Nil {
  // Unit square centroid is at (0.5, 0.5).
  let assert Ok(a) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(b) = latlng.new(lat: 0.0, lng: 1.0)
  let assert Ok(c) = latlng.new(lat: 1.0, lng: 1.0)
  let assert Ok(d) = latlng.new(lat: 1.0, lng: 0.0)
  let assert Ok(centre) =
    centroid.compute(geometry: geometry.Polygon([[a, b, c, d, a]]))
  approx_equal(latlng.lat(centre), 0.5, 0.0001)
  |> should.be_true
  approx_equal(latlng.lng(centre), 0.5, 0.0001)
  |> should.be_true
}

pub fn centroid_of_offset_square_test() -> Nil {
  // Square from (10, 20) to (12, 22) has centroid (11, 21).
  let assert Ok(a) = latlng.new(lat: 10.0, lng: 20.0)
  let assert Ok(b) = latlng.new(lat: 10.0, lng: 22.0)
  let assert Ok(c) = latlng.new(lat: 12.0, lng: 22.0)
  let assert Ok(d) = latlng.new(lat: 12.0, lng: 20.0)
  let assert Ok(centre) =
    centroid.compute(geometry: geometry.Polygon([[a, b, c, d, a]]))
  approx_equal(latlng.lat(centre), 11.0, 0.0001)
  |> should.be_true
  approx_equal(latlng.lng(centre), 21.0, 0.0001)
  |> should.be_true
}

// --- empty ---------------------------------------------------------------

pub fn centroid_empty_line_test() -> Nil {
  case centroid.compute(geometry: geometry.LineString([])) {
    Error(centroid.EmptyGeometry) -> Nil
    _ -> should.be_true(False)
  }
}

// --- of_points (List(LatLng) convenience wrapper) -----------------------

pub fn centroid_of_points_matches_line_string_test() -> Nil {
  let assert Ok(a) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(b) = latlng.new(lat: 0.0, lng: 2.0)
  let assert Ok(c) = latlng.new(lat: 2.0, lng: 0.0)
  let assert Ok(d) = latlng.new(lat: 2.0, lng: 2.0)
  let assert Ok(via_helper) = centroid.of_points([a, b, c, d])
  let assert Ok(via_geom) =
    centroid.compute(geometry: geometry.LineString([a, b, c, d]))
  latlng.equal(via_helper, via_geom)
  |> should.be_true
  latlng.lat(via_helper)
  |> should.equal(1.0)
  latlng.lng(via_helper)
  |> should.equal(1.0)
}

pub fn centroid_of_points_single_test() -> Nil {
  let assert Ok(p) = latlng.new(lat: 35.6812, lng: 139.7671)
  let assert Ok(c) = centroid.of_points([p])
  latlng.equal(c, p)
  |> should.be_true
}

pub fn centroid_of_points_empty_test() -> Nil {
  case centroid.of_points([]) {
    Error(centroid.EmptyGeometry) -> Nil
    _ -> should.be_true(False)
  }
}

pub fn centroid_compute_multi_point_test() -> Nil {
  let assert Ok(a) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(b) = latlng.new(lat: 10.0, lng: 10.0)
  let assert Ok(via_multi) =
    centroid.compute(geometry: geometry.MultiPoint([a, b]))
  let assert Ok(via_line) =
    centroid.compute(geometry: geometry.LineString([a, b]))
  latlng.equal(via_multi, via_line) |> should.be_true
}

pub fn centroid_compute_multi_point_empty_test() -> Nil {
  case centroid.compute(geometry: geometry.MultiPoint([])) {
    Error(centroid.EmptyGeometry) -> Nil
    _ -> should.be_true(False)
  }
}

pub fn of_points_closed_ring_unit_square_returns_true_centroid_test() -> Nil {
  // GeoJSON-shaped closed ring (5 points, last duplicates first).
  // Pre-#26, the trailing (0, 0) was double-counted and the mean
  // came out at (0.4, 0.4). With closing-duplicate dedupe the
  // function now returns the unit square's true mean (0.5, 0.5).
  let assert Ok(a) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(b) = latlng.new(lat: 0.0, lng: 1.0)
  let assert Ok(c) = latlng.new(lat: 1.0, lng: 1.0)
  let assert Ok(d) = latlng.new(lat: 1.0, lng: 0.0)
  let assert Ok(e) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(centre) = centroid.of_points(points: [a, b, c, d, e])
  latlng.lat(centre) |> should.equal(0.5)
  latlng.lng(centre) |> should.equal(0.5)
}

pub fn of_points_unclosed_ring_uses_arithmetic_mean_test() -> Nil {
  let assert Ok(a) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(b) = latlng.new(lat: 0.0, lng: 1.0)
  let assert Ok(c) = latlng.new(lat: 1.0, lng: 1.0)
  let assert Ok(d) = latlng.new(lat: 1.0, lng: 0.0)
  let assert Ok(centre) = centroid.of_points(points: [a, b, c, d])
  latlng.lat(centre) |> should.equal(0.5)
  latlng.lng(centre) |> should.equal(0.5)
}

pub fn of_points_interior_adjacent_duplicates_are_kept_test() -> Nil {
  // Only the closing duplicate (last == first) is dropped. An
  // interior repeat is left alone because it may carry weight that
  // the caller intends.
  let assert Ok(a) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(b) = latlng.new(lat: 1.0, lng: 1.0)
  let assert Ok(centre) = centroid.of_points(points: [a, a, b])
  latlng.lng(centre) |> should.equal({ 0.0 +. 0.0 +. 1.0 } /. 3.0)
}

pub fn of_points_single_point_test() -> Nil {
  let assert Ok(only) = latlng.new(lat: 5.0, lng: 10.0)
  let assert Ok(centre) = centroid.of_points(points: [only])
  latlng.lat(centre) |> should.equal(5.0)
  latlng.lng(centre) |> should.equal(10.0)
}

pub fn of_points_empty_errors_test() -> Nil {
  case centroid.of_points(points: []) {
    Error(centroid.EmptyGeometry) -> Nil
    _ -> should.be_true(False)
  }
}

// --- long inputs (20_000 points) ----------------------------------------

// 20_000 points walking the perimeter of the square [0, 10] x [0, 10]
// counter-clockwise from (0, 0). The ring is not closed.
fn square_perimeter() -> List(latlng.LatLng) {
  list.repeat(Nil, times: 20_000)
  |> list.index_map(fn(_, i) {
    let side = i / 5000
    let t = int.to_float(i % 5000) /. 500.0
    case side {
      0 -> latlng.wrap(lat: 0.0, lng: t)
      1 -> latlng.wrap(lat: t, lng: 10.0)
      2 -> latlng.wrap(lat: 10.0, lng: 10.0 -. t)
      _ -> latlng.wrap(lat: 10.0 -. t, lng: 0.0)
    }
  })
}

pub fn centroid_of_long_polygon_test() -> Nil {
  let assert Ok(c) =
    centroid.compute(geometry: geometry.Polygon([square_perimeter()]))
  approx_equal(latlng.lat(c), 5.0, 1.0e-9)
  |> should.be_true
  approx_equal(latlng.lng(c), 5.0, 1.0e-9)
  |> should.be_true
}

pub fn centroid_of_long_closed_ring_points_test() -> Nil {
  let ring = square_perimeter()
  let closed = list.append(ring, list.take(ring, 1))
  let assert Ok(c) = centroid.of_points(points: closed)
  approx_equal(latlng.lat(c), 5.0, 1.0e-9)
  |> should.be_true
  approx_equal(latlng.lng(c), 5.0, 1.0e-9)
  |> should.be_true
}

pub fn of_points_closed_ring_with_signed_zero_test() -> Nil {
  // First (0.0, 0.0) and last (-0.0, -0.0) are the same vertex, so the
  // closing duplicate is dropped and the mean is the square's centre.
  let assert Ok(c) =
    centroid.of_points(points: [
      latlng.new_or_panic(lat: 0.0, lng: 0.0),
      latlng.new_or_panic(lat: 0.0, lng: 1.0),
      latlng.new_or_panic(lat: 1.0, lng: 1.0),
      latlng.new_or_panic(lat: 1.0, lng: 0.0),
      latlng.new_or_panic(lat: -0.0, lng: -0.0),
    ])
  #(latlng.lat(c), latlng.lng(c))
  |> should.equal(#(0.5, 0.5))
}

pub fn polygon_centroid_with_signed_zero_closure_test() -> Nil {
  // A closed triangle whose closing vertex is written with -0.0 must
  // not be closed a second time.
  let assert Ok(c) =
    centroid.compute(
      geometry: geometry.Polygon([
        [
          latlng.new_or_panic(lat: 0.0, lng: 0.0),
          latlng.new_or_panic(lat: 0.0, lng: 3.0),
          latlng.new_or_panic(lat: 3.0, lng: 0.0),
          latlng.new_or_panic(lat: -0.0, lng: -0.0),
        ],
      ]),
    )
  approx_equal(latlng.lat(c), 1.0, 1.0e-12)
  |> should.be_true
  approx_equal(latlng.lng(c), 1.0, 1.0e-12)
  |> should.be_true
}

// --- holes and multipolygons (area-weighted) -----------------------------

fn ring(coords: List(#(Float, Float))) -> List(latlng.LatLng) {
  list.map(coords, fn(c) { latlng.new_or_panic(lat: c.1, lng: c.0) })
}

// Coordinates are (lng, lat), as in Shapely.
fn outer_square() -> List(latlng.LatLng) {
  ring([#(0.0, 0.0), #(10.0, 0.0), #(10.0, 10.0), #(0.0, 10.0), #(0.0, 0.0)])
}

fn west_hole() -> List(latlng.LatLng) {
  ring([#(1.0, 1.0), #(1.0, 9.0), #(4.0, 9.0), #(4.0, 1.0), #(1.0, 1.0)])
}

fn small_square() -> List(latlng.LatLng) {
  ring([#(20.0, 0.0), #(22.0, 0.0), #(22.0, 2.0), #(20.0, 2.0), #(20.0, 0.0)])
}

fn close_to(c: latlng.LatLng, lng: Float, lat: Float) -> Nil {
  approx_equal(latlng.lng(c), lng, 1.0e-12)
  |> should.be_true
  approx_equal(latlng.lat(c), lat, 1.0e-12)
  |> should.be_true
}

pub fn centroid_of_polygon_with_hole_test() -> Nil {
  // Shapely: Polygon(square, [hole]).centroid == (440 / 76, 5.0). The
  // hole (area 24, centre (2.5, 5)) is subtracted from the square
  // (area 100, centre (5, 5)), whatever the ring orientation.
  let assert Ok(c) =
    centroid.compute(geometry: geometry.Polygon([outer_square(), west_hole()]))
  close_to(c, 440.0 /. 76.0, 5.0)
  let assert Ok(c) =
    centroid.compute(
      geometry: geometry.Polygon([outer_square(), list.reverse(west_hole())]),
    )
  close_to(c, 440.0 /. 76.0, 5.0)
}

pub fn centroid_of_multipolygon_is_area_weighted_test() -> Nil {
  // Shapely: MultiPolygon([square, small]).centroid == (584 / 104,
  // 504 / 104). A plain mean of the two centres would give (13, 3).
  let assert Ok(c) =
    centroid.compute(
      geometry: geometry.MultiPolygon([[outer_square()], [small_square()]]),
    )
  close_to(c, 584.0 /. 104.0, 504.0 /. 104.0)
}

pub fn centroid_of_multipolygon_with_hole_test() -> Nil {
  // Square minus hole (area 76) plus the small square (area 4, wound
  // clockwise): (524 / 80, 384 / 80).
  let assert Ok(c) =
    centroid.compute(
      geometry: geometry.MultiPolygon([
        [outer_square(), west_hole()],
        [list.reverse(small_square())],
      ]),
    )
  close_to(c, 524.0 /. 80.0, 384.0 /. 80.0)
}

pub fn centroid_of_zero_area_multipolygon_falls_back_to_vertex_mean_test() -> Nil {
  // Two degenerate polygons: each falls back to the mean of its
  // exterior vertices, and the result is the mean of those.
  let line_a = ring([#(0.0, 0.0), #(2.0, 0.0), #(0.0, 0.0)])
  let line_b = ring([#(10.0, 10.0), #(10.0, 12.0), #(10.0, 10.0)])
  let assert Ok(c) =
    centroid.compute(geometry: geometry.MultiPolygon([[line_a], [line_b]]))
  close_to(c, { 2.0 /. 3.0 +. 10.0 } /. 2.0, { 0.0 +. 32.0 /. 3.0 } /. 2.0)
}
