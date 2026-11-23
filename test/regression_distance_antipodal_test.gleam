//// The haversine form loses precision near antipodal points: one
//// rounding step in its `h` term moved the result by up to 18 cm, and
//// Erlang and JavaScript disagreed by 13 cm on the same input. Expected
//// values are GeographicLib geodesics on a sphere of the same radius.

import geokit
import gleam/float
import gleeunit/should

fn distance(a: #(Float, Float), b: #(Float, Float)) -> Float {
  geokit.distance(
    from: geokit.wrap_lat_lng(latitude: a.0, longitude: a.1),
    to: geokit.wrap_lat_lng(latitude: b.0, longitude: b.1),
  )
}

fn assert_within_a_millimetre(actual: Float, expected: Float) -> Nil {
  should.be_true(float.absolute_value(actual -. expected) <. 0.001)
}

pub fn exactly_antipodal_points_test() {
  distance(#(16.4076183, -65.7253324), #(-16.4076183, 114.2746676))
  |> assert_within_a_millimetre(20_015_114.442035925)
}

pub fn nearly_antipodal_points_test() {
  distance(#(26.4881098, -98.3025554), #(-26.4880998, 81.6974446))
  |> assert_within_a_millimetre(20_015_113.33008512)
  distance(#(-89.9999999, 94.4208297), #(90.0, -85.5791703))
  |> assert_within_a_millimetre(20_015_114.430916414)
  distance(#(0.0, 0.0), #(0.0, 179.9999))
  |> assert_within_a_millimetre(20_015_103.3225279)
}

fn assert_relative(actual: Float, expected: Float) -> Nil {
  should.be_true(
    float.absolute_value(actual -. expected) <=. expected *. 0.000_000_001,
  )
}

pub fn short_and_medium_distances_keep_relative_precision_test() {
  distance(#(35.6812, 139.7671), #(34.6937, 135.5023))
  |> assert_relative(402_784.7393766612)
  distance(#(10.0, 20.0), #(10.00001, 20.00001))
  |> assert_relative(1.560636431460593)
  distance(#(0.0, 0.0), #(0.000000001, 0.000000001))
  |> assert_relative(0.00015725359049404105)
}
