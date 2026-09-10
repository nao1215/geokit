//// Point-in-polygon test for a [`Geometry`](./geometry.html#Geometry)
//// — the operation Turf.js calls `booleanPointInPolygon`.
////
//// The first ring of a `Polygon` is its exterior and every further
//// ring is a hole, so a point inside a hole is outside the polygon.
//// A `MultiPolygon` contains a point when any of its polygons does.
//// Rings may be closed (first point repeated at the end) or open —
//// an open ring is closed implicitly — and may run in either
//// direction.
////
//// A point exactly on a ring — on an edge or a vertex, of the
//// exterior or of a hole — is on the polygon's boundary.
//// [`contains`](#contains) counts the boundary as inside, like
//// Turf's default. [`locate`](#locate) reports it separately as
//// `OnBoundary`, so Turf's `ignoreBoundary: true` is
//// `locate(...) == Ok(Inside)`.
////
//// The test is planar ray casting, as in Turf: each edge is the
//// straight segment between its two vertices on the flat lng/lat
//// plane, not a great-circle arc. For polygons spanning many degrees
//// an edge therefore does not follow the shortest path between its
//// vertices. The antimeridian is not special-cased: a ring with
//// vertices at lng 170 and lng -170 encloses the wide band through
//// lng 0, and lng 180 and lng -180 are different points. Split a
//// shape that crosses the antimeridian into a `MultiPolygon` at ±180°,
//// as RFC 7946 §3.1.9 recommends.
////
//// Coordinates are only subtracted and multiplied, never divided. On
//// whole-degree coordinates the answer is therefore exact, points on
//// a ring included; elsewhere a point within rounding error of an
//// edge may be reported on either side of it.

import gleam/bool
import gleam/result

import geokit/geometry.{
  type Geometry, LineString, MultiPoint, MultiPolygon, Point, Polygon,
}
import geokit/latlng.{type LatLng}

/// Where a point lies relative to a polygon, as reported by
/// [`locate`](#locate).
pub type Location {
  /// Inside the exterior ring and outside every hole, not touching
  /// any ring.
  Inside
  /// On an edge or a vertex of the exterior ring or of a hole.
  OnBoundary
  /// Outside the exterior ring, or inside a hole.
  Outside
}

/// Errors returned by [`contains`](#contains) and [`locate`](#locate).
pub type PointInPolygonError {
  /// The geometry was a `Point`, `MultiPoint`, or `LineString`, none
  /// of which encloses an area.
  NotAPolygon
}

/// Whether `point` lies inside `geometry`, a `Polygon` or
/// `MultiPolygon`. A point on the boundary — an edge or a vertex of
/// any ring — counts as inside, like Turf's `booleanPointInPolygon`
/// default. A point inside a hole is outside. Use
/// [`locate`](#locate) to tell boundary points apart.
///
/// ```gleam
/// import geokit/geometry
/// import geokit/latlng
/// import geokit/point_in_polygon
///
/// let assert Ok(a) = latlng.new(lat: 0.0, lng: 0.0)
/// let assert Ok(b) = latlng.new(lat: 0.0, lng: 10.0)
/// let assert Ok(c) = latlng.new(lat: 10.0, lng: 10.0)
/// let assert Ok(d) = latlng.new(lat: 10.0, lng: 0.0)
/// let assert Ok(p) = latlng.new(lat: 5.0, lng: 5.0)
/// point_in_polygon.contains(
///   geometry: geometry.Polygon([[a, b, c, d, a]]),
///   point: p,
/// )
/// // == Ok(True)
/// ```
///
/// Any other geometry returns [`NotAPolygon`](#PointInPolygonError).
/// A polygon with no rings, or whose rings are empty, contains no
/// point.
pub fn contains(
  geometry geometry: Geometry,
  point point: LatLng,
) -> Result(Bool, PointInPolygonError) {
  use location <- result.map(locate(geometry: geometry, point: point))
  location != Outside
}

/// Where `point` lies relative to `geometry`, a `Polygon` or
/// `MultiPolygon`: `Inside`, `OnBoundary`, or `Outside`.
///
/// ```gleam
/// import geokit/geometry
/// import geokit/latlng
/// import geokit/point_in_polygon
///
/// let assert Ok(a) = latlng.new(lat: 0.0, lng: 0.0)
/// let assert Ok(b) = latlng.new(lat: 0.0, lng: 10.0)
/// let assert Ok(c) = latlng.new(lat: 10.0, lng: 10.0)
/// let assert Ok(d) = latlng.new(lat: 10.0, lng: 0.0)
/// let assert Ok(on_edge) = latlng.new(lat: 0.0, lng: 5.0)
/// point_in_polygon.locate(
///   geometry: geometry.Polygon([[a, b, c, d, a]]),
///   point: on_edge,
/// )
/// // == Ok(point_in_polygon.OnBoundary)
/// ```
///
/// For a `MultiPolygon` the answer is `Inside` when any member
/// polygon has the point inside, otherwise `OnBoundary` when any
/// member has it on its boundary, otherwise `Outside`. Any other
/// geometry returns [`NotAPolygon`](#PointInPolygonError).
pub fn locate(
  geometry geometry: Geometry,
  point point: LatLng,
) -> Result(Location, PointInPolygonError) {
  let lng = latlng.lng(point)
  let lat = latlng.lat(point)
  case geometry {
    Polygon(rings) -> Ok(locate_in_polygon(rings: rings, lng: lng, lat: lat))
    MultiPolygon(polygons) ->
      Ok(locate_in_polygons(
        polygons: polygons,
        lng: lng,
        lat: lat,
        best: Outside,
      ))
    Point(_) | MultiPoint(_) | LineString(_) -> Error(NotAPolygon)
  }
}

