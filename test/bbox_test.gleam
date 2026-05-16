import gleeunit/should

import geokit/bbox
import geokit/geometry
import geokit/latlng

// --- point ---------------------------------------------------------------

pub fn bbox_of_point_test() -> Nil {
  let assert Ok(p) = latlng.new(lat: 35.6812, lng: 139.7671)
  let assert Ok(#(sw, ne)) = bbox.compute(geometry: geometry.Point(p))
  latlng.lat(sw)
  |> should.equal(35.6812)
  latlng.lat(ne)
  |> should.equal(35.6812)
  latlng.lng(sw)
  |> should.equal(139.7671)
  latlng.lng(ne)
  |> should.equal(139.7671)
}

// --- line string ---------------------------------------------------------

pub fn bbox_of_line_string_test() -> Nil {
  let assert Ok(a) = latlng.new(lat: 35.0, lng: 139.0)
  let assert Ok(b) = latlng.new(lat: 36.0, lng: 140.0)
  let assert Ok(c) = latlng.new(lat: 34.5, lng: 139.5)
  let assert Ok(#(sw, ne)) =
    bbox.compute(geometry: geometry.LineString([a, b, c]))
  latlng.lat(sw)
  |> should.equal(34.5)
  latlng.lat(ne)
  |> should.equal(36.0)
  latlng.lng(sw)
  |> should.equal(139.0)
  latlng.lng(ne)
  |> should.equal(140.0)
}

// --- polygon -------------------------------------------------------------

pub fn bbox_of_polygon_test() -> Nil {
  let assert Ok(a) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(b) = latlng.new(lat: 0.0, lng: 10.0)
  let assert Ok(c) = latlng.new(lat: 10.0, lng: 10.0)
  let assert Ok(d) = latlng.new(lat: 10.0, lng: 0.0)
  let assert Ok(#(sw, ne)) =
    bbox.compute(geometry: geometry.Polygon([[a, b, c, d, a]]))
  latlng.lat(sw)
  |> should.equal(0.0)
  latlng.lat(ne)
  |> should.equal(10.0)
  latlng.lng(sw)
  |> should.equal(0.0)
  latlng.lng(ne)
  |> should.equal(10.0)
}

// --- empty ---------------------------------------------------------------

pub fn bbox_empty_line_string_test() -> Nil {
  case bbox.compute(geometry: geometry.LineString([])) {
    Error(bbox.EmptyGeometry) -> Nil
    _ -> should.be_true(False)
  }
}

pub fn bbox_empty_polygon_test() -> Nil {
  case bbox.compute(geometry: geometry.Polygon([])) {
    Error(bbox.EmptyGeometry) -> Nil
    _ -> should.be_true(False)
  }
}

// --- of_points (List(LatLng) convenience wrapper) -----------------------

pub fn bbox_of_points_matches_line_string_test() -> Nil {
  let assert Ok(a) = latlng.new(lat: 35.0, lng: 139.0)
  let assert Ok(b) = latlng.new(lat: 36.0, lng: 140.0)
  let assert Ok(c) = latlng.new(lat: 34.5, lng: 139.5)
  let assert Ok(#(sw, ne)) = bbox.of_points([a, b, c])
  latlng.lat(sw)
  |> should.equal(34.5)
  latlng.lat(ne)
  |> should.equal(36.0)
  latlng.lng(sw)
  |> should.equal(139.0)
  latlng.lng(ne)
  |> should.equal(140.0)
  // Same answer the LineString-based call gives.
  let assert Ok(#(sw_via_geom, ne_via_geom)) =
    bbox.compute(geometry: geometry.LineString([a, b, c]))
  latlng.equal(sw, sw_via_geom)
  |> should.be_true
  latlng.equal(ne, ne_via_geom)
  |> should.be_true
}

pub fn bbox_of_points_single_test() -> Nil {
  let assert Ok(p) = latlng.new(lat: 35.6812, lng: 139.7671)
  let assert Ok(#(sw, ne)) = bbox.of_points([p])
  latlng.equal(sw, p)
  |> should.be_true
  latlng.equal(ne, p)
  |> should.be_true
}

pub fn bbox_of_points_empty_test() -> Nil {
  case bbox.of_points([]) {
    Error(bbox.EmptyGeometry) -> Nil
    _ -> should.be_true(False)
  }
}

pub fn bbox_compute_multi_point_test() -> Nil {
  let assert Ok(a) = latlng.new(lat: 35.0, lng: 139.0)
  let assert Ok(b) = latlng.new(lat: 36.0, lng: 140.0)
  // `MultiPoint` is the variant `of_points` now wraps callers in; the
  // bbox answer must match the `LineString` form for the same points.
  let assert Ok(#(sw, ne)) = bbox.compute(geometry: geometry.MultiPoint([a, b]))
  let assert Ok(#(sw_via_line, ne_via_line)) =
    bbox.compute(geometry: geometry.LineString([a, b]))
  latlng.equal(sw, sw_via_line) |> should.be_true
  latlng.equal(ne, ne_via_line) |> should.be_true
}

pub fn bbox_compute_multi_point_empty_test() -> Nil {
  case bbox.compute(geometry: geometry.MultiPoint([])) {
    Error(bbox.EmptyGeometry) -> Nil
    _ -> should.be_true(False)
  }
}
