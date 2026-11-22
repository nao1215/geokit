import gleeunit/should

import geokit/latlng

// --- Constructors --------------------------------------------------------

pub fn new_within_range_test() -> Nil {
  let assert Ok(tokyo) = latlng.new(lat: 35.6812, lng: 139.7671)
  latlng.lat(tokyo)
  |> should.equal(35.6812)
  latlng.lng(tokyo)
  |> should.equal(139.7671)
}

pub fn new_at_bounds_test() -> Nil {
  let assert Ok(north_pole) = latlng.new(lat: 90.0, lng: 0.0)
  latlng.lat(north_pole)
  |> should.equal(90.0)
  let assert Ok(south_pole) = latlng.new(lat: -90.0, lng: 0.0)
  latlng.lat(south_pole)
  |> should.equal(-90.0)
  let assert Ok(east) = latlng.new(lat: 0.0, lng: 180.0)
  latlng.lng(east)
  |> should.equal(180.0)
  let assert Ok(west) = latlng.new(lat: 0.0, lng: -180.0)
  latlng.lng(west)
  |> should.equal(-180.0)
}

// Issue #19: new_or_panic is the literal-friendly companion to new
// for curated coordinate lists where wrapping every value in
// `let assert Ok(...)` adds noise without adding safety.
pub fn new_or_panic_builds_valid_latlng_test() -> Nil {
  let tokyo = latlng.new_or_panic(lat: 35.6812, lng: 139.7671)
  latlng.lat(tokyo)
  |> should.equal(35.6812)
  latlng.lng(tokyo)
  |> should.equal(139.7671)
}

pub fn new_or_panic_accepts_pole_and_antimeridian_test() -> Nil {
  let north = latlng.new_or_panic(lat: 90.0, lng: 0.0)
  latlng.lat(north)
  |> should.equal(90.0)
  let dateline_east = latlng.new_or_panic(lat: 0.0, lng: 180.0)
  latlng.lng(dateline_east)
  |> should.equal(180.0)
  let dateline_west = latlng.new_or_panic(lat: 0.0, lng: -180.0)
  latlng.lng(dateline_west)
  |> should.equal(-180.0)
}

pub fn new_lat_out_of_range_test() -> Nil {
  case latlng.new(lat: 90.5, lng: 0.0) {
    Error(latlng.LatOutOfRange(lat: 90.5)) -> Nil
    _ -> should.be_true(False)
  }
  case latlng.new(lat: -90.5, lng: 0.0) {
    Error(latlng.LatOutOfRange(lat: -90.5)) -> Nil
    _ -> should.be_true(False)
  }
}

pub fn new_lng_out_of_range_test() -> Nil {
  case latlng.new(lat: 0.0, lng: 180.5) {
    Error(latlng.LngOutOfRange(lng: 180.5)) -> Nil
    _ -> should.be_true(False)
  }
  case latlng.new(lat: 0.0, lng: -180.5) {
    Error(latlng.LngOutOfRange(lng: -180.5)) -> Nil
    _ -> should.be_true(False)
  }
}

// --- Wrap ----------------------------------------------------------------

pub fn wrap_at_antimeridian_test() -> Nil {
  let point = latlng.wrap(lat: 0.0, lng: 181.0)
  latlng.lng(point)
  |> should.equal(-179.0)
}

pub fn wrap_negative_overflow_test() -> Nil {
  let point = latlng.wrap(lat: 0.0, lng: -181.0)
  latlng.lng(point)
  |> should.equal(179.0)
}

pub fn wrap_lat_clamped_test() -> Nil {
  let point = latlng.wrap(lat: 95.0, lng: 0.0)
  latlng.lat(point)
  |> should.equal(90.0)
  let southern = latlng.wrap(lat: -95.0, lng: 0.0)
  latlng.lat(southern)
  |> should.equal(-90.0)
}

// --- Equality ------------------------------------------------------------

pub fn equal_test() -> Nil {
  let assert Ok(a) = latlng.new(lat: 35.6812, lng: 139.7671)
  let assert Ok(b) = latlng.new(lat: 35.6812, lng: 139.7671)
  let assert Ok(c) = latlng.new(lat: 35.6813, lng: 139.7671)
  latlng.equal(a, b)
  |> should.be_true
  latlng.equal(a, c)
  |> should.be_false
}

// --- equal ---------------------------------------------------------------

pub fn equal_treats_signed_zeros_as_equal_test() -> Nil {
  // -0.0 and 0.0 are the same coordinate. Erlang's exact `==` on floats
  // tells them apart; JavaScript does not.
  latlng.equal(
    a: latlng.new_or_panic(lat: 0.0, lng: -0.0),
    b: latlng.new_or_panic(lat: -0.0, lng: 0.0),
  )
  |> should.be_true
}

pub fn equal_distinguishes_different_values_test() -> Nil {
  latlng.equal(
    a: latlng.new_or_panic(lat: 0.0, lng: 180.0),
    b: latlng.new_or_panic(lat: 0.0, lng: -180.0),
  )
  |> should.be_false
  latlng.equal(
    a: latlng.new_or_panic(lat: 1.0, lng: 2.0),
    b: latlng.new_or_panic(lat: 1.0, lng: 2.0),
  )
  |> should.be_true
}

// --- non-finite input (JavaScript only) ---------------------------------
// Erlang floats cannot hold Infinity or NaN: the arithmetic that would
// produce them raises instead.

@target(javascript)
fn infinity() -> Float {
  1.0e308 *. 10.0
}

@target(javascript)
pub fn new_rejects_nan_test() -> Nil {
  let nan = infinity() -. infinity()
  let assert Error(_) = latlng.new(lat: nan, lng: 0.0)
  let assert Error(_) = latlng.new(lat: 0.0, lng: nan)
  let assert Error(_) = latlng.new(lat: infinity(), lng: 0.0)
  Nil
}

@target(javascript)
pub fn wrap_non_finite_test() -> Nil {
  let nan = infinity() -. infinity()
  let p = latlng.wrap(lat: infinity(), lng: infinity())
  #(latlng.lat(p), latlng.lng(p))
  |> should.equal(#(90.0, 0.0))
  let p = latlng.wrap(lat: 0.0 -. infinity(), lng: nan)
  #(latlng.lat(p), latlng.lng(p))
  |> should.equal(#(-90.0, 0.0))
  let p = latlng.wrap(lat: nan, lng: 10.0)
  #(latlng.lat(p), latlng.lng(p))
  |> should.equal(#(0.0, 10.0))
}
