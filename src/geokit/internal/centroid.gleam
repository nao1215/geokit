//// Planar centroids. A point is `#(x, y)`, longitude then latitude in
//// degrees.

import gleam/bool
import gleam/int
import gleam/list
import gleam/result

/// The arithmetic mean of `points`, or `Error(Nil)` when there are none.
pub fn mean(points: List(#(Float, Float))) -> Result(#(Float, Float), Nil) {
  use <- bool.guard(when: points == [], return: Error(Nil))
  let #(sum_x, sum_y, count) =
    list.fold(points, #(0.0, 0.0, 0), fn(sums, point) {
      let #(sum_x, sum_y, count) = sums
      #(sum_x +. point.0, sum_y +. point.1, count + 1)
    })
  let count = int.to_float(count)
  Ok(#(sum_x /. count, sum_y /. count))
}

// First moments and twice the area of a polygon, accumulated over its
// rings with the shoelace formula. The centroid is
// `#(sum_x, sum_y) / (3 * area_twice)`; sums of several polygons give
// the area-weighted centroid of the whole.
type Moments {
  Moments(sum_x: Float, sum_y: Float, area_twice: Float)
}

/// The area centroid of a polygon given as rings (exterior first, then
/// holes). Holes subtract. A polygon with zero area falls back to the
/// vertex mean of its exterior. `Error(Nil)` when the exterior is
/// missing or empty.
pub fn polygon(
  rings: List(List(#(Float, Float))),
) -> Result(#(Float, Float), Nil) {
  use exterior <- result.try(exterior_ring(rings))
  from_moments(polygon_moments(rings), fallback: fn() {
    mean(open_ring(exterior))
  })
}

// A closed ring repeats its first vertex at the end; drop the repeat so
// the zero-area fallback weighs every distinct vertex once.
fn open_ring(ring: List(#(Float, Float))) -> List(#(Float, Float)) {
  case ring, list.last(ring) {
    [first, _, ..], Ok(last) if first == last ->
      list.take(ring, list.length(ring) - 1)
    _, _ -> ring
  }
}

/// The area-weighted centroid of several polygons. Polygons without an
/// exterior ring are skipped. When the total area is zero, the result is
/// the mean of the polygons' own centroids.
pub fn polygons(
  polygons: List(List(List(#(Float, Float)))),
) -> Result(#(Float, Float), Nil) {
  let polygons =
    list.filter(polygons, fn(rings) { result.is_ok(exterior_ring(rings)) })
  use <- bool.guard(when: polygons == [], return: Error(Nil))
  let total =
    list.fold(polygons, Moments(0.0, 0.0, 0.0), fn(total, rings) {
      add_moments(total, polygon_moments(rings))
    })
  from_moments(total, fallback: fn() {
    list.filter_map(polygons, polygon)
    |> mean
  })
}

fn exterior_ring(
  rings: List(List(#(Float, Float))),
) -> Result(List(#(Float, Float)), Nil) {
  case rings {
    [[_, ..] as exterior, ..] -> Ok(exterior)
    _ -> Error(Nil)
  }
}

// Whatever the winding order, the exterior counts with positive area
// and every hole with negative area, as in GEOS / Shapely.
fn polygon_moments(rings: List(List(#(Float, Float)))) -> Moments {
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
  moments: Moments,
  fallback fallback: fn() -> Result(#(Float, Float), Nil),
) -> Result(#(Float, Float), Nil) {
  let area_twice = moments.area_twice
  // Numeric test so a -0.0 total also counts as zero on Erlang.
  use <- bool.lazy_guard(
    when: area_twice >=. 0.0 && area_twice <=. 0.0,
    return: fallback,
  )
  let factor = 1.0 /. { 3.0 *. area_twice }
  Ok(#(moments.sum_x *. factor, moments.sum_y *. factor))
}

fn ring_moments(ring: List(#(Float, Float))) -> Moments {
  ring_sums(ensure_closed(ring), acc: Moments(0.0, 0.0, 0.0))
}

fn ring_sums(points: List(#(Float, Float)), acc acc: Moments) -> Moments {
  case points {
    [a, b, ..rest] -> {
      let #(x0, y0) = a
      let #(x1, y1) = b
      let cross = x0 *. y1 -. x1 *. y0
      ring_sums(
        [b, ..rest],
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

fn ensure_closed(points: List(#(Float, Float))) -> List(#(Float, Float)) {
  case points, list.last(points) {
    [first, ..], Ok(last) if first != last -> list.append(points, [first])
    _, _ -> points
  }
}
