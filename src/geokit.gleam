//// Coordinates, geometries and the math on them: great-circle distance,
//// bearings, bounding boxes, centroids, Douglas-Peucker simplification
//// and point-in-polygon tests. Latitudes and longitudes are in degrees.
//// Planar operations treat longitude and latitude as x and y on a flat
//// plane and do not handle the antimeridian.
////
//// The encodings live in their own modules:
////
//// - [`geokit/geohash`](./geokit/geohash.html): geohash strings.
//// - [`geokit/polyline`](./geokit/polyline.html): encoded polylines.
//// - [`geokit/tile`](./geokit/tile.html): Web Mercator tiles and quadkeys.
//// - [`geokit/geojson`](./geokit/geojson.html): GeoJSON (RFC 7946).

import gleam/bool
import gleam/float
import gleam/list
import gleam/result
import gleam_community/maths

import geokit/internal/centroid
import geokit/internal/douglas_peucker

/// A position on the Earth in degrees. Build one with
/// [`lat_lng`](#lat_lng) or [`wrap_lat_lng`](#wrap_lat_lng).
pub opaque type LatLng {
  // Invariant: latitude is in [-90, 90], longitude is in [-180, 180],
  // neither is NaN, and neither is -0.0 (stored as 0.0 so that `==`
  // treats the two zeros alike on Erlang).
  LatLng(latitude: Float, longitude: Float)
}

/// The reason [`lat_lng`](#lat_lng) rejected its input.
pub type LatLngError {
  /// The latitude was outside [-90, 90] or was NaN.
  LatitudeOutOfRange(latitude: Float)
  /// The longitude was outside [-180, 180] or was NaN.
  LongitudeOutOfRange(longitude: Float)
}

/// A shape made of positions. Rings of a `Polygon` are the exterior
/// first, then the holes. Rings may be closed (first position repeated
/// at the end) or open.
pub type Geometry {
  Point(point: LatLng)
  MultiPoint(points: List(LatLng))
  LineString(points: List(LatLng))
  MultiLineString(lines: List(List(LatLng)))
  Polygon(rings: List(List(LatLng)))
  MultiPolygon(polygons: List(List(List(LatLng))))
}

/// An axis-aligned box given by its south-west and north-east corners.
pub type BoundingBox {
  BoundingBox(south_west: LatLng, north_east: LatLng)
}

/// Where a point lies relative to a polygon.
pub type Location {
  /// Inside the exterior ring and outside every hole.
  Inside
  /// On an edge or a vertex of any ring.
  OnBoundary
  /// Outside the exterior ring, or inside a hole.
  Outside
}

/// Mean Earth radius (WGS84), in meters.
const earth_radius_meters: Float = 6_371_008.8

// --- LatLng ---------------------------------------------------------------

/// Returns a position for a latitude in [-90, 90] and a longitude in
/// [-180, 180]. Returns an error naming the first value out of range.
///
/// ## Examples
///
/// ```gleam
/// lat_lng(latitude: 35.6812, longitude: 139.7671)
/// |> result.map(latitude)
/// // -> Ok(35.6812)
/// ```
///
/// ```gleam
/// lat_lng(latitude: 91.0, longitude: 0.0)
/// // -> Error(LatitudeOutOfRange(latitude: 91.0))
/// ```
pub fn lat_lng(
  latitude latitude: Float,
  longitude longitude: Float,
) -> Result(LatLng, LatLngError) {
  // Written as "inside the range" so that NaN, which fails every
  // comparison, is rejected (JavaScript can produce it; Erlang cannot).
  case
    latitude >=. -90.0 && latitude <=. 90.0,
    longitude >=. -180.0 && longitude <=. 180.0
  {
    True, True -> Ok(make(latitude:, longitude:))
    False, _ -> Error(LatitudeOutOfRange(latitude:))
    True, False -> Error(LongitudeOutOfRange(longitude:))
  }
}

/// Returns a position for any input by clamping the latitude to
/// [-90, 90] and wrapping the longitude into [-180, 180].
///
/// ## Examples
///
/// ```gleam
/// let point = wrap_lat_lng(latitude: 91.0, longitude: 181.0)
/// #(latitude(point), longitude(point))
/// // -> #(90.0, -179.0)
/// ```
///
/// ## Target specific behavior
///
/// Only JavaScript can produce infinite and NaN floats. There, an
/// infinite latitude clamps to the pole on its side, a NaN latitude
/// becomes 0.0 and an infinite or NaN longitude becomes 0.0.
pub fn wrap_lat_lng(
  latitude latitude: Float,
  longitude longitude: Float,
) -> LatLng {
  make(latitude: clamp_latitude(latitude), longitude: wrap_longitude(longitude))
}

