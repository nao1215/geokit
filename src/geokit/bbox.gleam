//// Bounding box computation for a [`Geometry`](./geometry.html#Geometry).
////
//// A bounding box is the smallest axis-aligned rectangle that
//// contains every point of the geometry. The box is reported as the
//// south-west and north-east corners. Empty inputs produce
//// [`EmptyGeometry`](#BBoxError).
////
//// The implementation does **not** account for the antimeridian: a
//// geometry that straddles 180° longitude is treated as if the
//// world were a flat rectangle and produces a box that spans almost
//// the entire globe in the longitude axis. Antimeridian-aware
//// bounding boxes (the "narrow" variant chosen by `Turfjs`,
//// `terraformer`, etc.) are an explicit design choice and are out
//// of scope for this module.

import gleam/bool

import geokit/geometry.{type Geometry, LineString, MultiPolygon, Point, Polygon}
import geokit/latlng.{type LatLng}

/// Errors returned by [`compute`](#compute).
pub type BBoxError {
  /// The geometry contained no points (an empty `LineString`,
  /// `Polygon`, or `MultiPolygon`).
  EmptyGeometry
}

/// Compute the bounding box of `geometry` as `#(sw, ne)`.
pub fn compute(
  geometry geometry: Geometry,
) -> Result(#(LatLng, LatLng), BBoxError) {
  case all_points(geometry) {
    [] -> Error(EmptyGeometry)
    [head, ..tail] -> {
      let #(min_lat, max_lat, min_lng, max_lng) =
        extend_loop(
          points: tail,
          min_lat: latlng.lat(head),
          max_lat: latlng.lat(head),
          min_lng: latlng.lng(head),
          max_lng: latlng.lng(head),
        )
      let sw = latlng.wrap(lat: min_lat, lng: min_lng)
      let ne = latlng.wrap(lat: max_lat, lng: max_lng)
      Ok(#(sw, ne))
    }
  }
}

fn extend_loop(
  points points: List(LatLng),
  min_lat min_lat: Float,
  max_lat max_lat: Float,
  min_lng min_lng: Float,
  max_lng max_lng: Float,
) -> #(Float, Float, Float, Float) {
  case points {
    [] -> #(min_lat, max_lat, min_lng, max_lng)
    [head, ..tail] -> {
      let lat = latlng.lat(head)
      let lng = latlng.lng(head)
      extend_loop(
        points: tail,
        min_lat: min_float(a: min_lat, b: lat),
        max_lat: max_float(a: max_lat, b: lat),
        min_lng: min_float(a: min_lng, b: lng),
        max_lng: max_float(a: max_lng, b: lng),
      )
    }
  }
}

fn all_points(geometry: Geometry) -> List(LatLng) {
  case geometry {
    Point(p) -> [p]
    LineString(ps) -> ps
    Polygon(rings) -> flatten_rings(rings)
    MultiPolygon(polygons) -> flatten_polygons(polygons)
  }
}

fn flatten_rings(rings: List(List(LatLng))) -> List(LatLng) {
  case rings {
    [] -> []
    [head, ..tail] -> append_list(head, flatten_rings(tail))
  }
}

fn flatten_polygons(polygons: List(List(List(LatLng)))) -> List(LatLng) {
  case polygons {
    [] -> []
    [head, ..tail] -> append_list(flatten_rings(head), flatten_polygons(tail))
  }
}

fn append_list(left: List(a), right: List(a)) -> List(a) {
  case left {
    [] -> right
    [head, ..tail] -> [head, ..append_list(tail, right)]
  }
}

fn min_float(a a: Float, b b: Float) -> Float {
  use <- bool.guard(when: a <. b, return: a)
  b
}

fn max_float(a a: Float, b b: Float) -> Float {
  use <- bool.guard(when: a >. b, return: a)
  b
}
