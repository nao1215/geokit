import gleeunit/should

import geokit/bearing
import geokit/latlng

fn approx_equal(a: Float, b: Float, tolerance: Float) -> Bool {
  let delta = case a >. b {
    True -> a -. b
    False -> b -. a
  }
  delta <=. tolerance
}

// Wraps the difference into [0, 360) and tests whether the bearing
// is within `tolerance` of `target` modulo 360°.
fn bearing_approx(value: Float, target: Float, tolerance: Float) -> Bool {
  let raw_diff = value -. target
  let mod_diff = case raw_diff <. -180.0 {
    True -> raw_diff +. 360.0
    False ->
      case raw_diff >. 180.0 {
        True -> raw_diff -. 360.0
        False -> raw_diff
      }
  }
  let abs_diff = case mod_diff <. 0.0 {
    True -> 0.0 -. mod_diff
    False -> mod_diff
  }
  abs_diff <=. tolerance
}

// --- initial bearing ----------------------------------------------------

pub fn initial_due_north_test() -> Nil {
  let assert Ok(equator) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(north) = latlng.new(lat: 1.0, lng: 0.0)
  bearing.initial(from: equator, to: north)
  |> approx_equal(0.0, 0.001)
  |> should.be_true
}

pub fn initial_due_east_test() -> Nil {
  let assert Ok(equator) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(east) = latlng.new(lat: 0.0, lng: 1.0)
  bearing.initial(from: equator, to: east)
  |> approx_equal(90.0, 0.001)
  |> should.be_true
}

pub fn initial_due_south_test() -> Nil {
  let assert Ok(equator) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(south) = latlng.new(lat: -1.0, lng: 0.0)
  bearing.initial(from: equator, to: south)
  |> approx_equal(180.0, 0.001)
  |> should.be_true
}

pub fn initial_due_west_test() -> Nil {
  let assert Ok(equator) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(west) = latlng.new(lat: 0.0, lng: -1.0)
  bearing.initial(from: equator, to: west)
  |> approx_equal(270.0, 0.001)
  |> should.be_true
}

pub fn london_to_paris_initial_test() -> Nil {
  // Reference (chrisveness/geodesy): ~149°.
  let assert Ok(london) = latlng.new(lat: 51.5074, lng: -0.1278)
  let assert Ok(paris) = latlng.new(lat: 48.8566, lng: 2.3522)
  let b = bearing.initial(from: london, to: paris)
  bearing_approx(b, 149.0, 1.0)
  |> should.be_true
}

pub fn initial_is_in_range_test() -> Nil {
  let assert Ok(a) = latlng.new(lat: 12.34, lng: 56.78)
  let assert Ok(b) = latlng.new(lat: -23.45, lng: 67.89)
  let value = bearing.initial(from: a, to: b)
  { value >=. 0.0 && value <. 360.0 }
  |> should.be_true
}

// --- final bearing ------------------------------------------------------

pub fn final_along_meridian_equals_initial_test() -> Nil {
  // Travelling along a meridian, initial and final bearings agree.
  let assert Ok(a) = latlng.new(lat: 10.0, lng: 0.0)
  let assert Ok(b) = latlng.new(lat: 30.0, lng: 0.0)
  let init = bearing.initial(from: a, to: b)
  let fin = bearing.final(from: a, to: b)
  bearing_approx(init, fin, 0.001)
  |> should.be_true
}

pub fn final_long_route_differs_from_initial_test() -> Nil {
  // Long east-west route across the northern hemisphere has a final
  // bearing distinct from the initial one.
  let assert Ok(london) = latlng.new(lat: 51.5074, lng: -0.1278)
  let assert Ok(tokyo) = latlng.new(lat: 35.6812, lng: 139.7671)
  let init = bearing.initial(from: london, to: tokyo)
  let fin = bearing.final(from: london, to: tokyo)
  // The two should differ by more than 1°.
  let raw = fin -. init
  let abs_diff = case raw <. 0.0 {
    True -> 0.0 -. raw
    False -> raw
  }
  { abs_diff >. 1.0 }
  |> should.be_true
}