// Adding 0.0 turns -0.0 into 0.0 and leaves every other value alone.
fn make(latitude latitude: Float, longitude longitude: Float) -> LatLng {
  LatLng(latitude: latitude +. 0.0, longitude: longitude +. 0.0)
}

fn clamp_latitude(latitude: Float) -> Float {
  use <- bool.guard(when: latitude >. 90.0, return: 90.0)
  use <- bool.guard(when: latitude <. -90.0, return: -90.0)
  use <- bool.guard(when: latitude >=. -90.0, return: latitude)
  // NaN fails every comparison above.
  0.0
}

fn wrap_longitude(longitude: Float) -> Float {
  // Values already in range are returned as they are, so the common case
  // is exact. Other values are reduced with floor, which is O(1) and
  // cannot ping-pong on floating-point cancellation.
  use <- bool.guard(
    when: longitude >=. -180.0 && longitude <=. 180.0,
    return: longitude,
  )
  let shifted = longitude +. 180.0
  let wrapped = shifted -. 360.0 *. float.floor(shifted /. 360.0)
  let result = wrapped -. 180.0
  use <- bool.guard(when: result >. 180.0, return: 180.0)
  use <- bool.guard(when: result <. -180.0, return: -180.0)
  use <- bool.guard(when: result >=. -180.0, return: result)
  // Only an infinite or NaN longitude gets here: the reduction above
  // turns it into NaN.
  0.0
}

/// Returns the latitude in degrees, in [-90, 90].
///
/// ## Examples
///
/// ```gleam
/// wrap_lat_lng(latitude: 35.0, longitude: 139.0) |> latitude
/// // -> 35.0
/// ```
pub fn latitude(point: LatLng) -> Float {
  point.latitude
}

/// Returns the longitude in degrees, in [-180, 180].
///
/// ## Examples
///
/// ```gleam
/// wrap_lat_lng(latitude: 35.0, longitude: 139.0) |> longitude
/// // -> 139.0
/// ```
pub fn longitude(point: LatLng) -> Float {
  point.longitude
}

// --- Distance and bearing -------------------------------------------------

/// Returns the great-circle distance in meters, computed with the
/// haversine formula on a sphere of radius 6,371,008.8 m.
///
/// ## Examples
///
/// ```gleam
/// let tokyo = wrap_lat_lng(latitude: 35.6812, longitude: 139.7671)
/// let osaka = wrap_lat_lng(latitude: 34.6937, longitude: 135.5023)
/// distance(from: tokyo, to: osaka) |> float.round
/// // -> 402_785
/// ```
pub fn distance(from from: LatLng, to to: LatLng) -> Float {
  let lat_from = maths.degrees_to_radians(from.latitude)
  let lat_to = maths.degrees_to_radians(to.latitude)
  let half_lat = maths.degrees_to_radians(to.latitude -. from.latitude) /. 2.0
  let half_lng = maths.degrees_to_radians(to.longitude -. from.longitude) /. 2.0
  let sin_half_lat = maths.sin(half_lat)
  let sin_half_lng = maths.sin(half_lng)
  let h =
    sin_half_lat
    *. sin_half_lat
    +. maths.cos(lat_from)
    *. maths.cos(lat_to)
    *. sin_half_lng
    *. sin_half_lng
  let h = float.clamp(h, min: 0.0, max: 1.0)
  let central_angle = 2.0 *. maths.atan2(sqrt_nonneg(h), sqrt_nonneg(1.0 -. h))
  earth_radius_meters *. central_angle
}

// Callers pass values in [0, 1], so `float.square_root` cannot fail.
fn sqrt_nonneg(value: Float) -> Float {
  case float.square_root(float.max(value, 0.0)) {
    Ok(root) -> root
    Error(Nil) -> 0.0
  }
}

/// Returns the direction of travel when leaving `from` on the
/// great-circle route to `to`, in degrees clockwise from true north, in
/// [0, 360).
///
/// ## Examples
///
/// ```gleam
/// let tokyo = wrap_lat_lng(latitude: 35.6812, longitude: 139.7671)
/// let osaka = wrap_lat_lng(latitude: 34.6937, longitude: 135.5023)
/// initial_bearing(from: tokyo, to: osaka) |> float.round
/// // -> 255
/// ```
pub fn initial_bearing(from from: LatLng, to to: LatLng) -> Float {
  let phi_1 = maths.degrees_to_radians(from.latitude)
  let phi_2 = maths.degrees_to_radians(to.latitude)
  let delta_lambda = maths.degrees_to_radians(to.longitude -. from.longitude)
  let y = maths.sin(delta_lambda) *. maths.cos(phi_2)
  let x =
    maths.cos(phi_1)
    *. maths.sin(phi_2)
    -. maths.sin(phi_1)
    *. maths.cos(phi_2)
    *. maths.cos(delta_lambda)
  normalize_degrees(maths.radians_to_degrees(maths.atan2(y, x)))
}

