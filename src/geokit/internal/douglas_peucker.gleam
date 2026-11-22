//// Douglas-Peucker simplification on the plane. A point is `#(x, y)`,
//// longitude then latitude in degrees.

import gleam/bool
import gleam/float
import gleam/list

pub type Point =
  #(Float, Float)

/// Simplifies an open line. `tolerance` is non-negative; a point is kept
/// when it is farther than `tolerance` from the chord of its span.
pub fn line(points: List(Point), tolerance tolerance: Float) -> List(Point) {
  case points {
    [] | [_] | [_, _] -> points
    [first, ..rest] -> dp(first: first, rest: rest, tolerance: tolerance)
  }
}

/// Simplifies a polygon ring, keeping a closed ring closed and valid.
pub fn ring(points: List(Point), tolerance tolerance: Float) -> List(Point) {
  // A closed ring starts and ends at the same vertex, so Douglas-Peucker
  // over the whole ring would measure every point against a zero-length
  // chord and could keep only the closing pair. Split at the vertex
  // farthest from the start instead, simplify both halves and rejoin. A
  // result with fewer than four positions is not a valid ring, so it is
  // replaced by the smallest valid ring (see `smallest_ring`); a ring of
  // four positions or fewer is already that small and is kept. Unclosed
  // rings are simplified as a line.
  case points, list.last(points) {
    [first, second, third, fourth, ..more], Ok(last) if first == last ->
      closed_ring(
        ring: points,
        first: first,
        rest: [second, third, fourth, ..more],
        tolerance: tolerance,
      )
    _, _ -> line(points, tolerance: tolerance)
  }
}

fn closed_ring(
  ring ring: List(Point),
  first first: Point,
  rest rest: List(Point),
  tolerance tolerance: Float,
) -> List(Point) {
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
        True ->
          smallest_ring(
            ring: ring,
            first: first,
            pivot: pivot,
            before: before,
            after: after,
          )
        False -> joined
      }
    }
  }
}

// The fallback when both halves collapse: the start, the pivot and the
// remaining vertex farthest from the chord between them, in ring order,
// closed. Keeping only four positions means a larger tolerance never
// yields a larger ring. `before` is reversed and `after` ends with the
// closing vertex, which is not a candidate.
fn smallest_ring(
  ring ring: List(#(Float, Float)),
  first first: #(Float, Float),
  pivot pivot: #(Float, Float),
  before before: List(#(Float, Float)),
  after after: List(#(Float, Float)),
) -> List(#(Float, Float)) {
  use <- bool.guard(when: list.length(ring) <= 4, return: ring)
  let after_open = list.take(after, list.length(after) - 1)
  let best_before =
    farthest_from_chord(points: list.reverse(before), a: first, b: pivot)
  let best_after = farthest_from_chord(points: after_open, a: first, b: pivot)
  case best_before, best_after {
    Ok(#(d_before, v)), Ok(#(d_after, _)) if d_before >=. d_after -> [
      first,
      v,
      pivot,
      first,
    ]
    _, Ok(#(_, v)) -> [first, pivot, v, first]
    Ok(#(_, v)), Error(Nil) -> [first, v, pivot, first]
    Error(Nil), Error(Nil) -> ring
  }
}

// The point of `points` farthest from the line `a`-`b` with its
// distance, the earliest one on ties.
fn farthest_from_chord(
  points points: List(#(Float, Float)),
  a a: #(Float, Float),
  b b: #(Float, Float),
) -> Result(#(Float, #(Float, Float)), Nil) {
  list.fold(points, Error(Nil), fn(best, p) {
    let distance = perpendicular_distance(p: p, a: a, b: b)
    case best {
      Ok(#(best_distance, _)) if best_distance >=. distance -> best
      _ -> Ok(#(distance, p))
    }
  })
}

// The point of `points` farthest from `origin` (the earliest one on
// ties), with the points before it (reversed) and after it.
fn farthest_from(
  origin origin: Point,
  points points: List(Point),
) -> Result(#(List(Point), Point, List(Point)), Nil) {
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

// A span of the input between two kept points: `first`, the points in
// between (in input order) and `last`.
type Span {
  Span(first: Point, middle: List(Point), last: Point)
}

// Douglas-Peucker with an explicit stack of spans instead of recursion,
// so a split that peels one point per level (a zigzag) cannot exhaust
// the stack on JavaScript. Spans are processed left to right; when a
// span needs no split its `first` is kept, and the input's last point
// closes the output.
fn dp(
  first first: Point,
  rest rest: List(Point),
  tolerance tolerance: Float,
) -> List(Point) {
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
  kept kept: List(Point),
  end end: Point,
) -> List(Point) {
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
  points points: List(Point),
  a a: Point,
  b b: Point,
  seen seen: List(Point),
  best best: #(Float, List(Point), Point, List(Point)),
) -> #(Float, List(Point), Point, List(Point)) {
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

fn perpendicular_distance(p p: Point, a a: Point, b b: Point) -> Float {
  let #(x, y) = p
  let #(x1, y1) = a
  let #(x2, y2) = b
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
