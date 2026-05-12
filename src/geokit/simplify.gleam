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
import gleam/list

import geokit/latlng.{type LatLng}

/// Errors returned by [`line_string`](#line_string).
pub type SimplifyError {
  /// `tolerance` was negative.
  NegativeTolerance(tolerance: Float)
}

/// Simplify a sequence of points using Douglas-Peucker.
/// `tolerance` is in degrees. A tolerance of `0.0` keeps every
/// point; larger values keep fewer points.
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
    _ -> Ok(dp(points: points, tolerance: tolerance))
  }
}

fn dp(points points: List(LatLng), tolerance tolerance: Float) -> List(LatLng) {
  let length = list.length(points)
  case length <= 2 {
    True -> points
    False -> {
      let first = first_or_default(points)
      let last = last_or_default(points, first)
      let middle = middle_of(points)
      let #(max_dist, max_index) =
        max_perp_distance(
          middle: middle,
          a: first,
          b: last,
          index: 1,
          best_dist: 0.0,
          best_index: 0,
        )
      case max_dist >. tolerance {
        True -> {
          let left_part = list.take(points, max_index + 1)
          let right_part = list.drop(points, max_index)
          let left = dp(points: left_part, tolerance: tolerance)
          let right = dp(points: right_part, tolerance: tolerance)
          merge_skipping_duplicate_pivot(left, right)
        }
        False -> [first, last]
      }
    }
  }
}

fn merge_skipping_duplicate_pivot(
  left: List(LatLng),
  right: List(LatLng),
) -> List(LatLng) {
  // The last element of `left` and the first element of `right` are
  // the same pivot point; concatenate but drop the duplicate.
  case right {
    [] -> left
    [_, ..tail] -> list.append(left, tail)
  }
}

fn max_perp_distance(
  middle middle: List(LatLng),
  a a: LatLng,
  b b: LatLng,
  index index: Int,
  best_dist best_dist: Float,
  best_index best_index: Int,
) -> #(Float, Int) {
  case middle {
    [] -> #(best_dist, best_index)
    [head, ..tail] -> {
      let d = perpendicular_distance(p: head, a: a, b: b)
      case d >. best_dist {
        True ->
          max_perp_distance(
            middle: tail,
            a: a,
            b: b,
            index: index + 1,
            best_dist: d,
            best_index: index,
          )
        False ->
          max_perp_distance(
            middle: tail,
            a: a,
            b: b,
            index: index + 1,
            best_dist: best_dist,
            best_index: best_index,
          )
      }
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
      let abs_cross = case cross <. 0.0 {
        True -> 0.0 -. cross
        False -> cross
      }
      abs_cross /. sqrt_nonneg(length_squared)
    }
  }
}

fn sqrt_nonneg(value: Float) -> Float {
  use <- bool.guard(when: value <=. 0.0, return: 0.0)
  newton_sqrt(value: value, guess: value, iterations: 32)
}

fn newton_sqrt(
  value value: Float,
  guess guess: Float,
  iterations iterations: Int,
) -> Float {
  use <- bool.guard(when: iterations <= 0 || guess == 0.0, return: guess)
  newton_sqrt(
    value: value,
    guess: { guess +. value /. guess } /. 2.0,
    iterations: iterations - 1,
  )
}

// --- list helpers --------------------------------------------------------

fn first_or_default(points: List(LatLng)) -> LatLng {
  case points {
    [] -> latlng.wrap(lat: 0.0, lng: 0.0)
    [head, ..] -> head
  }
}

fn last_or_default(points: List(LatLng), fallback: LatLng) -> LatLng {
  case points {
    [] -> fallback
    [single] -> single
    [_, ..tail] -> last_or_default(tail, fallback)
  }
}

fn middle_of(points: List(LatLng)) -> List(LatLng) {
  case points {
    [] -> []
    [_] -> []
    [_, ..tail] -> drop_last(tail)
  }
}

fn drop_last(points: List(LatLng)) -> List(LatLng) {
  case points {
    [] -> []
    [_] -> []
    [head, ..tail] -> [head, ..drop_last(tail)]
  }
}
