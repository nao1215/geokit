import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam_community/maths
import gleeunit
import gleeunit/should

import geokit.{type LatLng, Inside, OnBoundary, Outside}
import geokit/geojson

pub fn main() -> Nil {
  gleeunit.main()
}

// === latlng ================================================================

// --- Constructors --------------------------------------------------------

pub fn new_within_range_test() -> Nil {
  let assert Ok(tokyo) = geokit.lat_lng(latitude: 35.6812, longitude: 139.7671)
  geokit.latitude(tokyo)
  |> should.equal(35.6812)
  geokit.longitude(tokyo)
  |> should.equal(139.7671)
}

pub fn new_at_bounds_test() -> Nil {
  let assert Ok(north_pole) = geokit.lat_lng(latitude: 90.0, longitude: 0.0)
  geokit.latitude(north_pole)
  |> should.equal(90.0)
  let assert Ok(south_pole) = geokit.lat_lng(latitude: -90.0, longitude: 0.0)
  geokit.latitude(south_pole)
  |> should.equal(-90.0)
  let assert Ok(east) = geokit.lat_lng(latitude: 0.0, longitude: 180.0)
  geokit.longitude(east)
  |> should.equal(180.0)
  let assert Ok(west) = geokit.lat_lng(latitude: 0.0, longitude: -180.0)
  geokit.longitude(west)
  |> should.equal(-180.0)
}

// Issue #19: new_or_panic is the literal-friendly companion to new
// for curated coordinate lists where wrapping every value in
// `let assert Ok(...)` adds noise without adding safety.
pub fn new_or_panic_builds_valid_latlng_test() -> Nil {
  let tokyo = geokit.wrap_lat_lng(latitude: 35.6812, longitude: 139.7671)
  geokit.latitude(tokyo)
  |> should.equal(35.6812)
  geokit.longitude(tokyo)
  |> should.equal(139.7671)
}

pub fn new_or_panic_accepts_pole_and_antimeridian_test() -> Nil {
  let north = geokit.wrap_lat_lng(latitude: 90.0, longitude: 0.0)
  geokit.latitude(north)
  |> should.equal(90.0)
  let dateline_east = geokit.wrap_lat_lng(latitude: 0.0, longitude: 180.0)
  geokit.longitude(dateline_east)
  |> should.equal(180.0)
  let dateline_west = geokit.wrap_lat_lng(latitude: 0.0, longitude: -180.0)
  geokit.longitude(dateline_west)
  |> should.equal(-180.0)
}

pub fn new_lat_out_of_range_test() -> Nil {
  case geokit.lat_lng(latitude: 90.5, longitude: 0.0) {
    Error(geokit.LatitudeOutOfRange(latitude: 90.5)) -> Nil
    _ -> should.be_true(False)
  }
  case geokit.lat_lng(latitude: -90.5, longitude: 0.0) {
    Error(geokit.LatitudeOutOfRange(latitude: -90.5)) -> Nil
    _ -> should.be_true(False)
  }
}

pub fn new_lng_out_of_range_test() -> Nil {
  case geokit.lat_lng(latitude: 0.0, longitude: 180.5) {
    Error(geokit.LongitudeOutOfRange(longitude: 180.5)) -> Nil
    _ -> should.be_true(False)
  }
  case geokit.lat_lng(latitude: 0.0, longitude: -180.5) {
    Error(geokit.LongitudeOutOfRange(longitude: -180.5)) -> Nil
    _ -> should.be_true(False)
  }
}

// --- Wrap ----------------------------------------------------------------

pub fn wrap_at_antimeridian_test() -> Nil {
  let point = geokit.wrap_lat_lng(latitude: 0.0, longitude: 181.0)
  geokit.longitude(point)
  |> should.equal(-179.0)
}

pub fn wrap_negative_overflow_test() -> Nil {
  let point = geokit.wrap_lat_lng(latitude: 0.0, longitude: -181.0)
  geokit.longitude(point)
  |> should.equal(179.0)
}

pub fn wrap_lat_clamped_test() -> Nil {
  let point = geokit.wrap_lat_lng(latitude: 95.0, longitude: 0.0)
  geokit.latitude(point)
  |> should.equal(90.0)
  let southern = geokit.wrap_lat_lng(latitude: -95.0, longitude: 0.0)
  geokit.latitude(southern)
  |> should.equal(-90.0)
}

// --- Equality ------------------------------------------------------------

pub fn equal_test() -> Nil {
  let assert Ok(a) = geokit.lat_lng(latitude: 35.6812, longitude: 139.7671)
  let assert Ok(b) = geokit.lat_lng(latitude: 35.6812, longitude: 139.7671)
  let assert Ok(c) = geokit.lat_lng(latitude: 35.6813, longitude: 139.7671)
  a |> should.equal(b)
  a |> should.not_equal(c)
}

// --- equal ---------------------------------------------------------------

pub fn equal_treats_signed_zeros_as_equal_test() -> Nil {
  // -0.0 and 0.0 are the same coordinate. Erlang's exact `==` on floats
  // tells them apart; JavaScript does not.
  geokit.wrap_lat_lng(latitude: 0.0, longitude: -0.0)
  |> should.equal(geokit.wrap_lat_lng(latitude: -0.0, longitude: 0.0))
}

pub fn equal_distinguishes_different_values_test() -> Nil {
  geokit.wrap_lat_lng(latitude: 0.0, longitude: 180.0)
  |> should.not_equal(geokit.wrap_lat_lng(latitude: 0.0, longitude: -180.0))
  geokit.wrap_lat_lng(latitude: 1.0, longitude: 2.0)
  |> should.equal(geokit.wrap_lat_lng(latitude: 1.0, longitude: 2.0))
}

// --- non-finite input (JavaScript only) ---------------------------------
// Erlang floats cannot hold Infinity or NaN: the arithmetic that would
// produce them raises instead.

@target(javascript)
fn infinity() -> Float {
  1.0e308 *. 10.0
}

@target(javascript)
pub fn new_rejects_nan_test() -> Nil {
  let nan = infinity() -. infinity()
  let assert Error(_) = geokit.lat_lng(latitude: nan, longitude: 0.0)
  let assert Error(_) = geokit.lat_lng(latitude: 0.0, longitude: nan)
  let assert Error(_) = geokit.lat_lng(latitude: infinity(), longitude: 0.0)
  Nil
}

