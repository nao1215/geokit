//// Douglas-Peucker line simplification.
////
//// Reduces the number of points in a `LineString` while preserving
//// its general shape: any point further than `tolerance` from the
//// straight line between its neighbours is kept; closer ones are
//// discarded.
////
//// `tolerance` is a distance in *degrees* on the lat/lng plane — no
//// projection is applied. For polylines spanning more than a few
//// degrees, project to Web Mercator first
//// (see [`geokit/mercator`](./mercator.html)) and convert your
//// tolerance to pixels. For short segments (city-scale and below)
//// the planar approximation is well within rendering tolerance.
////
//// Reference:
//// Douglas, D.; Peucker, T. (1973), "Algorithms for the reduction
//// of the number of points required to represent a digitized line
//// or its caricature".

import gleam/bool
import gleam/float
import gleam/list
import gleam/result

import geokit/geometry.{
  type Geometry, LineString, MultiPoint, MultiPolygon, Point, Polygon,
}
import geokit/latlng.{type LatLng}

/// Errors returned by [`line_string`](#line_string).
pub type SimplifyError {
  /// `tolerance` was negative.
  NegativeTolerance(tolerance: Float)
}

/// Simplify a sequence of points using Douglas-Peucker.
/// `tolerance` is in degrees. Larger values keep fewer points.
///
/// A tolerance of `0.0` is the **canonical Douglas-Peucker
/// behaviour**: it drops every intermediate point that lies
/// *exactly* on the straight line between its surviving neighbours,
/// because the comparison `perpendicular_distance >. tolerance` is
/// strict. Use a tiny positive value (for example `1.0e-12`) if you
/// want to preserve every point.
///
/// ```gleam
/// import geokit/simplify
/// import geokit/latlng
///
/// let assert Ok(a) = latlng.new(lat: 0.0, lng: 0.0)
/// let assert Ok(b) = latlng.new(lat: 0.0, lng: 0.5)
/// let assert Ok(c) = latlng.new(lat: 0.0, lng: 1.0)
/// let assert Ok(simplified) =
///   simplify.line_string(points: [a, b, c], tolerance: 0.001)
/// // simplified == [a, c]  (b is on the straight line between a and c)
/// ```
pub fn line_string(
  points points: List(LatLng),
  tolerance tolerance: Float,
) -> Result(List(LatLng), SimplifyError) {
  use <- bool.guard(
    when: tolerance <. 0.0,
    return: Error(NegativeTolerance(tolerance: tolerance)),
  )
  case points {
    [] -> Ok([])
    [single] -> Ok([single])
    [a, b] -> Ok([a, b])
    [first, ..rest] -> Ok(dp(first: first, rest: rest, tolerance: tolerance))
  }
}

/// Simplify any [`Geometry`](../geometry.html#Geometry), matching the
/// [`bbox.compute`](../bbox.html#compute) /
/// [`centroid.compute`](../centroid.html#compute) call shape.
///
/// - `Point` is returned unchanged.
/// - `LineString` is simplified via [`line_string`](#line_string).
/// - `Polygon` simplifies each ring; closure is preserved by always
///   keeping the first and last vertex of each ring.
/// - `MultiPolygon` recurses into each polygon.
///
/// ```gleam
/// import geokit/geometry
/// import geokit/simplify
///
/// let result =
///   geometry.LineString([a, b, c])
///   |> simplify.compute(tolerance: 0.001)
/// ```
pub fn compute(
  geometry geometry: Geometry,
  tolerance tolerance: Float,
) -> Result(Geometry, SimplifyError) {
  use <- bool.guard(
    when: tolerance <. 0.0,
    return: Error(NegativeTolerance(tolerance: tolerance)),
  )
  case geometry {
    Point(_) -> Ok(geometry)
    // A bag of unconnected points has no inter-point edges to
    // collapse, so simplification is a no-op at any tolerance.
    MultiPoint(_) -> Ok(geometry)
    LineString(points) -> {
      use simplified <- result.map(line_string(
        points: points,
        tolerance: tolerance,
      ))
      LineString(simplified)
    }
    Polygon(rings) -> {
      use new_rings <- result.map(
        simplify_rings(rings: rings, tolerance: tolerance, acc: []),
      )
      Polygon(new_rings)
    }
    MultiPolygon(polygons) -> {
      use new_polygons <- result.map(
        simplify_polygons(polygons: polygons, tolerance: tolerance, acc: []),
      )
      MultiPolygon(new_polygons)
    }
  }
}

