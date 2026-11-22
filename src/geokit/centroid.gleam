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
import gleam/result

import geokit/geometry.{
  type Geometry, LineString, MultiPoint, MultiPolygon, Point, Polygon,
}
import geokit/latlng.{type LatLng}

/// Errors returned by [`compute`](#compute).
pub type CentroidError {
  /// The geometry contained no points.
  EmptyGeometry
}

/// Convenience wrapper for callers who already hold a flat list of
/// points and don't want to mint a [`LineString`](../geometry.html#Geometry)
/// just to feed it in. Mirrors the
/// [`simplify.line_string`](../simplify.html#line_string) shape:
/// `LineString` carries edge / ordering semantics that the
/// unweighted-mean-of-vertices computation used by
/// `centroid.compute` for `LineString` does not actually rely on,
/// so wrapping a bag of points in `LineString` reads as noise at
/// the call site.
///
/// ```gleam
/// import geokit/centroid
/// import geokit/latlng
///
/// let assert Ok(a) = latlng.new(lat: 0.0, lng: 0.0)
/// let assert Ok(b) = latlng.new(lat: 10.0, lng: 10.0)
/// let assert Ok(c) = centroid.of_points([a, b])
/// // c is the mean of a and b.
/// ```
///
/// Equivalent to `centroid.compute(MultiPoint(points))` — wraps the
/// list in the variant that matches a bag-of-points semantically (no
/// edge or ordering implied). Empty input returns
/// [`EmptyGeometry`](#CentroidError).
///
/// When the input is a closed ring (first vertex equal to last —
/// the shape GeoJSON Polygon linear rings carry per RFC 7946
/// §3.1.6), the trailing duplicate is dropped before the mean so
/// the closing vertex is not double-counted. Two-element rings
/// where both vertices are equal are left alone (their mean is
/// already that point). Interior adjacent duplicates are
/// **preserved** — they may be deliberate.
///
/// For the geometric (signed-area) centroid of a Polygon, use
/// `centroid.compute(Polygon(...))`.
pub fn of_points(points points: List(LatLng)) -> Result(LatLng, CentroidError) {
  compute(geometry: MultiPoint(drop_closing_duplicate(points)))
}

/// Drop the last vertex when the input is a closed ring of three or
/// more vertices (first == last). Empty lists, single-vertex lists,
/// and two-vertex lists pass through unchanged.
fn drop_closing_duplicate(points: List(LatLng)) -> List(LatLng) {
  case points, list.reverse(points) {
    [first, _, _, ..], [last, ..before_last] ->
      case latlng.equal(first, last) {
        True -> list.reverse(before_last)
        False -> points
      }
    _, _ -> points
  }
}

/// Compute the centroid of `geometry`.
pub fn compute(geometry geometry: Geometry) -> Result(LatLng, CentroidError) {
  case geometry {
    Point(p) -> Ok(p)
    MultiPoint(points) -> mean_of_points(points: points)
    LineString(points) -> mean_of_points(points: points)
    Polygon(rings) -> polygon_centroid(rings: rings)
    MultiPolygon(polygons) -> multipolygon_centroid(polygons: polygons)
  }
}

fn mean_of_points(
  points points: List(LatLng),
) -> Result(LatLng, CentroidError) {
  case points {
    [] -> Error(EmptyGeometry)
    _ -> {
      let #(sum_lat, sum_lng, count) =
        list.fold(points, #(0.0, 0.0, 0), fn(sums, p) {
          let #(sum_lat, sum_lng, count) = sums
          #(sum_lat +. latlng.lat(p), sum_lng +. latlng.lng(p), count + 1)
        })
      let count_f = int.to_float(count)
      Ok(latlng.wrap(lat: sum_lat /. count_f, lng: sum_lng /. count_f))
    }
  }
}

// First moments and twice the area of a polygon, accumulated over its
// rings with the shoelace formula. The centroid is
// `#(sum_x, sum_y) / (3 * area_twice)`; sums of several polygons give
// the area-weighted centroid of the whole.
type Moments {
  Moments(sum_x: Float, sum_y: Float, area_twice: Float)
}

