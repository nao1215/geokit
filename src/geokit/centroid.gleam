//// Centroid (geometric centre) of a [`Geometry`](./geometry.html#Geometry).
////
//// For a `Point`, the centroid is the point itself. For a
//// `LineString` it is the arithmetic mean of its vertices. For a
//// `Polygon` it is the centroid of the exterior ring weighted by
//// the signed area of each triangle, which is the correct mean for
//// a planar polygon (Turfjs / Shapely use the same formula).
////
//// All computations treat the Earth as a flat plane in lat/lng — no
//// projection is applied. For polygons spanning more than a few
//// degrees, project to Web Mercator first
//// (see [`geokit/mercator`](./mercator.html)) for an
//// area-accurate centroid.

import gleam/bool
import gleam/int
import gleam/list

import geokit/geometry.{type Geometry, LineString, MultiPolygon, Point, Polygon}
import geokit/latlng.{type LatLng}

/// Errors returned by [`compute`](#compute).
pub type CentroidError {
  /// The geometry contained no points.
  EmptyGeometry
}

/// Compute the centroid of `geometry`.
pub fn compute(geometry geometry: Geometry) -> Result(LatLng, CentroidError) {
  case geometry {
    Point(p) -> Ok(p)
    LineString(points) -> mean_of_points(points: points)
    Polygon(rings) -> polygon_centroid(rings: rings)
    MultiPolygon(polygons) -> multipolygon_centroid(polygons: polygons)
  }
}

fn mean_of_points(points points: List(LatLng)) -> Result(LatLng, CentroidError) {
  use <- bool.guard(when: list.is_empty(points), return: Error(EmptyGeometry))
  let #(sum_lat, sum_lng, count) =
    sum_points(points: points, sum_lat: 0.0, sum_lng: 0.0, count: 0)
  let count_f = int_to_float(count)
  Ok(latlng.wrap(lat: sum_lat /. count_f, lng: sum_lng /. count_f))
}

fn sum_points(
  points points: List(LatLng),
  sum_lat sum_lat: Float,
  sum_lng sum_lng: Float,
  count count: Int,
) -> #(Float, Float, Int) {
  case points {
    [] -> #(sum_lat, sum_lng, count)
    [head, ..tail] ->
      sum_points(
        points: tail,
        sum_lat: sum_lat +. latlng.lat(head),
        sum_lng: sum_lng +. latlng.lng(head),
        count: count + 1,
      )
  }
}

fn polygon_centroid(
  rings rings: List(List(LatLng)),
) -> Result(LatLng, CentroidError) {
  case rings {
    [] -> Error(EmptyGeometry)
    [exterior, ..] -> ring_centroid(ring: exterior)
  }
}

fn ring_centroid(ring ring: List(LatLng)) -> Result(LatLng, CentroidError) {
  case ring {
    [] -> Error(EmptyGeometry)
    [single] -> Ok(single)
    _ -> ring_centroid_weighted(ring: ring)
  }
}

fn ring_centroid_weighted(
  ring ring: List(LatLng),
) -> Result(LatLng, CentroidError) {
  let closed = ensure_closed(points: ring)
  let #(sum_x, sum_y, signed_area_twice) =
    ring_sums(points: closed, sum_x: 0.0, sum_y: 0.0, area_twice: 0.0)
  use <- bool.guard(
    when: signed_area_twice == 0.0,
    return: mean_of_points(points: ring),
  )
  let factor = 1.0 /. { 3.0 *. signed_area_twice }
  Ok(latlng.wrap(lat: sum_y *. factor, lng: sum_x *. factor))
}

fn ring_sums(
  points points: List(LatLng),
  sum_x sum_x: Float,
  sum_y sum_y: Float,
  area_twice area_twice: Float,
) -> #(Float, Float, Float) {
  case points {
    [] -> #(sum_x, sum_y, area_twice)
    [_] -> #(sum_x, sum_y, area_twice)
    [a, b, ..rest] -> {
      let x0 = latlng.lng(a)
      let y0 = latlng.lat(a)
      let x1 = latlng.lng(b)
      let y1 = latlng.lat(b)
      let cross = x0 *. y1 -. x1 *. y0
      ring_sums(
        points: [b, ..rest],
        sum_x: sum_x +. { x0 +. x1 } *. cross,
        sum_y: sum_y +. { y0 +. y1 } *. cross,
        area_twice: area_twice +. cross,
      )
    }
  }
}

fn ensure_closed(points points: List(LatLng)) -> List(LatLng) {
  case points {
    [] -> []
    [head, ..] -> {
      let last = last_of(points: points, fallback: head)
      use <- bool.guard(when: latlng.equal(head, last), return: points)
      append_one(items: points, value: head)
    }
  }
}

fn last_of(points points: List(LatLng), fallback fallback: LatLng) -> LatLng {
  case points {
    [] -> fallback
    [single] -> single
    [_, ..tail] -> last_of(points: tail, fallback: fallback)
  }
}

fn append_one(items items: List(LatLng), value value: LatLng) -> List(LatLng) {
  case items {
    [] -> [value]
    [head, ..tail] -> [head, ..append_one(items: tail, value: value)]
  }
}

fn multipolygon_centroid(
  polygons polygons: List(List(List(LatLng))),
) -> Result(LatLng, CentroidError) {
  let centroids =
    list.filter_map(polygons, fn(polygon) { polygon_centroid(rings: polygon) })
  case centroids {
    [] -> Error(EmptyGeometry)
    _ -> mean_of_points(points: centroids)
  }
}

fn int_to_float(value: Int) -> Float {
  int.to_float(value)
}