fn simplify_rings(
  rings rings: List(List(LatLng)),
  tolerance tolerance: Float,
  acc acc: List(List(LatLng)),
) -> Result(List(List(LatLng)), SimplifyError) {
  case rings {
    [] -> Ok(list.reverse(acc))
    [head, ..tail] -> {
      use simplified <- result.try(ring(points: head, tolerance: tolerance))
      simplify_rings(rings: tail, tolerance: tolerance, acc: [simplified, ..acc])
    }
  }
}

// A closed ring starts and ends at the same vertex, so Douglas-Peucker
// over the whole ring would measure every point against a zero-length
// chord and could keep only the closing pair. Split at the vertex
// farthest from the start instead, simplify both halves and rejoin. A
// result with fewer than four positions is not a valid ring, so the
// original ring is kept in that case. Unclosed rings are simplified as
// a line.
fn ring(
  points points: List(LatLng),
  tolerance tolerance: Float,
) -> Result(List(LatLng), SimplifyError) {
  case points, list.last(points) {
    [first, second, third, fourth, ..more], Ok(last) ->
      case latlng.equal(first, last) {
        True ->
          Ok(closed_ring(
            ring: points,
            first: first,
            rest: [second, third, fourth, ..more],
            tolerance: tolerance,
          ))
        False -> line_string(points: points, tolerance: tolerance)
      }
    _, _ -> line_string(points: points, tolerance: tolerance)
  }
}

fn closed_ring(
  ring ring: List(LatLng),
  first first: LatLng,
  rest rest: List(LatLng),
  tolerance tolerance: Float,
) -> List(LatLng) {
  case farthest_from(origin: first, points: rest) {
    Error(Nil) -> ring
    Ok(#(before, pivot, after)) -> {
      let left =
        dp(
          first: first,
          rest: list.reverse([pivot, ..before]),
          tolerance: tolerance,
        )
      let right = dp(first: pivot, rest: after, tolerance: tolerance)
      let joined = list.append(left, list.drop(right, 1))
      case list.length(joined) < 4 {
        True -> ring
        False -> joined
      }
    }
  }
}

// The point of `points` farthest from `origin` (the earliest one on
// ties), with the points before it (reversed) and after it.
fn farthest_from(
  origin origin: LatLng,
  points points: List(LatLng),
) -> Result(#(List(LatLng), LatLng, List(LatLng)), Nil) {
  case points {
    [] -> Error(Nil)
    [head, ..tail] -> {
      let #(_, before, pivot, after) =
        farthest_loop(points: tail, a: origin, b: origin, seen: [head], best: #(
          perpendicular_distance(p: head, a: origin, b: origin),
          [],
          head,
          tail,
        ))
      Ok(#(before, pivot, after))
    }
  }
}

fn simplify_polygons(
  polygons polygons: List(List(List(LatLng))),
  tolerance tolerance: Float,
  acc acc: List(List(List(LatLng))),
) -> Result(List(List(List(LatLng))), SimplifyError) {
  case polygons {
    [] -> Ok(list.reverse(acc))
    [head, ..tail] -> {
      use simplified <- result.try(
        simplify_rings(rings: head, tolerance: tolerance, acc: []),
      )
      simplify_polygons(polygons: tail, tolerance: tolerance, acc: [
        simplified,
        ..acc
      ])
    }
  }
}

// A span of the input between two kept points: `first`, the points in
// between (in input order) and `last`.
type Span {
  Span(first: LatLng, middle: List(LatLng), last: LatLng)
}

