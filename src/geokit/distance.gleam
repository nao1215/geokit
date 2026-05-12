//// Great-circle distance between two `LatLng` points.
////
//// The haversine formula is used; see
//// <https://en.wikipedia.org/wiki/Haversine_formula>. Distances are
//// reported in metres using the WGS84 mean Earth radius
//// (6_371_008.8 m). The error against a Vincenty ellipsoidal
//// distance is bounded by 0.5 % for any two points on Earth, which
//// matches every consumer-grade mapping API.

import gleam/bool
import gleam/float
import gleam_community/maths

import geokit/latlng.{type LatLng}

/// Mean Earth radius (WGS84), in metres.
const earth_radius_m: Float = 6_371_008.8

/// Great-circle distance between `a` and `b`, in metres.
///
/// ```gleam
/// import geokit/distance
/// import geokit/latlng
///
/// let assert Ok(tokyo) = latlng.new(lat: 35.6812, lng: 139.7671)
/// let assert Ok(osaka) = latlng.new(lat: 34.6937, lng: 135.5023)
/// distance.haversine(a: tokyo, b: osaka)
/// // ~= 396_900.0 (≈ 397 km)
/// ```
pub fn haversine(a a: LatLng, b b: LatLng) -> Float {
  let lat_a = maths.degrees_to_radians(latlng.lat(a))
  let lat_b = maths.degrees_to_radians(latlng.lat(b))
  let delta_lat = maths.degrees_to_radians(latlng.lat(b) -. latlng.lat(a))
  let delta_lng = maths.degrees_to_radians(latlng.lng(b) -. latlng.lng(a))
  let half_lat = delta_lat /. 2.0
  let half_lng = delta_lng /. 2.0
  let sin_half_lat = maths.sin(half_lat)
  let sin_half_lng = maths.sin(half_lng)
  let h =
    sin_half_lat
    *. sin_half_lat
    +. maths.cos(lat_a)
    *. maths.cos(lat_b)
    *. sin_half_lng
    *. sin_half_lng
  let h_clamped = float.clamp(h, min: 0.0, max: 1.0)
  let root_h = sqrt_nonneg(h_clamped)
  let root_one_minus_h = sqrt_nonneg(1.0 -. h_clamped)
  let c = 2.0 *. maths.atan2(root_h, root_one_minus_h)
  earth_radius_m *. c
}

/// Great-circle distance between `a` and `b`, in kilometres.
/// Convenience wrapper around [`haversine`](#haversine).
pub fn haversine_km(a a: LatLng, b b: LatLng) -> Float {
  haversine(a: a, b: b) /. 1000.0
}

/// Square root of a non-negative input via Newton iteration. Caller
/// must ensure the argument is `>= 0`; on a negative input the
/// function returns `0.0`.
fn sqrt_nonneg(x: Float) -> Float {
  use <- bool.guard(when: x <=. 0.0, return: 0.0)
  newton_sqrt(value: x, guess: x, iterations: 32)
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