@target(javascript)
pub fn wrap_non_finite_test() -> Nil {
  let nan = infinity() -. infinity()
  let p = geokit.wrap_lat_lng(latitude: infinity(), longitude: infinity())
  #(geokit.latitude(p), geokit.longitude(p))
  |> should.equal(#(90.0, 0.0))
  let p = geokit.wrap_lat_lng(latitude: 0.0 -. infinity(), longitude: nan)
  #(geokit.latitude(p), geokit.longitude(p))
  |> should.equal(#(-90.0, 0.0))
  let p = geokit.wrap_lat_lng(latitude: nan, longitude: 10.0)
  #(geokit.latitude(p), geokit.longitude(p))
  |> should.equal(#(0.0, 10.0))
}

// === distance ==============================================================

// Approximate comparison: returns True if |a - b| <= tolerance.
fn approx_equal(a: Float, b: Float, tolerance: Float) -> Bool {
  let delta = case a >. b {
    True -> a -. b
    False -> b -. a
  }
  delta <=. tolerance
}

// --- haversine -----------------------------------------------------------

pub fn distance_zero_for_same_point_test() -> Nil {
  let assert Ok(tokyo) = geokit.lat_lng(latitude: 35.6812, longitude: 139.7671)
  geokit.distance(from: tokyo, to: tokyo)
  |> approx_equal(0.0, 0.001)
  |> should.be_true
}

pub fn tokyo_to_osaka_test() -> Nil {
  // Tokyo (35.6812, 139.7671) to Osaka (34.6937, 135.5023).
  // Reference: Python `math` haversine with WGS84 mean radius
  // ≈ 402_785 m.
  let assert Ok(tokyo) = geokit.lat_lng(latitude: 35.6812, longitude: 139.7671)
  let assert Ok(osaka) = geokit.lat_lng(latitude: 34.6937, longitude: 135.5023)
  let d = geokit.distance(from: tokyo, to: osaka)
  approx_equal(d, 402_785.0, 100.0)
  |> should.be_true
}

pub fn london_to_paris_test() -> Nil {
  // London (51.5074, -0.1278) to Paris (48.8566, 2.3522). Reference
  // haversine on WGS84 mean radius ≈ 343_500 m.
  let assert Ok(london) = geokit.lat_lng(latitude: 51.5074, longitude: -0.1278)
  let assert Ok(paris) = geokit.lat_lng(latitude: 48.8566, longitude: 2.3522)
  let d = geokit.distance(from: london, to: paris)
  approx_equal(d, 343_500.0, 4000.0)
  |> should.be_true
}

pub fn ny_to_la_test() -> Nil {
  // NYC (40.7128, -74.0060) to LA (34.0522, -118.2437). Reference ≈
  // 3_935_500 m.
  let assert Ok(nyc) = geokit.lat_lng(latitude: 40.7128, longitude: -74.006)
  let assert Ok(la) = geokit.lat_lng(latitude: 34.0522, longitude: -118.2437)
  let d = geokit.distance(from: nyc, to: la)
  approx_equal(d, 3_935_500.0, 20_000.0)
  |> should.be_true
}

pub fn antipodes_test() -> Nil {
  // Two diametrically opposite points should be ≈ half the Earth's
  // circumference: π × 6_371_008.8 m ≈ 20_015_115 m.
  let assert Ok(a) = geokit.lat_lng(latitude: 0.0, longitude: 0.0)
  let assert Ok(b) = geokit.lat_lng(latitude: 0.0, longitude: 180.0)
  let d = geokit.distance(from: a, to: b)
  approx_equal(d, 20_015_115.0, 1000.0)
  |> should.be_true
}

pub fn equator_quarter_test() -> Nil {
  // 0°E to 90°E along the equator: π/2 × 6_371_008.8 m ≈ 10_007_557 m.
  let assert Ok(a) = geokit.lat_lng(latitude: 0.0, longitude: 0.0)
  let assert Ok(b) = geokit.lat_lng(latitude: 0.0, longitude: 90.0)
  let d = geokit.distance(from: a, to: b)
  approx_equal(d, 10_007_557.0, 1000.0)
  |> should.be_true
}

pub fn haversine_km_matches_metres_test() -> Nil {
  let assert Ok(a) = geokit.lat_lng(latitude: 35.0, longitude: 139.0)
  let assert Ok(b) = geokit.lat_lng(latitude: 36.0, longitude: 140.0)
  let metres = geokit.distance(from: a, to: b)
  let km = {
    geokit.distance(from: a, to: b) /. 1000.0
  }
  approx_equal(metres /. 1000.0, km, 0.000_001)
  |> should.be_true
}

pub fn symmetric_test() -> Nil {
  let assert Ok(a) = geokit.lat_lng(latitude: 12.34, longitude: 56.78)
  let assert Ok(b) = geokit.lat_lng(latitude: -23.45, longitude: 67.89)
  let d_ab = geokit.distance(from: a, to: b)
  let d_ba = geokit.distance(from: b, to: a)
  approx_equal(d_ab, d_ba, 0.001)
  |> should.be_true
}

// --- tiny distances -------------------------------------------------------

pub fn haversine_tiny_distance_test() -> Nil {
  // 1e-9 degrees of latitude: R * 1e-9 * pi / 180 ~= 1.1119e-4 m.
  let a = geokit.wrap_lat_lng(latitude: 0.0, longitude: 0.0)
  let b = geokit.wrap_lat_lng(latitude: 1.0e-9, longitude: 0.0)
  let expected = 6_371_008.8 *. 1.0e-9 *. 3.141592653589793 /. 180.0
  approx_equal(geokit.distance(from: a, to: b), expected, expected *. 1.0e-9)
  |> should.be_true
}

// === bearing ===============================================================

// Wraps the difference into [0, 360) and tests whether the bearing
// is within `tolerance` of `target` modulo 360°.
fn bearing_approx(value: Float, target: Float, tolerance: Float) -> Bool {
  let raw_diff = value -. target
  let mod_diff = case raw_diff <. -180.0 {
    True -> raw_diff +. 360.0
    False ->
      case raw_diff >. 180.0 {
        True -> raw_diff -. 360.0
        False -> raw_diff
      }
  }
  let abs_diff = case mod_diff <. 0.0 {
    True -> 0.0 -. mod_diff
    False -> mod_diff
  }
  abs_diff <=. tolerance
}

// --- initial bearing ----------------------------------------------------

pub fn initial_due_north_test() -> Nil {
  let assert Ok(equator) = geokit.lat_lng(latitude: 0.0, longitude: 0.0)
  let assert Ok(north) = geokit.lat_lng(latitude: 1.0, longitude: 0.0)
  geokit.initial_bearing(from: equator, to: north)
  |> approx_equal(0.0, 0.001)
  |> should.be_true
}

pub fn initial_due_east_test() -> Nil {
  let assert Ok(equator) = geokit.lat_lng(latitude: 0.0, longitude: 0.0)
  let assert Ok(east) = geokit.lat_lng(latitude: 0.0, longitude: 1.0)
  geokit.initial_bearing(from: equator, to: east)
  |> approx_equal(90.0, 0.001)
  |> should.be_true
}

pub fn initial_due_south_test() -> Nil {
  let assert Ok(equator) = geokit.lat_lng(latitude: 0.0, longitude: 0.0)
  let assert Ok(south) = geokit.lat_lng(latitude: -1.0, longitude: 0.0)
  geokit.initial_bearing(from: equator, to: south)
  |> approx_equal(180.0, 0.001)
  |> should.be_true
}

pub fn initial_due_west_test() -> Nil {
  let assert Ok(equator) = geokit.lat_lng(latitude: 0.0, longitude: 0.0)
  let assert Ok(west) = geokit.lat_lng(latitude: 0.0, longitude: -1.0)
  geokit.initial_bearing(from: equator, to: west)
  |> approx_equal(270.0, 0.001)
  |> should.be_true
}

pub fn london_to_paris_initial_test() -> Nil {
  // Reference (chrisveness/geodesy): ~149°.
  let assert Ok(london) = geokit.lat_lng(latitude: 51.5074, longitude: -0.1278)
  let assert Ok(paris) = geokit.lat_lng(latitude: 48.8566, longitude: 2.3522)
  let b = geokit.initial_bearing(from: london, to: paris)
  bearing_approx(b, 149.0, 1.0)
  |> should.be_true
}

pub fn initial_is_in_range_test() -> Nil {
  let assert Ok(a) = geokit.lat_lng(latitude: 12.34, longitude: 56.78)
  let assert Ok(b) = geokit.lat_lng(latitude: -23.45, longitude: 67.89)
  let value = geokit.initial_bearing(from: a, to: b)
  { value >=. 0.0 && value <. 360.0 }
  |> should.be_true
}

// --- final bearing ------------------------------------------------------

pub fn final_along_meridian_equals_initial_test() -> Nil {
  // Travelling along a meridian, initial and final bearings agree.
  let assert Ok(a) = geokit.lat_lng(latitude: 10.0, longitude: 0.0)
  let assert Ok(b) = geokit.lat_lng(latitude: 30.0, longitude: 0.0)
  let init = geokit.initial_bearing(from: a, to: b)
  let fin = geokit.final_bearing(from: a, to: b)
  bearing_approx(init, fin, 0.001)
  |> should.be_true
}

pub fn final_long_route_differs_from_initial_test() -> Nil {
  // Long east-west route across the northern hemisphere has a final
  // bearing distinct from the initial one.
  let assert Ok(london) = geokit.lat_lng(latitude: 51.5074, longitude: -0.1278)
  let assert Ok(tokyo) = geokit.lat_lng(latitude: 35.6812, longitude: 139.7671)
  let init = geokit.initial_bearing(from: london, to: tokyo)
  let fin = geokit.final_bearing(from: london, to: tokyo)
  // The two should differ by more than 1°.
  let raw = fin -. init
  let abs_diff = case raw <. 0.0 {
    True -> 0.0 -. raw
    False -> raw
  }
  { abs_diff >. 1.0 }
  |> should.be_true
}

// === bbox ==================================================================

// --- point ---------------------------------------------------------------

pub fn bbox_of_point_test() -> Nil {
  let assert Ok(p) = geokit.lat_lng(latitude: 35.6812, longitude: 139.7671)
  let assert Ok(#(sw, ne)) = bbox(geokit.Point(p))
  geokit.latitude(sw)
  |> should.equal(35.6812)
  geokit.latitude(ne)
  |> should.equal(35.6812)
  geokit.longitude(sw)
  |> should.equal(139.7671)
  geokit.longitude(ne)
  |> should.equal(139.7671)
}

// --- line string ---------------------------------------------------------

pub fn bbox_of_line_string_test() -> Nil {
  let assert Ok(a) = geokit.lat_lng(latitude: 35.0, longitude: 139.0)
  let assert Ok(b) = geokit.lat_lng(latitude: 36.0, longitude: 140.0)
  let assert Ok(c) = geokit.lat_lng(latitude: 34.5, longitude: 139.5)
  let assert Ok(#(sw, ne)) = bbox(geokit.LineString([a, b, c]))
  geokit.latitude(sw)
  |> should.equal(34.5)
  geokit.latitude(ne)
  |> should.equal(36.0)
  geokit.longitude(sw)
  |> should.equal(139.0)
  geokit.longitude(ne)
  |> should.equal(140.0)
}

// --- polygon -------------------------------------------------------------

pub fn bbox_of_polygon_test() -> Nil {
  let assert Ok(a) = geokit.lat_lng(latitude: 0.0, longitude: 0.0)
  let assert Ok(b) = geokit.lat_lng(latitude: 0.0, longitude: 10.0)
  let assert Ok(c) = geokit.lat_lng(latitude: 10.0, longitude: 10.0)
  let assert Ok(d) = geokit.lat_lng(latitude: 10.0, longitude: 0.0)
  let assert Ok(#(sw, ne)) = bbox(geokit.Polygon([[a, b, c, d, a]]))
  geokit.latitude(sw)
  |> should.equal(0.0)
  geokit.latitude(ne)
  |> should.equal(10.0)
  geokit.longitude(sw)
  |> should.equal(0.0)
  geokit.longitude(ne)
  |> should.equal(10.0)
}

// --- empty ---------------------------------------------------------------

pub fn bbox_empty_line_string_test() -> Nil {
  case bbox(geokit.LineString([])) {
    Error(Nil) -> Nil
    _ -> should.be_true(False)
  }
}

pub fn bbox_empty_polygon_test() -> Nil {
  case bbox(geokit.Polygon([])) {
    Error(Nil) -> Nil
    _ -> should.be_true(False)
  }
}

// --- multi point ---------------------------------------------------------

pub fn bbox_of_points_matches_line_string_test() -> Nil {
  let assert Ok(a) = geokit.lat_lng(latitude: 35.0, longitude: 139.0)
  let assert Ok(b) = geokit.lat_lng(latitude: 36.0, longitude: 140.0)
  let assert Ok(c) = geokit.lat_lng(latitude: 34.5, longitude: 139.5)
  let assert Ok(#(sw, ne)) = bbox(geokit.MultiPoint([a, b, c]))
  geokit.latitude(sw)
  |> should.equal(34.5)
  geokit.latitude(ne)
  |> should.equal(36.0)
  geokit.longitude(sw)
  |> should.equal(139.0)
  geokit.longitude(ne)
  |> should.equal(140.0)
  // Same answer the LineString-based call gives.
  let assert Ok(#(sw_via_geom, ne_via_geom)) =
    bbox(geokit.LineString([a, b, c]))
  sw |> should.equal(sw_via_geom)
  ne |> should.equal(ne_via_geom)
}

pub fn bbox_of_points_single_test() -> Nil {
  let assert Ok(p) = geokit.lat_lng(latitude: 35.6812, longitude: 139.7671)
  let assert Ok(#(sw, ne)) = bbox(geokit.MultiPoint([p]))
  sw |> should.equal(p)
  ne |> should.equal(p)
}

pub fn bbox_of_points_empty_test() -> Nil {
  case bbox(geokit.MultiPoint([])) {
    Error(Nil) -> Nil
    _ -> should.be_true(False)
  }
}

pub fn bbox_compute_multi_point_test() -> Nil {
  let assert Ok(a) = geokit.lat_lng(latitude: 35.0, longitude: 139.0)
  let assert Ok(b) = geokit.lat_lng(latitude: 36.0, longitude: 140.0)
  // The bbox of a MultiPoint matches the LineString of the same points.
  let assert Ok(#(sw, ne)) = bbox(geokit.MultiPoint([a, b]))
  let assert Ok(#(sw_via_line, ne_via_line)) = bbox(geokit.LineString([a, b]))
  sw |> should.equal(sw_via_line)
  ne |> should.equal(ne_via_line)
}

pub fn bbox_compute_multi_point_empty_test() -> Nil {
  case bbox(geokit.MultiPoint([])) {
    Error(Nil) -> Nil
    _ -> should.be_true(False)
  }
}

// --- long inputs (20_000 points) ----------------------------------------

// 20_000 points walking the perimeter of the square [0, 10] x [0, 10]
// counter-clockwise from (0, 0). The ring is not closed.
fn square_perimeter() -> List(geokit.LatLng) {
  list.repeat(Nil, times: 20_000)
  |> list.index_map(fn(_, i) {
    let side = i / 5000
    let t = int.to_float(i % 5000) /. 500.0
    case side {
      0 -> geokit.wrap_lat_lng(latitude: 0.0, longitude: t)
      1 -> geokit.wrap_lat_lng(latitude: t, longitude: 10.0)
      2 -> geokit.wrap_lat_lng(latitude: 10.0, longitude: 10.0 -. t)
      _ -> geokit.wrap_lat_lng(latitude: 10.0 -. t, longitude: 0.0)
    }
  })
}

pub fn bbox_of_long_polygon_test() -> Nil {
  let ring = square_perimeter()
  let assert Ok(#(sw, ne)) = bbox(geokit.MultiPolygon([[ring], [ring, ring]]))
  #(
    geokit.latitude(sw),
    geokit.longitude(sw),
    geokit.latitude(ne),
    geokit.longitude(ne),
  )
  |> should.equal(#(0.0, 0.0, 10.0, 10.0))
}

// === centroid ==============================================================

// --- point ---------------------------------------------------------------

pub fn centroid_of_point_test() -> Nil {
  let assert Ok(p) = geokit.lat_lng(latitude: 35.6812, longitude: 139.7671)
  let assert Ok(c) = geokit.centroid(geokit.Point(p))
  c |> should.equal(p)
}

// --- line string ---------------------------------------------------------

pub fn centroid_of_line_string_test() -> Nil {
  // Mean of (0,0), (0,2), (2,0), (2,2) is (1,1).
  let assert Ok(a) = geokit.lat_lng(latitude: 0.0, longitude: 0.0)
  let assert Ok(b) = geokit.lat_lng(latitude: 0.0, longitude: 2.0)
  let assert Ok(c) = geokit.lat_lng(latitude: 2.0, longitude: 0.0)
  let assert Ok(d) = geokit.lat_lng(latitude: 2.0, longitude: 2.0)
  let assert Ok(centre) = geokit.centroid(geokit.LineString([a, b, c, d]))
  geokit.latitude(centre)
  |> should.equal(1.0)
  geokit.longitude(centre)
  |> should.equal(1.0)
}

// --- polygon (unit square) ----------------------------------------------

pub fn centroid_of_unit_square_test() -> Nil {
  // Unit square centroid is at (0.5, 0.5).
  let assert Ok(a) = geokit.lat_lng(latitude: 0.0, longitude: 0.0)
  let assert Ok(b) = geokit.lat_lng(latitude: 0.0, longitude: 1.0)
  let assert Ok(c) = geokit.lat_lng(latitude: 1.0, longitude: 1.0)
  let assert Ok(d) = geokit.lat_lng(latitude: 1.0, longitude: 0.0)
  let assert Ok(centre) = geokit.centroid(geokit.Polygon([[a, b, c, d, a]]))
  approx_equal(geokit.latitude(centre), 0.5, 0.0001)
  |> should.be_true
  approx_equal(geokit.longitude(centre), 0.5, 0.0001)
  |> should.be_true
}

pub fn centroid_of_offset_square_test() -> Nil {
  // Square from (10, 20) to (12, 22) has centroid (11, 21).
  let assert Ok(a) = geokit.lat_lng(latitude: 10.0, longitude: 20.0)
  let assert Ok(b) = geokit.lat_lng(latitude: 10.0, longitude: 22.0)
  let assert Ok(c) = geokit.lat_lng(latitude: 12.0, longitude: 22.0)
  let assert Ok(d) = geokit.lat_lng(latitude: 12.0, longitude: 20.0)
  let assert Ok(centre) = geokit.centroid(geokit.Polygon([[a, b, c, d, a]]))
  approx_equal(geokit.latitude(centre), 11.0, 0.0001)
  |> should.be_true
  approx_equal(geokit.longitude(centre), 21.0, 0.0001)
  |> should.be_true
}

// --- empty ---------------------------------------------------------------

pub fn centroid_empty_line_test() -> Nil {
  case geokit.centroid(geokit.LineString([])) {
    Error(Nil) -> Nil
    _ -> should.be_true(False)
  }
}

// --- multi point ---------------------------------------------------------

pub fn centroid_of_points_matches_line_string_test() -> Nil {
  let assert Ok(a) = geokit.lat_lng(latitude: 0.0, longitude: 0.0)
  let assert Ok(b) = geokit.lat_lng(latitude: 0.0, longitude: 2.0)
  let assert Ok(c) = geokit.lat_lng(latitude: 2.0, longitude: 0.0)
  let assert Ok(d) = geokit.lat_lng(latitude: 2.0, longitude: 2.0)
  let assert Ok(via_helper) = geokit.centroid(geokit.MultiPoint([a, b, c, d]))
  let assert Ok(via_geom) = geokit.centroid(geokit.LineString([a, b, c, d]))
  via_helper |> should.equal(via_geom)
  geokit.latitude(via_helper)
  |> should.equal(1.0)
  geokit.longitude(via_helper)
  |> should.equal(1.0)
}

pub fn centroid_of_points_single_test() -> Nil {
  let assert Ok(p) = geokit.lat_lng(latitude: 35.6812, longitude: 139.7671)
  let assert Ok(c) = geokit.centroid(geokit.MultiPoint([p]))
  c |> should.equal(p)
}

pub fn centroid_of_points_empty_test() -> Nil {
  case geokit.centroid(geokit.MultiPoint([])) {
    Error(Nil) -> Nil
    _ -> should.be_true(False)
  }
}

pub fn centroid_compute_multi_point_test() -> Nil {
  let assert Ok(a) = geokit.lat_lng(latitude: 0.0, longitude: 0.0)
  let assert Ok(b) = geokit.lat_lng(latitude: 10.0, longitude: 10.0)
  let assert Ok(via_multi) = geokit.centroid(geokit.MultiPoint([a, b]))
  let assert Ok(via_line) = geokit.centroid(geokit.LineString([a, b]))
  via_multi |> should.equal(via_line)
}

pub fn centroid_compute_multi_point_empty_test() -> Nil {
  case geokit.centroid(geokit.MultiPoint([])) {
    Error(Nil) -> Nil
    _ -> should.be_true(False)
  }
}

pub fn closed_ring_centroid_does_not_count_the_closing_vertex_twice_test() -> Nil {
  // A MultiPoint is a bag of points, so a repeated closing vertex is
  // counted twice and the mean of this closed unit square is (0.4, 0.4).
  // As a Polygon the same ring gives the true centroid (0.5, 0.5).
  let assert Ok(a) = geokit.lat_lng(latitude: 0.0, longitude: 0.0)
  let assert Ok(b) = geokit.lat_lng(latitude: 0.0, longitude: 1.0)
  let assert Ok(c) = geokit.lat_lng(latitude: 1.0, longitude: 1.0)
  let assert Ok(d) = geokit.lat_lng(latitude: 1.0, longitude: 0.0)
  let assert Ok(e) = geokit.lat_lng(latitude: 0.0, longitude: 0.0)
  let assert Ok(mean) = geokit.centroid(geokit.MultiPoint([a, b, c, d, e]))
  geokit.latitude(mean) |> should.equal(0.4)
  geokit.longitude(mean) |> should.equal(0.4)
  let assert Ok(centre) = geokit.centroid(geokit.Polygon([[a, b, c, d, e]]))
  geokit.latitude(centre) |> should.equal(0.5)
  geokit.longitude(centre) |> should.equal(0.5)
}

pub fn of_points_unclosed_ring_uses_arithmetic_mean_test() -> Nil {
  let assert Ok(a) = geokit.lat_lng(latitude: 0.0, longitude: 0.0)
  let assert Ok(b) = geokit.lat_lng(latitude: 0.0, longitude: 1.0)
  let assert Ok(c) = geokit.lat_lng(latitude: 1.0, longitude: 1.0)
  let assert Ok(d) = geokit.lat_lng(latitude: 1.0, longitude: 0.0)
  let assert Ok(centre) = geokit.centroid(geokit.MultiPoint([a, b, c, d]))
  geokit.latitude(centre) |> should.equal(0.5)
  geokit.longitude(centre) |> should.equal(0.5)
}

pub fn multi_point_duplicates_are_kept_test() -> Nil {
  // A repeated point carries weight in the mean.
  let assert Ok(a) = geokit.lat_lng(latitude: 0.0, longitude: 0.0)
  let assert Ok(b) = geokit.lat_lng(latitude: 1.0, longitude: 1.0)
  let assert Ok(centre) = geokit.centroid(geokit.MultiPoint([a, a, b]))
  geokit.longitude(centre) |> should.equal({ 0.0 +. 0.0 +. 1.0 } /. 3.0)
}

pub fn of_points_single_point_test() -> Nil {
  let assert Ok(only) = geokit.lat_lng(latitude: 5.0, longitude: 10.0)
  let assert Ok(centre) = geokit.centroid(geokit.MultiPoint([only]))
  geokit.latitude(centre) |> should.equal(5.0)
  geokit.longitude(centre) |> should.equal(10.0)
}

pub fn of_points_empty_errors_test() -> Nil {
  case geokit.centroid(geokit.MultiPoint([])) {
    Error(Nil) -> Nil
    _ -> should.be_true(False)
  }
}

// --- long inputs (20_000 points) ----------------------------------------

// 20_000 points walking the perimeter of the square [0, 10] x [0, 10]
// counter-clockwise from (0, 0). The ring is not closed.

pub fn centroid_of_long_polygon_test() -> Nil {
  let assert Ok(c) = geokit.centroid(geokit.Polygon([square_perimeter()]))
  approx_equal(geokit.latitude(c), 5.0, 1.0e-9)
  |> should.be_true
  approx_equal(geokit.longitude(c), 5.0, 1.0e-9)
  |> should.be_true
}

pub fn centroid_of_long_closed_ring_test() -> Nil {
  let ring = square_perimeter()
  let closed = list.append(ring, list.take(ring, 1))
  let assert Ok(c) = geokit.centroid(geokit.Polygon([closed]))
  approx_equal(geokit.latitude(c), 5.0, 1.0e-9)
  |> should.be_true
  approx_equal(geokit.longitude(c), 5.0, 1.0e-9)
  |> should.be_true
}

pub fn closed_ring_with_signed_zero_test() -> Nil {
  // First (0.0, 0.0) and last (-0.0, -0.0) are the same vertex, so the
  // ring is closed and its centroid is the square's centre.
  geokit.wrap_lat_lng(latitude: -0.0, longitude: -0.0)
  |> should.equal(geokit.wrap_lat_lng(latitude: 0.0, longitude: 0.0))
  let assert Ok(c) =
    geokit.centroid(
      geokit.Polygon([
        [
          geokit.wrap_lat_lng(latitude: 0.0, longitude: 0.0),
          geokit.wrap_lat_lng(latitude: 0.0, longitude: 1.0),
          geokit.wrap_lat_lng(latitude: 1.0, longitude: 1.0),
          geokit.wrap_lat_lng(latitude: 1.0, longitude: 0.0),
          geokit.wrap_lat_lng(latitude: -0.0, longitude: -0.0),
        ],
      ]),
    )
  #(geokit.latitude(c), geokit.longitude(c))
  |> should.equal(#(0.5, 0.5))
}

pub fn polygon_centroid_with_signed_zero_closure_test() -> Nil {
  // A closed triangle whose closing vertex is written with -0.0 must
  // not be closed a second time.
  let assert Ok(c) =
    geokit.centroid(
      geokit.Polygon([
        [
          geokit.wrap_lat_lng(latitude: 0.0, longitude: 0.0),
          geokit.wrap_lat_lng(latitude: 0.0, longitude: 3.0),
          geokit.wrap_lat_lng(latitude: 3.0, longitude: 0.0),
          geokit.wrap_lat_lng(latitude: -0.0, longitude: -0.0),
        ],
      ]),
    )
  approx_equal(geokit.latitude(c), 1.0, 1.0e-12)
  |> should.be_true
  approx_equal(geokit.longitude(c), 1.0, 1.0e-12)
  |> should.be_true
}

// --- holes and multipolygons (area-weighted) -----------------------------

fn ring(coords: List(#(Float, Float))) -> List(geokit.LatLng) {
  list.map(coords, fn(c) { geokit.wrap_lat_lng(latitude: c.1, longitude: c.0) })
}

// Coordinates are (lng, lat), as in Shapely.
fn outer_square() -> List(geokit.LatLng) {
  ring([#(0.0, 0.0), #(10.0, 0.0), #(10.0, 10.0), #(0.0, 10.0), #(0.0, 0.0)])
}

fn west_hole() -> List(geokit.LatLng) {
  ring([#(1.0, 1.0), #(1.0, 9.0), #(4.0, 9.0), #(4.0, 1.0), #(1.0, 1.0)])
}

fn small_square() -> List(geokit.LatLng) {
  ring([#(20.0, 0.0), #(22.0, 0.0), #(22.0, 2.0), #(20.0, 2.0), #(20.0, 0.0)])
}

fn close_to(c: geokit.LatLng, lng: Float, lat: Float) -> Nil {
  approx_equal(geokit.longitude(c), lng, 1.0e-12)
  |> should.be_true
  approx_equal(geokit.latitude(c), lat, 1.0e-12)
  |> should.be_true
}

pub fn centroid_of_polygon_with_hole_test() -> Nil {
  // Shapely: Polygon(square, [hole]).centroid == (440 / 76, 5.0). The
  // hole (area 24, centre (2.5, 5)) is subtracted from the square
  // (area 100, centre (5, 5)), whatever the ring orientation.
  let assert Ok(c) =
    geokit.centroid(geokit.Polygon([outer_square(), west_hole()]))
  close_to(c, 440.0 /. 76.0, 5.0)
  let assert Ok(c) =
    geokit.centroid(geokit.Polygon([outer_square(), list.reverse(west_hole())]))
  close_to(c, 440.0 /. 76.0, 5.0)
}

pub fn centroid_of_multipolygon_is_area_weighted_test() -> Nil {
  // Shapely: MultiPolygon([square, small]).centroid == (584 / 104,
  // 504 / 104). A plain mean of the two centres would give (13, 3).
  let assert Ok(c) =
    geokit.centroid(geokit.MultiPolygon([[outer_square()], [small_square()]]))
  close_to(c, 584.0 /. 104.0, 504.0 /. 104.0)
}

pub fn centroid_of_multipolygon_with_hole_test() -> Nil {
  // Square minus hole (area 76) plus the small square (area 4, wound
  // clockwise): (524 / 80, 384 / 80).
  let assert Ok(c) =
    geokit.centroid(
      geokit.MultiPolygon([
        [outer_square(), west_hole()],
        [list.reverse(small_square())],
      ]),
    )
  close_to(c, 524.0 /. 80.0, 384.0 /. 80.0)
}

pub fn centroid_of_zero_area_multipolygon_falls_back_to_vertex_mean_test() -> Nil {
  // Two degenerate polygons: each falls back to the mean of its
  // exterior vertices without the closing duplicate, and the result is
  // the mean of those.
  let line_a = ring([#(0.0, 0.0), #(2.0, 0.0), #(0.0, 0.0)])
  let line_b = ring([#(10.0, 10.0), #(10.0, 12.0), #(10.0, 10.0)])
  let assert Ok(c) = geokit.centroid(geokit.MultiPolygon([[line_a], [line_b]]))
  close_to(c, { 1.0 +. 10.0 } /. 2.0, { 0.0 +. 11.0 } /. 2.0)
}

pub fn centroid_of_zero_area_polygon_ignores_closing_vertex_test() -> Nil {
  // A closed ring on a line has zero area; the fallback must average
  // the distinct vertices, as the vertex mean of the open ring does.
  let points = ring([#(0.0, 0.0), #(1.0, 0.0), #(2.0, 0.0)])
  let assert Ok(c) =
    geokit.centroid(
      geokit.Polygon([
        ring([#(0.0, 0.0), #(1.0, 0.0), #(2.0, 0.0), #(0.0, 0.0)]),
      ]),
    )
  close_to(c, 1.0, 0.0)
  geokit.centroid(geokit.MultiPoint(points))
  |> should.equal(Ok(c))
}

pub fn centroid_of_zero_area_unclosed_polygon_keeps_every_vertex_test() -> Nil {
  let assert Ok(c) =
    geokit.centroid(
      geokit.Polygon([ring([#(0.0, 0.0), #(1.0, 0.0), #(5.0, 0.0)])]),
    )
  close_to(c, 2.0, 0.0)
}

// === simplify ==============================================================

// --- basic ---------------------------------------------------------------

pub fn simplify_empty_test() -> Nil {
  let assert Ok(result) = simplify_line([], tolerance: 0.1)
  list.length(result)
  |> should.equal(0)
}

pub fn simplify_single_point_test() -> Nil {
  let assert Ok(p) = geokit.lat_lng(latitude: 0.0, longitude: 0.0)
  let assert Ok(result) = simplify_line([p], tolerance: 0.1)
  list.length(result)
  |> should.equal(1)
}

pub fn simplify_two_points_test() -> Nil {
  let assert Ok(a) = geokit.lat_lng(latitude: 0.0, longitude: 0.0)
  let assert Ok(b) = geokit.lat_lng(latitude: 1.0, longitude: 1.0)
  let assert Ok(result) = simplify_line([a, b], tolerance: 0.1)
  list.length(result)
  |> should.equal(2)
}

// --- collinear -----------------------------------------------------------

pub fn simplify_collinear_drops_middle_test() -> Nil {
  // a -- b -- c collinear: b should be dropped at any positive
  // tolerance.
  let assert Ok(a) = geokit.lat_lng(latitude: 0.0, longitude: 0.0)
  let assert Ok(b) = geokit.lat_lng(latitude: 0.0, longitude: 0.5)
  let assert Ok(c) = geokit.lat_lng(latitude: 0.0, longitude: 1.0)
  let assert Ok(result) = simplify_line([a, b, c], tolerance: 0.001)
  list.length(result)
  |> should.equal(2)
}

pub fn simplify_kept_when_perpendicular_test() -> Nil {
  // a (0,0) → b (1, 0.5) → c (0, 1). Point b has perpendicular
  // distance 0.5 from line a-c, so it survives any tolerance below
  // 0.5.
  let assert Ok(a) = geokit.lat_lng(latitude: 0.0, longitude: 0.0)
  let assert Ok(b) = geokit.lat_lng(latitude: 1.0, longitude: 0.5)
  let assert Ok(c) = geokit.lat_lng(latitude: 0.0, longitude: 1.0)
  let assert Ok(result) = simplify_line([a, b, c], tolerance: 0.1)
  list.length(result)
  |> should.equal(3)
}

pub fn simplify_dropped_at_large_tolerance_test() -> Nil {
  // Same shape, with tolerance > 0.5: middle point is dropped.
  let assert Ok(a) = geokit.lat_lng(latitude: 0.0, longitude: 0.0)
  let assert Ok(b) = geokit.lat_lng(latitude: 1.0, longitude: 0.5)
  let assert Ok(c) = geokit.lat_lng(latitude: 0.0, longitude: 1.0)
  let assert Ok(result) = simplify_line([a, b, c], tolerance: 1.0)
  list.length(result)
  |> should.equal(2)
}

pub fn simplify_diagonal_segment_away_from_origin_test() -> Nil {
  // Segment (lng 20, lat 10) - (lng 22, lat 12) with the middle point at
  // (lng 20.5, lat 12): its distance to the line is 1.5 / sqrt(2), about
  // 1.061 degrees. Both ends are away from the origin and the segment is
  // diagonal, so a formula that adds a coordinate instead of subtracting it
  // gives another distance.
  let assert Ok(a) = geokit.lat_lng(latitude: 10.0, longitude: 20.0)
  let assert Ok(b) = geokit.lat_lng(latitude: 12.0, longitude: 20.5)
  let assert Ok(c) = geokit.lat_lng(latitude: 12.0, longitude: 22.0)
  simplify_line([a, b, c], tolerance: 1.0)
  |> should.equal(Ok([a, b, c]))
  simplify_line([a, b, c], tolerance: 1.1)
  |> should.equal(Ok([a, c]))
}

pub fn compute_accepts_zero_tolerance_test() -> Nil {
  // Zero is the smallest valid tolerance; only negative values are errors.
  let assert Ok(a) = geokit.lat_lng(latitude: 0.0, longitude: 0.0)
  let assert Ok(b) = geokit.lat_lng(latitude: 1.0, longitude: 0.5)
  let assert Ok(c) = geokit.lat_lng(latitude: 0.0, longitude: 1.0)
  geokit.simplify(geokit.LineString([a, b, c]), tolerance: 0.0)
  |> should.equal(Ok(geokit.LineString([a, b, c])))
}

pub fn simplify_closed_line_away_from_origin_test() -> Nil {
  // The first and last points coincide, so the distance is measured to
  // that point: (lng 20.3, lat 10.4) is 0.5 degrees from (lng 20, lat 10).
  let assert Ok(a) = geokit.lat_lng(latitude: 10.0, longitude: 20.0)
  let assert Ok(b) = geokit.lat_lng(latitude: 10.4, longitude: 20.3)
  simplify_line([a, b, a], tolerance: 0.45)
  |> should.equal(Ok([a, b, a]))
  simplify_line([a, b, a], tolerance: 0.55)
  |> should.equal(Ok([a, a]))
}

// --- error ---------------------------------------------------------------

pub fn simplify_negative_tolerance_test() -> Nil {
  let assert Ok(p) = geokit.lat_lng(latitude: 0.0, longitude: 0.0)
  case simplify_line([p], tolerance: -0.1) {
    Error(Nil) -> Nil
    _ -> should.be_true(False)
  }
}

// --- compute (issue #5) -------------------------------------------------

pub fn compute_point_test() -> Nil {
  let assert Ok(p) = geokit.lat_lng(latitude: 35.0, longitude: 139.0)
  let assert Ok(geom) = geokit.simplify(geokit.Point(p), tolerance: 0.001)
  case geom {
    geokit.Point(q) -> p |> should.equal(q)
    _ -> should.be_true(False)
  }
}

pub fn compute_line_string_drops_collinear_test() -> Nil {
  let assert Ok(a) = geokit.lat_lng(latitude: 0.0, longitude: 0.0)
  let assert Ok(b) = geokit.lat_lng(latitude: 0.0, longitude: 0.5)
  let assert Ok(c) = geokit.lat_lng(latitude: 0.0, longitude: 1.0)
  let assert Ok(geom) =
    geokit.simplify(geokit.LineString([a, b, c]), tolerance: 0.001)
  case geom {
    geokit.LineString(points) ->
      list.length(points)
      |> should.equal(2)
    _ -> should.be_true(False)
  }
}

pub fn compute_polygon_simplifies_each_ring_test() -> Nil {
  let assert Ok(a) = geokit.lat_lng(latitude: 0.0, longitude: 0.0)
  let assert Ok(b) = geokit.lat_lng(latitude: 0.0, longitude: 0.5)
  let assert Ok(c) = geokit.lat_lng(latitude: 0.0, longitude: 1.0)
  let assert Ok(d) = geokit.lat_lng(latitude: 1.0, longitude: 1.0)
  let assert Ok(e) = geokit.lat_lng(latitude: 1.0, longitude: 0.0)
  // Exterior ring has a collinear middle point on the bottom edge
  // that should be dropped.
  let ring = [a, b, c, d, e, a]
  let assert Ok(geom) =
    geokit.simplify(geokit.Polygon([ring]), tolerance: 0.001)
  case geom {
    geokit.Polygon([simplified]) -> {
      // 5 corners + closure; middle of bottom edge dropped.
      list.length(simplified)
      |> should.equal(5)
    }
    _ -> should.be_true(False)
  }
}

pub fn compute_multi_point_is_no_op_test() -> Nil {
  let assert Ok(a) = geokit.lat_lng(latitude: 0.0, longitude: 0.0)
  let assert Ok(b) = geokit.lat_lng(latitude: 0.0, longitude: 0.5)
  let assert Ok(c) = geokit.lat_lng(latitude: 0.0, longitude: 1.0)
  // A bag of points has no edges to collapse, so simplify leaves it
  // unchanged regardless of tolerance.
  let assert Ok(geom) =
    geokit.simplify(geokit.MultiPoint([a, b, c]), tolerance: 0.001)
  case geom {
    geokit.MultiPoint(points) ->
      list.length(points)
      |> should.equal(3)
    _ -> should.be_true(False)
  }
}

pub fn compute_multipolygon_recurses_test() -> Nil {
  let assert Ok(a) = geokit.lat_lng(latitude: 0.0, longitude: 0.0)
  let assert Ok(b) = geokit.lat_lng(latitude: 0.0, longitude: 0.5)
  let assert Ok(c) = geokit.lat_lng(latitude: 0.0, longitude: 1.0)
  let polygon = [[a, b, c, a]]
  let assert Ok(geom) =
    geokit.simplify(geokit.MultiPolygon([polygon, polygon]), tolerance: 0.001)
  case geom {
    geokit.MultiPolygon(ps) ->
      list.length(ps)
      |> should.equal(2)
    _ -> should.be_true(False)
  }
}

pub fn compute_negative_tolerance_test() -> Nil {
  let assert Ok(p) = geokit.lat_lng(latitude: 0.0, longitude: 0.0)
  case geokit.simplify(geokit.Point(p), tolerance: -0.5) {
    Error(Nil) -> Nil
    _ -> should.be_true(False)
  }
}

// --- long inputs (20_000 points) ----------------------------------------

// 20_000 points walking the perimeter of the square [0, 10] x [0, 10]
// counter-clockwise from (0, 0). The ring is not closed.

pub fn simplify_long_square_test() -> Nil {
  let assert Ok(simplified) =
    simplify_line(square_perimeter(), tolerance: 1.0e-6)
  // Only the start and the three later corners survive.
  list.map(simplified, fn(p) { #(geokit.latitude(p), geokit.longitude(p)) })
  |> should.equal([
    #(0.0, 0.0),
    #(0.0, 10.0),
    #(10.0, 10.0),
    #(10.0, 0.0),
    #(10.0 -. 4999.0 /. 500.0, 0.0),
  ])
}

pub fn simplify_long_random_walk_test() -> Nil {
  let walk = random_walk(20_000)
  let assert Ok(simplified) = simplify_line(walk, tolerance: 0.05)
  // Count recorded from the recursive implementation this replaced
  // (it ran on Erlang; JavaScript overflowed its stack).
  list.length(simplified)
  |> should.equal(9694)
  list.first(simplified)
  |> should.equal(list.first(walk))
  list.last(simplified)
  |> should.equal(list.last(walk))
}

// Deterministic random walk from the Park-Miller generator (products
// stay below 2^53, so both targets agree).
fn random_walk(n: Int) -> List(geokit.LatLng) {
  let #(_, _, _, points) =
    list.fold(list.repeat(Nil, times: n), #(12_345, 0.0, 0.0, []), fn(acc, _) {
      let #(seed, lat, lng, points) = acc
      let seed = seed * 16_807 % 2_147_483_647
      let step_lat = int.to_float(seed % 2001 - 1000) /. 10_000.0
      let seed = seed * 16_807 % 2_147_483_647
      let step_lng = int.to_float(seed % 2001 - 1000) /. 10_000.0
      let lat = lat +. step_lat
      let lng = lng +. step_lng
      #(seed, lat, lng, [
        geokit.wrap_lat_lng(latitude: lat, longitude: lng),
        ..points
      ])
    })
  list.reverse(points)
}

// --- closed polygon rings -------------------------------------------------

fn ll(lat: Float, lng: Float) -> geokit.LatLng {
  geokit.wrap_lat_lng(latitude: lat, longitude: lng)
}

pub fn compute_polygon_keeps_ring_valid_test() -> Nil {
  // A square with a collinear point in the middle of every side. The
  // ring starts and ends at the same vertex, so plain Douglas-Peucker
  // over it measures every point against a zero-length chord.
  let ring = [
    ll(0.0, 0.0),
    ll(0.0, 5.0),
    ll(0.0, 10.0),
    ll(5.0, 10.0),
    ll(10.0, 10.0),
    ll(10.0, 5.0),
    ll(10.0, 0.0),
    ll(5.0, 0.0),
    ll(0.0, 0.0),
  ]
  let assert Ok(simplified) =
    geokit.simplify(geokit.Polygon([ring]), tolerance: 1.0)
  simplified
  |> should.equal(
    geokit.Polygon([
      [
        ll(0.0, 0.0),
        ll(0.0, 10.0),
        ll(10.0, 10.0),
        ll(10.0, 0.0),
        ll(0.0, 0.0),
      ],
    ]),
  )
  geojson.geometry_to_json(simplified)
  |> json.to_string
  |> json.parse(geojson.geometry_decoder())
  |> should.equal(Ok(simplified))
}

pub fn compute_polygon_keeps_four_position_ring_when_it_would_collapse_test() -> Nil {
  // A triangle (four positions) is already the smallest valid ring, so
  // it is kept as is at any tolerance.
  let ring = [ll(0.0, 0.0), ll(0.0, 10.0), ll(10.0, 10.0), ll(0.0, 0.0)]
  geokit.simplify(geokit.Polygon([ring]), tolerance: 100.0)
  |> should.equal(Ok(geokit.Polygon([ring])))
}

pub fn compute_polygon_falls_back_to_smallest_ring_test() -> Nil {
  // At a tolerance larger than the square, both halves reduce to their
  // endpoints and only three positions would remain. The result is the
  // smallest valid ring: the start, the pivot and the vertex farthest
  // from the chord between them, in ring order.
  let ring = [
    ll(0.0, 0.0),
    ll(0.0, 10.0),
    ll(10.0, 10.0),
    ll(10.0, 0.0),
    ll(0.0, 0.0),
  ]
  let assert Ok(simplified) =
    geokit.simplify(geokit.MultiPolygon([[ring]]), tolerance: 100.0)
  simplified
  |> should.equal(
    geokit.MultiPolygon([
      [[ll(0.0, 0.0), ll(0.0, 10.0), ll(10.0, 10.0), ll(0.0, 0.0)]],
    ]),
  )
  geojson.geometry_to_json(simplified)
  |> json.to_string
  |> json.parse(geojson.geometry_decoder())
  |> should.equal(Ok(simplified))
}

pub fn compute_polygon_fallback_keeps_ring_order_test() -> Nil {
  // The farthest remaining vertex lies after the pivot here, so it
  // follows the pivot in the fallback ring.
  let ring = [
    ll(0.0, 0.0),
    ll(1.0, 1.0),
    ll(10.0, 10.0),
    ll(0.0, 10.0),
    ll(0.0, 0.0),
  ]
  geokit.simplify(geokit.Polygon([ring]), tolerance: 100.0)
  |> should.equal(
    Ok(
      geokit.Polygon([
        [ll(0.0, 0.0), ll(10.0, 10.0), ll(0.0, 10.0), ll(0.0, 0.0)],
      ]),
    ),
  )
}

// A closed 1000-vertex ring around (0, 0) whose radius wobbles, so
// Douglas-Peucker keeps a different number of vertices per tolerance.
fn wobbly_ring() -> List(LatLng) {
  let vertices =
    list.repeat(Nil, times: 999)
    |> list.index_map(fn(_, i) {
      let angle = int.to_float(i) *. 2.0 *. maths.pi() /. 999.0
      let radius = 1.0 +. 0.1 *. int.to_float(i % 7) /. 7.0
      ll(radius *. maths.sin(angle), radius *. maths.cos(angle))
    })
  let assert [first, ..] = vertices
  list.append(vertices, [first])
}

pub fn compute_polygon_size_is_monotonic_in_tolerance_test() -> Nil {
  let ring = wobbly_ring()
  list.length(ring)
  |> should.equal(1000)
  let sizes =
    [0.0, 1.0e-4, 1.0e-3, 0.01, 0.05, 0.1, 0.5, 1.0, 2.0, 10.0, 1000.0]
    |> list.map(fn(tolerance) {
      let assert Ok(geokit.Polygon([simplified])) =
        geokit.simplify(geokit.Polygon([ring]), tolerance:)
      list.length(simplified)
    })
  list.window_by_2(sizes)
  |> list.each(fn(pair) {
    { pair.1 <= pair.0 }
    |> should.be_true
  })
  let assert Ok(last) = list.last(sizes)
  last
  |> should.equal(4)
}

// --- tiny segments --------------------------------------------------------

pub fn simplify_tiny_segment_test() -> Nil {
  // The chord from (0, 0) to (lng 1e-12, lat 0) is 1e-12 degrees long
  // and the middle point is 1e-12 degrees off it, so it survives a
  // tolerance of 0.9e-12 and is dropped at 1.1e-12.
  let a = ll(0.0, 0.0)
  let b = ll(1.0e-12, 0.5e-12)
  let c = ll(0.0, 1.0e-12)
  simplify_line([a, b, c], tolerance: 0.9e-12)
  |> should.equal(Ok([a, b, c]))
  simplify_line([a, b, c], tolerance: 1.1e-12)
  |> should.equal(Ok([a, c]))
}

// === point in polygon ======================================================

// --- helpers -------------------------------------------------------------

fn at(lat: Float, lng: Float) -> LatLng {
  geokit.wrap_lat_lng(latitude: lat, longitude: lng)
}

/// Closed 10 × 10 square with corners at (0, 0) and (10, 10).
fn square_ring() -> List(LatLng) {
  [at(0.0, 0.0), at(0.0, 10.0), at(10.0, 10.0), at(10.0, 0.0), at(0.0, 0.0)]
}

/// Closed 4 × 4 hole centred inside `square_ring`.
fn hole_ring() -> List(LatLng) {
  [at(3.0, 3.0), at(7.0, 3.0), at(7.0, 7.0), at(3.0, 7.0), at(3.0, 3.0)]
}

fn square() -> geokit.Geometry {
  geokit.Polygon([square_ring()])
}

fn square_with_hole() -> geokit.Geometry {
  geokit.Polygon([square_ring(), hole_ring()])
}

fn locate(geometry: geokit.Geometry, lat: Float, lng: Float) {
  geokit.locate(at(lat, lng), in: geometry)
}

fn contains(geometry: geokit.Geometry, lat: Float, lng: Float) {
  contains_point(at(lat, lng), in: geometry)
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
    geokit.Polygon([[at(0.0, 0.0), at(0.0, 4.0), at(4.0, 0.0), at(0.0, 0.0)]])
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
  let polygon = geokit.Polygon([square_ring(), stray_hole])
  locate(polygon, 25.0, 25.0) |> should.equal(Ok(Outside))
  locate(polygon, 20.0, 25.0) |> should.equal(Ok(Outside))
  locate(polygon, 5.0, 5.0) |> should.equal(Ok(Inside))
}

// --- concave polygons ----------------------------------------------------

/// A "U": the notch between the two arms spans lat 3..10, lng 3..7.
fn u_shape() -> geokit.Geometry {
  geokit.Polygon([
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
fn l_shape() -> geokit.Geometry {
  geokit.Polygon([
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
fn diamond() -> geokit.Geometry {
  geokit.Polygon([
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
    geokit.Polygon([
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
  let clockwise = geokit.Polygon([list.reverse(square_ring())])
  locate(clockwise, 5.0, 5.0) |> should.equal(Ok(Inside))
  locate(clockwise, 15.0, 5.0) |> should.equal(Ok(Outside))
  locate(clockwise, 0.0, 5.0) |> should.equal(Ok(OnBoundary))
}

pub fn empty_polygon_contains_nothing_test() -> Nil {
  locate(geokit.Polygon([]), 0.0, 0.0) |> should.equal(Ok(Outside))
  locate(geokit.Polygon([[]]), 0.0, 0.0) |> should.equal(Ok(Outside))
  contains(geokit.Polygon([]), 0.0, 0.0) |> should.equal(Ok(False))
}

pub fn two_point_ring_has_no_interior_test() -> Nil {
  let sliver = geokit.Polygon([[at(0.0, 0.0), at(0.0, 10.0)]])
  locate(sliver, 0.0, 5.0) |> should.equal(Ok(OnBoundary))
  locate(sliver, 1.0, 5.0) |> should.equal(Ok(Outside))
  locate(sliver, 0.0, 11.0) |> should.equal(Ok(Outside))
}

pub fn collinear_ring_has_no_interior_test() -> Nil {
  let flat =
    geokit.Polygon([
      [at(0.0, 0.0), at(5.0, 5.0), at(10.0, 10.0), at(0.0, 0.0)],
    ])
  locate(flat, 2.0, 2.0) |> should.equal(Ok(OnBoundary))
  locate(flat, 2.0, 3.0) |> should.equal(Ok(Outside))
  locate(flat, 11.0, 11.0) |> should.equal(Ok(Outside))
}

pub fn repeated_vertices_are_harmless_test() -> Nil {
  let stuttering =
    geokit.Polygon([
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
    geokit.Polygon([
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
    geokit.Polygon([
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
    geokit.MultiPolygon([
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
  let both = geokit.MultiPolygon([[square_ring()], far_square_rings()])
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
    geokit.MultiPolygon([[square_ring(), hole_ring()], island])
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
  let pair = geokit.MultiPolygon([[square_ring()], east])
  locate(pair, 5.0, 10.0) |> should.equal(Ok(OnBoundary))
  locate(pair, 5.0, 15.0) |> should.equal(Ok(Inside))
}

pub fn empty_multipolygon_contains_nothing_test() -> Nil {
  locate(geokit.MultiPolygon([]), 0.0, 0.0) |> should.equal(Ok(Outside))
  contains(geokit.MultiPolygon([]), 0.0, 0.0) |> should.equal(Ok(False))
}

// --- non-areal geometries ------------------------------------------------

pub fn non_polygon_geometries_are_rejected_test() -> Nil {
  let p = at(0.0, 0.0)
  let rejected = [
    geokit.Point(p),
    geokit.MultiPoint([p]),
    geokit.LineString([p, at(1.0, 1.0)]),
  ]
  list.each(rejected, fn(geometry) {
    geokit.locate(p, in: geometry)
    |> should.equal(Error(Nil))
    contains_point(p, in: geometry)
    |> should.equal(Error(Nil))
  })
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

fn simplify_line(
  points: List(LatLng),
  tolerance tolerance: Float,
) -> Result(List(LatLng), Nil) {
  case geokit.simplify(geokit.LineString(points), tolerance:) {
    Ok(geokit.LineString(simplified)) -> Ok(simplified)
    _ -> Error(Nil)
  }
}

// === multi line string =====================================================

pub fn signed_zero_is_stored_as_zero_test() -> Nil {
  let assert Ok(negative) = geokit.lat_lng(latitude: -0.0, longitude: -0.0)
  let assert Ok(positive) = geokit.lat_lng(latitude: 0.0, longitude: 0.0)
  negative |> should.equal(positive)
}

pub fn bounding_box_of_multi_line_string_test() -> Nil {
  geokit.bounding_box(
    geokit.MultiLineString([[ll(1.0, 2.0), ll(3.0, 4.0)], [ll(-1.0, 5.0)]]),
  )
  |> should.equal(
    Ok(geokit.BoundingBox(south_west: ll(-1.0, 2.0), north_east: ll(3.0, 5.0))),
  )
  geokit.bounding_box(geokit.MultiLineString([[], []]))
  |> should.equal(Error(Nil))
}

pub fn centroid_of_multi_line_string_is_the_vertex_mean_test() -> Nil {
  let lines = [[ll(0.0, 0.0), ll(0.0, 2.0)], [ll(3.0, 1.0)]]
  geokit.centroid(geokit.MultiLineString(lines))
  |> should.equal(geokit.centroid(geokit.LineString(list.flatten(lines))))
  geokit.centroid(geokit.MultiLineString(lines))
  |> should.equal(Ok(ll(1.0, 1.0)))
  geokit.centroid(geokit.MultiLineString([]))
  |> should.equal(Error(Nil))
}

pub fn simplify_multi_line_string_simplifies_each_line_test() -> Nil {
  let first = [ll(0.0, 0.0), ll(0.0, 0.5), ll(0.0, 1.0)]
  let second = [ll(1.0, 0.0), ll(2.0, 0.0), ll(3.0, 0.0), ll(3.0, 1.0)]
  geokit.simplify(geokit.MultiLineString([first, second]), tolerance: 0.001)
  |> should.equal(
    Ok(
      geokit.MultiLineString([
        [ll(0.0, 0.0), ll(0.0, 1.0)],
        [ll(1.0, 0.0), ll(3.0, 0.0), ll(3.0, 1.0)],
      ]),
    ),
  )
}

pub fn simplify_rejects_negative_tolerance_for_every_geometry_test() -> Nil {
  [
    geokit.Point(ll(0.0, 0.0)),
    geokit.MultiPoint([]),
    geokit.MultiLineString([]),
    geokit.Polygon([]),
  ]
  |> list.each(fn(geometry) {
    geokit.simplify(geometry, tolerance: -0.5) |> should.equal(Error(Nil))
  })
}

pub fn locate_in_multi_line_string_is_an_error_test() -> Nil {
  geokit.locate(
    ll(0.0, 0.0),
    in: geokit.MultiLineString([[ll(0.0, 0.0), ll(1.0, 1.0)]]),
  )
  |> should.equal(Error(Nil))
}