// Douglas-Peucker with an explicit stack of spans instead of recursion,
// so a split that peels one point per level (a zigzag) cannot exhaust
// the stack on JavaScript. Spans are processed left to right; when a
// span needs no split its `first` is kept, and the input's last point
// closes the output.
fn dp(
  first first: LatLng,
  rest rest: List(LatLng),
  tolerance tolerance: Float,
) -> List(LatLng) {
  case list.reverse(rest) {
    [] -> [first]
    [last, ..middle_reversed] ->
      dp_loop(
        stack: [Span(first:, middle: list.reverse(middle_reversed), last:)],
        tolerance: tolerance,
        kept: [],
        end: last,
      )
  }
}

fn dp_loop(
  stack stack: List(Span),
  tolerance tolerance: Float,
  kept kept: List(LatLng),
  end end: LatLng,
) -> List(LatLng) {
  case stack {
    [] -> list.reverse([end, ..kept])
    [span, ..rest] ->
      case farthest(span: span) {
        Ok(#(distance, left, right)) if distance >. tolerance ->
          dp_loop(stack: [left, right, ..rest], tolerance:, kept:, end:)
        _ -> dp_loop(stack: rest, tolerance:, kept: [span.first, ..kept], end:)
      }
  }
}

// One pass over `span.middle` that finds the point farthest from the
// chord `first`-`last` (the earliest one on ties) and returns its
// distance with the two spans either side of it. The prefix before the
// candidate is the reversed accumulator at the moment it was found and
// the suffix is the remaining tail, so no second pass is needed to
// split. Returns `Error(Nil)` when the span has no middle points.
fn farthest(span span: Span) -> Result(#(Float, Span, Span), Nil) {
  case span.middle {
    [] -> Error(Nil)
    [head, ..tail] -> {
      let #(distance, before, pivot, after) =
        farthest_loop(
          points: tail,
          a: span.first,
          b: span.last,
          seen: [head],
          best: #(
            perpendicular_distance(p: head, a: span.first, b: span.last),
            [],
            head,
            tail,
          ),
        )
      Ok(#(
        distance,
        Span(first: span.first, middle: list.reverse(before), last: pivot),
        Span(first: pivot, middle: after, last: span.last),
      ))
    }
  }
}

fn farthest_loop(
  points points: List(LatLng),
  a a: LatLng,
  b b: LatLng,
  seen seen: List(LatLng),
  best best: #(Float, List(LatLng), LatLng, List(LatLng)),
) -> #(Float, List(LatLng), LatLng, List(LatLng)) {
  case points {
    [] -> best
    [head, ..tail] -> {
      let distance = perpendicular_distance(p: head, a: a, b: b)
      let best = case distance >. best.0 {
        True -> #(distance, seen, head, tail)
        False -> best
      }
      farthest_loop(points: tail, a: a, b: b, seen: [head, ..seen], best: best)
    }
  }
}

fn perpendicular_distance(p p: LatLng, a a: LatLng, b b: LatLng) -> Float {
  let x = latlng.lng(p)
  let y = latlng.lat(p)
  let x1 = latlng.lng(a)
  let y1 = latlng.lat(a)
  let x2 = latlng.lng(b)
  let y2 = latlng.lat(b)
  let dx = x2 -. x1
  let dy = y2 -. y1
  let length_squared = dx *. dx +. dy *. dy
  case length_squared == 0.0 {
    True -> {
      let edx = x -. x1
      let edy = y -. y1
      sqrt_nonneg(edx *. edx +. edy *. edy)
    }
    False -> {
      let cross = { x -. x1 } *. dy -. { y -. y1 } *. dx
      float.absolute_value(cross) /. sqrt_nonneg(length_squared)
    }
  }
}

// Callers pass sums of squares, so the input is non-negative and
// `float.square_root` cannot fail.
fn sqrt_nonneg(value: Float) -> Float {
  case float.square_root(float.max(value, 0.0)) {
    Ok(root) -> root
    Error(Nil) -> 0.0
  }
}
