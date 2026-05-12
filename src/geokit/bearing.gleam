//// Initial and final compass bearing between two `LatLng` points.
////
//// Bearings are reported in degrees clockwise from true north, in
//// `[0, 360)`. The initial bearing is the direction of travel when
//// departing `a` along the great-circle route to `b`; the final
//// bearing is the direction of arrival at `b`. The two differ along
//// any route except along a meridian or the equator (where they are
//// equal).
////
//// Formula: <https://www.movable-type.co.uk/scripts/latlong.html>.

import gleam/bool
import gleam/float
import gleam_community/maths

import geokit/latlng.{type LatLng}

/// Initial bearing (forward azimuth) from `a` to `b`, in degrees in
/// `[0, 360)`.
///
/// ```gleam
/// import geokit/bearing
/// import geokit/latlng
///
/// let assert Ok(tokyo) = latlng.new(lat: 35.6812, lng: 139.7671)
/// let assert Ok(osaka) = latlng.new(lat: 34.6937, lng: 135.5023)
/// bearing.initial(from: tokyo, to: osaka)
/// // ~= 254.0
/// ```
pub fn initial(from from: LatLng, to to: LatLng) -> Float {
  let phi_1 = maths.degrees_to_radians(latlng.lat(from))
  let phi_2 = maths.degrees_to_radians(latlng.lat(to))
  let lambda_1 = maths.degrees_to_radians(latlng.lng(from))
  let lambda_2 = maths.degrees_to_radians(latlng.lng(to))
  let delta_lambda = lambda_2 -. lambda_1
  let y = maths.sin(delta_lambda) *. maths.cos(phi_2)
  let x =
    maths.cos(phi_1)
    *. maths.sin(phi_2)
    -. maths.sin(phi_1)
    *. maths.cos(phi_2)
    *. maths.cos(delta_lambda)
  let theta = maths.atan2(y, x)
  normalise_degrees(maths.radians_to_degrees(theta))
}

/// Final bearing when arriving at `to` along the great-circle route
/// from `from`, in degrees in `[0, 360)`. Computed as the reverse of
/// `initial(from: to, to: from)` plus 180°.
pub fn final(from from: LatLng, to to: LatLng) -> Float {
  let reverse = initial(from: to, to: from)
  normalise_degrees(reverse +. 180.0)
}

fn normalise_degrees(value: Float) -> Float {
  // `value mod 360`, with the result clamped to `[0, 360)`. Computed
  // via floor to avoid the iterative add-/subtract-360 loop, which
  // can fail to terminate at the floating-point cancellation
  // boundary near zero or 360.
  let scaled = value /. 360.0
  let result = value -. 360.0 *. float.floor(scaled)
  use <- bool.guard(when: result <. 0.0, return: 0.0)
  use <- bool.guard(when: result >=. 360.0, return: 0.0)
  result
}