fn polygon_centroid(
  rings rings: List(List(LatLng)),
) -> Result(LatLng, CentroidError) {
  use exterior <- result.try(exterior_ring(rings: rings))
  from_moments(moments: polygon_moments(rings: rings), fallback: fn() {
    mean_of_points(points: exterior)
  })
}

fn multipolygon_centroid(
  polygons polygons: List(List(List(LatLng))),
) -> Result(LatLng, CentroidError) {
  let polygons =
    list.filter(polygons, fn(rings) { result.is_ok(exterior_ring(rings:)) })
  case polygons {
    [] -> Error(EmptyGeometry)
    _ -> {
      let total =
        list.fold(polygons, Moments(0.0, 0.0, 0.0), fn(total, rings) {
          add_moments(total, polygon_moments(rings: rings))
        })
      from_moments(moments: total, fallback: fn() {
        // Every polygon has zero area: average what each one falls back
        // to.
        list.filter_map(polygons, polygon_centroid)
        |> mean_of_points
      })
    }
  }
}

// The exterior ring, or `EmptyGeometry` when there is no ring or the
// exterior has no points.
fn exterior_ring(
  rings rings: List(List(LatLng)),
) -> Result(List(LatLng), CentroidError) {
  case rings {
    [[_, ..] as exterior, ..] -> Ok(exterior)
    _ -> Error(EmptyGeometry)
  }
}

// Whatever the winding order, the exterior counts with positive area
// and every hole with negative area, as in GEOS / Shapely.
fn polygon_moments(rings rings: List(List(LatLng))) -> Moments {
  case rings {
    [] -> Moments(0.0, 0.0, 0.0)
    [exterior, ..holes] ->
      list.fold(
        holes,
        oriented(ring_moments(exterior), positive: True),
        fn(total, hole) {
          add_moments(total, oriented(ring_moments(hole), positive: False))
        },
      )
  }
}

fn oriented(moments: Moments, positive positive: Bool) -> Moments {
  use <- bool.guard(
    when: { moments.area_twice <. 0.0 } != positive,
    return: moments,
  )
  Moments(
    sum_x: 0.0 -. moments.sum_x,
    sum_y: 0.0 -. moments.sum_y,
    area_twice: 0.0 -. moments.area_twice,
  )
}

fn add_moments(a: Moments, b: Moments) -> Moments {
  Moments(
    sum_x: a.sum_x +. b.sum_x,
    sum_y: a.sum_y +. b.sum_y,
    area_twice: a.area_twice +. b.area_twice,
  )
}

fn from_moments(
  moments moments: Moments,
  fallback fallback: fn() -> Result(LatLng, CentroidError),
) -> Result(LatLng, CentroidError) {
  let area_twice = moments.area_twice
  // Numeric test so a -0.0 total also counts as zero on Erlang.
  use <- bool.lazy_guard(
    when: area_twice >=. 0.0 && area_twice <=. 0.0,
    return: fallback,
  )
  let factor = 1.0 /. { 3.0 *. area_twice }
  Ok(latlng.wrap(lat: moments.sum_y *. factor, lng: moments.sum_x *. factor))
}

fn ring_moments(ring: List(LatLng)) -> Moments {
  ring_sums(points: ensure_closed(points: ring), acc: Moments(0.0, 0.0, 0.0))
}

fn ring_sums(points points: List(LatLng), acc acc: Moments) -> Moments {
  case points {
    [a, b, ..rest] -> {
      let x0 = latlng.lng(a)
      let y0 = latlng.lat(a)
      let x1 = latlng.lng(b)
      let y1 = latlng.lat(b)
      let cross = x0 *. y1 -. x1 *. y0
      ring_sums(
        points: [b, ..rest],
        acc: Moments(
          sum_x: acc.sum_x +. { x0 +. x1 } *. cross,
          sum_y: acc.sum_y +. { y0 +. y1 } *. cross,
          area_twice: acc.area_twice +. cross,
        ),
      )
    }
    _ -> acc
  }
}

fn ensure_closed(points points: List(LatLng)) -> List(LatLng) {
  case points, list.last(points) {
    [first, ..], Ok(last) ->
      case latlng.equal(first, last) {
        True -> points
        False -> list.append(points, [first])
      }
    _, _ -> points
  }
}
