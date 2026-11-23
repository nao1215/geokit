//// RFC 7946 section 3.1.1 allows positions with more than three
//// numbers, and a feature id `1.0` decoded to `FloatId` on Erlang but
//// `IntId` on JavaScript.

import geokit
import geokit/geojson
import gleam/dynamic/decode
import gleam/json
import gleam/option.{Some}
import gleeunit/should

pub fn positions_with_extra_numbers_drop_them_test() {
  json.parse(
    "{\"type\":\"Point\",\"coordinates\":[139.5,35.5,10,20]}",
    geojson.geometry_decoder(),
  )
  |> should.equal(
    Ok(geokit.Point(geokit.wrap_lat_lng(latitude: 35.5, longitude: 139.5))),
  )
}

pub fn a_single_number_is_still_not_a_position_test() {
  json.parse(
    "{\"type\":\"Point\",\"coordinates\":[139.5]}",
    geojson.geometry_decoder(),
  )
  |> should.be_error
}

fn id(text: String) {
  json.parse(
    "{\"type\":\"Feature\",\"geometry\":null,\"properties\":null,\"id\":"
      <> text
      <> "}",
    geojson.feature_decoder(properties: decode.dynamic),
  )
  |> should.be_ok
}

pub fn integral_number_ids_decode_to_int_id_on_both_targets_test() {
  id("1.0").id |> should.equal(Some(geojson.IntId(1)))
  id("1").id |> should.equal(Some(geojson.IntId(1)))
  id("-3.0e2").id |> should.equal(Some(geojson.IntId(-300)))
}

pub fn fractional_number_ids_stay_float_id_test() {
  id("1.5").id |> should.equal(Some(geojson.FloatId(1.5)))
  id("-0.25").id |> should.equal(Some(geojson.FloatId(-0.25)))
}

pub fn huge_integral_ids_are_int_id_on_both_targets_test() {
  let assert Some(geojson.IntId(_)) = id("1.0e300").id
  let assert Some(geojson.IntId(_)) = id("9007199254740993").id
}

pub fn huge_extra_numbers_in_a_position_are_dropped_test() {
  json.parse(
    "{\"type\":\"Point\",\"coordinates\":[139.5,35.5,10,1700000000000]}",
    geojson.geometry_decoder(),
  )
  |> should.equal(
    Ok(geokit.Point(geokit.wrap_lat_lng(latitude: 35.5, longitude: 139.5))),
  )
}
