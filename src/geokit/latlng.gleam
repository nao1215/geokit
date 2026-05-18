//// Opaque `LatLng` (geographic coordinate) shared by every module
//// in `geokit`.
////
//// Latitudes are in degrees, in the range [-90, 90], with positive
//// values north of the equator. Longitudes are in degrees, in the
//// range [-180, 180], with positive values east of the prime
//// meridian. Out-of-range inputs to [`new`](#new) return a typed
//// error; use [`wrap`](#wrap) when your source data may be
//// denormalised (for example, sensor output that crosses the
//// antimeridian).

import gleam/bool
import gleam/float

/// Geographic coordinate. `pub opaque`; build through [`new`](#new)
/// or [`wrap`](#wrap) and inspect through [`lat`](#lat) and
/// [`lng`](#lng).
pub opaque type LatLng {
  LatLng(lat: Float, lng: Float)
}

/// Errors returned by [`new`](#new).
pub type LatLngError {
  /// Latitude was outside `[-90, 90]`.
  LatOutOfRange(lat: Float)
  /// Longitude was outside `[-180, 180]`.
  LngOutOfRange(lng: Float)
}

// --- Constructors --------------------------------------------------------

/// Build a `LatLng` from latitude and longitude in degrees.
///
/// ```gleam
/// import geokit/latlng
///
/// let assert Ok(tokyo) = latlng.new(lat: 35.6812, lng: 139.7671)
/// ```
pub fn new(lat lat: Float, lng lng: Float) -> Result(LatLng, LatLngError) {
  use <- bool.guard(
    when: lat <. -90.0 || lat >. 90.0,
    return: Error(LatOutOfRange(lat: lat)),
  )
  use <- bool.guard(
    when: lng <. -180.0 || lng >. 180.0,
    return: Error(LngOutOfRange(lng: lng)),
  )
  Ok(LatLng(lat: lat, lng: lng))
}

/// Build a `LatLng` from literal coordinates, panicking on
/// out-of-range input. The companion to [`new`](#new) for
/// compile-time-known coordinates (curated city lists, landmark
/// fixtures, test data, hand-coded routes) where wrapping every
/// call site in `let assert Ok(...)` adds noise without adding
/// safety. Out-of-range inputs are programmer errors at literal
/// sites — they cannot be data-driven — so a panic carries the
/// offending value back through the stack rather than forcing the
/// caller to thread `Result` through the constant.
///
/// ```gleam
/// import geokit/latlng
///
/// pub fn cities() -> List(#(String, latlng.LatLng)) {
///   [
///     #("Tokyo", latlng.new_or_panic(lat: 35.6812, lng: 139.7671)),
///     #("Osaka", latlng.new_or_panic(lat: 34.6937, lng: 135.5023)),
///     #("Kyoto", latlng.new_or_panic(lat: 35.0116, lng: 135.7681)),
///   ]
/// }
/// ```
///
/// For runtime input (user-typed coordinates, parsed-from-file,
/// network-supplied values) use [`new`](#new) and handle the
/// `LatLngError` properly.
pub fn new_or_panic(lat lat: Float, lng lng: Float) -> LatLng {
  case new(lat: lat, lng: lng) {
    Ok(p) -> p
    Error(LatOutOfRange(lat: bad)) ->
      panic as {
        "latlng.new_or_panic: latitude out of [-90, 90]: "
        <> float.to_string(bad)
      }
    Error(LngOutOfRange(lng: bad)) ->
      panic as {
        "latlng.new_or_panic: longitude out of [-180, 180]: "
        <> float.to_string(bad)
      }
  }
}

/// Build a `LatLng`, normalising longitude into `[-180, 180]` and
/// clamping latitude into `[-90, 90]`. Use this when the source data
/// may be denormalised (sensor output crossing the antimeridian,
/// great-circle calculations producing 181°, ...).
///
/// ```gleam
/// import geokit/latlng
///
/// let p = latlng.wrap(lat: 91.0, lng: 181.0)
/// // p has lat = 90.0, lng = -179.0
/// ```
pub fn wrap(lat lat: Float, lng lng: Float) -> LatLng {
  let lat_clamped = float.clamp(lat, min: -90.0, max: 90.0)
  let lng_wrapped = wrap_longitude(lng)
  LatLng(lat: lat_clamped, lng: lng_wrapped)
}

fn wrap_longitude(lng: Float) -> Float {
  // Short-circuit for values already in `[-180, 180]` so the common
  // case is exact (no floating-point rounding). For out-of-range
  // values use floor-based reduction so the operation is O(1) even
  // at the antimeridian boundary; an iterative add-/subtract-360
  // form can ping-pong on floating-point cancellation.
  use <- bool.guard(when: lng >=. -180.0 && lng <=. 180.0, return: lng)
  let shifted = lng +. 180.0
  let wrapped = shifted -. 360.0 *. float.floor(shifted /. 360.0)
  let result = wrapped -. 180.0
  use <- bool.guard(when: result >. 180.0, return: 180.0)
  use <- bool.guard(when: result <. -180.0, return: -180.0)
  result
}

// --- Accessors -----------------------------------------------------------

/// Latitude in degrees.
pub fn lat(p p: LatLng) -> Float {
  p.lat
}

/// Longitude in degrees.
pub fn lng(p p: LatLng) -> Float {
  p.lng
}

// --- Equality / comparison ----------------------------------------------

/// Value equality. Two `LatLng` values are equal iff their `lat` and
/// `lng` components compare equal.
pub fn equal(a a: LatLng, b b: LatLng) -> Bool {
  a.lat == b.lat && a.lng == b.lng
}
