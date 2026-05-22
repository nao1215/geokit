//// Regression coverage for issue #31: midpoint inputs (equator,
//// poles, prime/anti meridian) used to disagree with every other
//// geohash implementation because the encode loop used strict `>`
//// at the bisection midpoint instead of the canonical `>=`.

import geokit/geohash
import geokit/latlng
import gleeunit/should

pub fn midpoint_equator_test() -> Nil {
  let assert Ok(p) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(h) = geohash.encode(point: p, precision: 5)
  h |> should.equal("s0000")
}

pub fn midpoint_north_pole_prime_meridian_test() -> Nil {
  let assert Ok(p) = latlng.new(lat: 90.0, lng: 0.0)
  let assert Ok(h) = geohash.encode(point: p, precision: 5)
  h |> should.equal("upbpb")
}

pub fn midpoint_antimeridian_east_test() -> Nil {
  let assert Ok(p) = latlng.new(lat: 0.0, lng: 180.0)
  let assert Ok(h) = geohash.encode(point: p, precision: 5)
  h |> should.equal("xbpbp")
}

pub fn midpoint_antimeridian_west_test() -> Nil {
  // -180 is the same physical meridian as +180; the canonical
  // convention puts it on the boundary of cell "8".
  let assert Ok(p) = latlng.new(lat: 0.0, lng: -180.0)
  let assert Ok(h) = geohash.encode(point: p, precision: 5)
  h |> should.equal("80000")
}

pub fn midpoint_south_pole_prime_meridian_test() -> Nil {
  let assert Ok(p) = latlng.new(lat: -90.0, lng: 0.0)
  let assert Ok(h) = geohash.encode(point: p, precision: 5)
  h |> should.equal("h0000")
}

pub fn non_midpoint_regression_test() -> Nil {
  // Sanity check that non-midpoint inputs still agree with the
  // README's Tokyo example — the fix is supposed to be narrow.
  let assert Ok(p) = latlng.new(lat: 35.6812, lng: 139.7671)
  let assert Ok(h) = geohash.encode(point: p, precision: 8)
  h |> should.equal("xn76urx6")
}