/// Returns the direction of travel when arriving at `to` on the
/// great-circle route from `from`, in degrees clockwise from true north,
/// in [0, 360).
///
/// ## Examples
///
/// ```gleam
/// let tokyo = wrap_lat_lng(latitude: 35.6812, longitude: 139.7671)
/// let osaka = wrap_lat_lng(latitude: 34.6937, longitude: 135.5023)
/// final_bearing(from: tokyo, to: osaka) |> float.round
/// // -> 253
/// ```
pub fn final_bearing(from from: LatLng, to to: LatLng) -> Float {
  normalize_degrees(initial_bearing(from: to, to: from) +. 180.0)
}

fn normalize_degrees(value: Float) -> Float {
  // Reduced with floor rather than repeated subtraction, which can fail
  // to terminate near 0 and 360.
  let result = value -. 360.0 *. float.floor(value /. 360.0)
  use <- bool.guard(when: result <. 0.0, return: 0.0)
  use <- bool.guard(when: result >=. 360.0, return: 0.0)
  result
}

// --- Planar operations ----------------------------------------------------

/// Returns the smallest box that contains every position of the
/// geometry. Returns `Error(Nil)` when the geometry has no positions. A
/// geometry that crosses the antimeridian gets a box spanning almost
/// every longitude.
///
/// ## Examples
///
/// ```gleam
/// let a = wrap_lat_lng(latitude: 35.0, longitude: 139.0)
/// let b = wrap_lat_lng(latitude: 36.0, longitude: 140.0)
/// bounding_box(LineString([a, b]))
/// // -> Ok(BoundingBox(south_west: a, north_east: b))
/// ```
///
/// ```gleam
/// bounding_box(MultiPoint([]))
/// // -> Error(Nil)
/// ```
pub fn bounding_box(geometry: Geometry) -> Result(BoundingBox, Nil) {
  case all_points(geometry) {
    [] -> Error(Nil)
    [head, ..tail] -> {
      let #(south, north, west, east) =
        list.fold(
          tail,
          #(head.latitude, head.latitude, head.longitude, head.longitude),
          fn(box, point) {
            let #(south, north, west, east) = box
            #(
              float.min(south, point.latitude),
              float.max(north, point.latitude),
              float.min(west, point.longitude),
              float.max(east, point.longitude),
            )
          },
        )
      Ok(BoundingBox(
        south_west: make(latitude: south, longitude: west),
        north_east: make(latitude: north, longitude: east),
      ))
    }
  }
}

fn all_points(geometry: Geometry) -> List(LatLng) {
  case geometry {
    Point(point) -> [point]
    MultiPoint(points) | LineString(points) -> points
    MultiLineString(lines) | Polygon(lines) -> list.flatten(lines)
    MultiPolygon(polygons) -> list.flat_map(polygons, list.flatten)
  }
}

/// Returns the centroid on the longitude/latitude plane. A `Point` is
/// its own centroid. `MultiPoint`, `LineString` and `MultiLineString`
/// give the mean of their vertices. A `Polygon` gives the area centroid
/// with holes subtracted, and a `MultiPolygon` weights its polygons by
/// area. A polygon with zero area falls back to the mean of its exterior
/// vertices. Returns `Error(Nil)` when there is nothing to average, such
/// as an empty list or a polygon without an exterior ring.
///
/// ## Examples
///
/// ```gleam
/// let ring = [
///   wrap_lat_lng(latitude: 0.0, longitude: 0.0),
///   wrap_lat_lng(latitude: 0.0, longitude: 4.0),
///   wrap_lat_lng(latitude: 2.0, longitude: 4.0),
///   wrap_lat_lng(latitude: 2.0, longitude: 0.0),
///   wrap_lat_lng(latitude: 0.0, longitude: 0.0),
/// ]
/// centroid(Polygon([ring])) |> result.map(longitude)
/// // -> Ok(2.0)
/// ```
///
/// ```gleam
/// centroid(LineString([]))
/// // -> Error(Nil)
/// ```
pub fn centroid(geometry: Geometry) -> Result(LatLng, Nil) {
  case geometry {
    Point(point) -> Ok(to_xy(point))
    MultiPoint(points) | LineString(points) ->
      centroid.mean(list.map(points, to_xy))
    MultiLineString(lines) -> centroid.mean(list.flat_map(lines, ring_to_xy))
    Polygon(rings) -> centroid.polygon(list.map(rings, ring_to_xy))
    MultiPolygon(polygons) ->
      centroid.polygons(
        list.map(polygons, fn(rings) { list.map(rings, ring_to_xy) }),
      )
  }
  |> result.map(from_xy)
}