fn locate_in_polygons(
  polygons polygons: List(List(List(LatLng))),
  lng lng: Float,
  lat lat: Float,
  best best: Location,
) -> Location {
  case polygons {
    [] -> best
    [rings, ..rest] ->
      case locate_in_polygon(rings: rings, lng: lng, lat: lat) {
        Inside -> Inside
        OnBoundary ->
          locate_in_polygons(
            polygons: rest,
            lng: lng,
            lat: lat,
            best: OnBoundary,
          )
        Outside ->
          locate_in_polygons(polygons: rest, lng: lng, lat: lat, best: best)
      }
  }
}

fn locate_in_polygon(
  rings rings: List(List(LatLng)),
  lng lng: Float,
  lat lat: Float,
) -> Location {
  case rings {
    [] -> Outside
    [exterior, ..holes] ->
      case locate_in_ring(ring: exterior, lng: lng, lat: lat) {
        Inside -> locate_outside_holes(holes: holes, lng: lng, lat: lat)
        OnBoundary -> OnBoundary
        Outside -> Outside
      }
  }
}

fn locate_outside_holes(
  holes holes: List(List(LatLng)),
  lng lng: Float,
  lat lat: Float,
) -> Location {
  case holes {
    [] -> Inside
    [hole, ..rest] ->
      case locate_in_ring(ring: hole, lng: lng, lat: lat) {
        Inside -> Outside
        OnBoundary -> OnBoundary
        Outside -> locate_outside_holes(holes: rest, lng: lng, lat: lat)
      }
  }
}

fn locate_in_ring(
  ring ring: List(LatLng),
  lng lng: Float,
  lat lat: Float,
) -> Location {
  case ring {
    [] -> Outside
    [first, ..] ->
      walk_edges(
        remaining: ring,
        first: first,
        lng: lng,
        lat: lat,
        inside: False,
      )
  }
}

/// Cast a ray from the point towards increasing longitude and count
/// the edges it crosses (even-odd rule), stopping early when the
/// point lies on an edge. The last vertex connects back to the first,
/// which closes an open ring; for a closed ring that extra edge has
/// zero length and never counts as a crossing.
fn walk_edges(
  remaining remaining: List(LatLng),
  first first: LatLng,
  lng lng: Float,
  lat lat: Float,
  inside inside: Bool,
) -> Location {
  case remaining {
    [] -> parity_location(inside: inside)
    [from, ..rest] -> {
      let to = case rest {
        [] -> first
        [next, ..] -> next
      }
      case classify_edge(from: from, to: to, lng: lng, lat: lat) {
        OnEdge -> OnBoundary
        Crosses ->
          walk_edges(
            remaining: rest,
            first: first,
            lng: lng,
            lat: lat,
            inside: !inside,
          )
        Misses ->
          walk_edges(
            remaining: rest,
            first: first,
            lng: lng,
            lat: lat,
            inside: inside,
          )
      }
    }
  }
}

fn parity_location(inside inside: Bool) -> Location {
  use <- bool.guard(when: inside, return: Inside)
  Outside
}

type EdgeHit {
  OnEdge
  Crosses
  Misses
}

/// How the eastward ray from `(lng, lat)` meets the edge `from`–`to`.
///
/// `side` is the cross product of the edge vector and the vector from
/// `from` to the point: zero when the point is on the edge's line,
/// positive when it is to the left of the edge (seen from `from`
/// towards `to`). An edge that spans the ray's latitude crosses the
/// ray east of the point exactly when the point is left of an edge
/// heading north, or right of an edge heading south.
///
/// An edge spans the ray's latitude when exactly one endpoint is
/// strictly north of it. This half-open rule counts a ray through a
/// vertex once when the ring passes through that latitude, and zero
/// or two times when the ring only touches it, and it ignores edges
/// that run along the ray.
fn classify_edge(
  from from: LatLng,
  to to: LatLng,
  lng lng: Float,
  lat lat: Float,
) -> EdgeHit {
  let from_lng = latlng.lng(from)
  let from_lat = latlng.lat(from)
  let to_lng = latlng.lng(to)
  let to_lat = latlng.lat(to)
  let side =
    { to_lng -. from_lng }
    *. { lat -. from_lat }
    -. { to_lat -. from_lat }
    *. { lng -. from_lng }
  // `side` can come out as -0.0, which `==` does not equate with 0.0
  // on the Erlang target; ordering comparisons treat the two zeros
  // alike on both targets.
  let on_edge =
    side >=. 0.0
    && side <=. 0.0
    && between(value: lng, first: from_lng, second: to_lng)
    && between(value: lat, first: from_lat, second: to_lat)
  use <- bool.guard(when: on_edge, return: OnEdge)
  let spans = { from_lat >. lat } != { to_lat >. lat }
  let east_of_point = case to_lat >. from_lat {
    True -> side >. 0.0
    False -> side <. 0.0
  }
  use <- bool.guard(when: spans && east_of_point, return: Crosses)
  Misses
}

fn between(
  value value: Float,
  first first: Float,
  second second: Float,
) -> Bool {
  { first <=. value && value <=. second }
  || { second <=. value && value <=. first }
}