/// Returns the geometry with Douglas-Peucker applied to every line and
/// ring. `tolerance` is a distance in degrees on the longitude/latitude
/// plane: a vertex is dropped when it lies within `tolerance` of the
/// chord between the vertices kept around it, so 0.0 removes only
/// collinear vertices. Every line keeps its first and last vertex, and a
/// closed ring stays closed with at least four positions. Points are
/// returned unchanged. Returns `Error(Nil)` when `tolerance` is negative.
///
/// ## Examples
///
/// ```gleam
/// let a = wrap_lat_lng(latitude: 0.0, longitude: 0.0)
/// let b = wrap_lat_lng(latitude: 0.0, longitude: 0.5)
/// let c = wrap_lat_lng(latitude: 0.0, longitude: 1.0)
/// simplify(LineString([a, b, c]), tolerance: 0.001)
/// // -> Ok(LineString([a, c]))
/// ```
///
/// ```gleam
/// simplify(LineString([]), tolerance: -1.0)
/// // -> Error(Nil)
/// ```
pub fn simplify(
  geometry: Geometry,
  tolerance tolerance: Float,
) -> Result(Geometry, Nil) {
  use <- bool.guard(when: tolerance <. 0.0, return: Error(Nil))
  let line = fn(points) {
    map_xy(points, douglas_peucker.line(_, tolerance: tolerance))
  }
  let rings = fn(rings) {
    list.map(rings, map_xy(_, douglas_peucker.ring(_, tolerance: tolerance)))
  }
  Ok(case geometry {
    Point(_) | MultiPoint(_) -> geometry
    LineString(points) -> LineString(line(points))
    MultiLineString(lines) -> MultiLineString(list.map(lines, line))
    Polygon(polygon) -> Polygon(rings(polygon))
    MultiPolygon(polygons) -> MultiPolygon(list.map(polygons, rings))
  })
}

fn to_xy(point: LatLng) -> #(Float, Float) {
  #(point.longitude, point.latitude)
}

fn ring_to_xy(ring: List(LatLng)) -> List(#(Float, Float)) {
  list.map(ring, to_xy)
}

fn from_xy(xy: #(Float, Float)) -> LatLng {
  wrap_lat_lng(latitude: xy.1, longitude: xy.0)
}

// Simplification only drops vertices, so every point it returns came
// from a valid `LatLng` and can be rebuilt as it was.
fn map_xy(
  points: List(LatLng),
  with transform: fn(List(#(Float, Float))) -> List(#(Float, Float)),
) -> List(LatLng) {
  points
  |> list.map(to_xy)
  |> transform
  |> list.map(fn(xy) { LatLng(latitude: xy.1, longitude: xy.0) })
}

// --- Point in polygon -----------------------------------------------------

/// Returns where `point` lies relative to a `Polygon` or `MultiPolygon`.
/// A point on an edge or vertex of any ring, holes included, is
/// `OnBoundary`, and a point inside a hole is `Outside`. For a
/// `MultiPolygon` the answer is `Inside` if any polygon has the point
/// inside, otherwise `OnBoundary` if any has it on its boundary. Edges
/// are straight lines on the longitude/latitude plane. Returns
/// `Error(Nil)` for the other geometries.
///
/// Coordinates are only subtracted and multiplied, so the answer is
/// exact for whole-degree coordinates. Elsewhere a point within rounding
/// error of an edge may be reported on either side of it.
///
/// ## Examples
///
/// ```gleam
/// let square = Polygon([[
///   wrap_lat_lng(latitude: 0.0, longitude: 0.0),
///   wrap_lat_lng(latitude: 0.0, longitude: 10.0),
///   wrap_lat_lng(latitude: 10.0, longitude: 10.0),
///   wrap_lat_lng(latitude: 10.0, longitude: 0.0),
/// ]])
/// locate(wrap_lat_lng(latitude: 5.0, longitude: 5.0), in: square)
/// // -> Ok(Inside)
/// locate(wrap_lat_lng(latitude: 0.0, longitude: 5.0), in: square)
/// // -> Ok(OnBoundary)
/// ```
///
/// ```gleam
/// let point = wrap_lat_lng(latitude: 0.0, longitude: 0.0)
/// locate(point, in: Point(point))
/// // -> Error(Nil)
/// ```
pub fn locate(point: LatLng, in geometry: Geometry) -> Result(Location, Nil) {
  case geometry {
    Polygon(rings) -> Ok(locate_in_polygon(rings, point:))
    MultiPolygon(polygons) ->
      Ok(locate_in_polygons(polygons, point:, best: Outside))
    Point(_) | MultiPoint(_) | LineString(_) | MultiLineString(_) -> Error(Nil)
  }
}

fn locate_in_polygons(
  polygons: List(List(List(LatLng))),
  point point: LatLng,
  best best: Location,
) -> Location {
  case polygons {
    [] -> best
    [rings, ..rest] ->
      case locate_in_polygon(rings, point:) {
        Inside -> Inside
        OnBoundary -> locate_in_polygons(rest, point:, best: OnBoundary)
        Outside -> locate_in_polygons(rest, point:, best:)
      }
  }
}

fn locate_in_polygon(
  rings: List(List(LatLng)),
  point point: LatLng,
) -> Location {
  case rings {
    [] -> Outside
    [exterior, ..holes] ->
      case locate_in_ring(exterior, point:) {
        Inside -> locate_outside_holes(holes, point:)
        location -> location
      }
  }
}

fn locate_outside_holes(
  holes: List(List(LatLng)),
  point point: LatLng,
) -> Location {
  case holes {
    [] -> Inside
    [hole, ..rest] ->
      case locate_in_ring(hole, point:) {
        Inside -> Outside
        OnBoundary -> OnBoundary
        Outside -> locate_outside_holes(rest, point:)
      }
  }
}

fn locate_in_ring(ring: List(LatLng), point point: LatLng) -> Location {
  case ring {
    [] -> Outside
    [first, ..] -> walk_edges(ring, first:, point:, inside: False)
  }
}

// Casts a ray from the point towards increasing longitude and counts the
// edges it crosses (even-odd rule), stopping early when the point lies
// on an edge. The last vertex connects back to the first, which closes
// an open ring; for a closed ring that extra edge has zero length and
// never counts as a crossing.
fn walk_edges(
  remaining: List(LatLng),
  first first: LatLng,
  point point: LatLng,
  inside inside: Bool,
) -> Location {
  case remaining {
    [] if inside -> Inside
    [] -> Outside
    [from, ..rest] -> {
      let to = case rest {
        [] -> first
        [next, ..] -> next
      }
      case classify_edge(from:, to:, point:) {
        OnEdge -> OnBoundary
        Crosses -> walk_edges(rest, first:, point:, inside: !inside)
        Misses -> walk_edges(rest, first:, point:, inside:)
      }
    }
  }
}

type EdgeHit {
  OnEdge
  Crosses
  Misses
}

// How the eastward ray from `point` meets the edge `from`-`to`.
//
// `side` is the cross product of the edge vector and the vector from
// `from` to the point: zero when the point is on the edge's line,
// positive when it is to the left of the edge (seen from `from` towards
// `to`). An edge that spans the ray's latitude crosses the ray east of
// the point exactly when the point is left of an edge heading north, or
// right of an edge heading south.
//
// An edge spans the ray's latitude when exactly one endpoint is strictly
// north of it. This half-open rule counts a ray through a vertex once
// when the ring passes through that latitude, and zero or two times when
// the ring only touches it, and it ignores edges that run along the ray.
fn classify_edge(
  from from: LatLng,
  to to: LatLng,
  point point: LatLng,
) -> EdgeHit {
  let LatLng(latitude: lat, longitude: lng) = point
  let side =
    { to.longitude -. from.longitude }
    *. { lat -. from.latitude }
    -. { to.latitude -. from.latitude }
    *. { lng -. from.longitude }
  // `side` can come out as -0.0, which `==` does not equate with 0.0 on
  // Erlang; ordering comparisons treat the two zeros alike.
  let on_edge =
    side >=. 0.0
    && side <=. 0.0
    && between(lng, from.longitude, to.longitude)
    && between(lat, from.latitude, to.latitude)
  use <- bool.guard(when: on_edge, return: OnEdge)
  let spans = { from.latitude >. lat } != { to.latitude >. lat }
  let east_of_point = case to.latitude >. from.latitude {
    True -> side >. 0.0
    False -> side <. 0.0
  }
  use <- bool.guard(when: spans && east_of_point, return: Crosses)
  Misses
}

fn between(value: Float, first: Float, second: Float) -> Bool {
  { first <=. value && value <=. second }
  || { second <=. value && value <=. first }
}
