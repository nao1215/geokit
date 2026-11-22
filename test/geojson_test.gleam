import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

import geokit
import geokit/geojson

// --- helpers -------------------------------------------------------------

fn p(lat: Float, lng: Float) -> geokit.LatLng {
  let assert Ok(point) = geokit.lat_lng(latitude: lat, longitude: lng)
  point
}

// Round-trip a Geometry through encode + decode. Used by the encode
// tests so they stay target-portable: the JavaScript runtime renders
// whole-number floats as `0` while Erlang renders them as `0.0`, so a
// byte-exact assertion on the encoded string would diverge between
// targets. A round-trip is the contract that actually matters.
fn round_trip(g: geokit.Geometry) -> geokit.Geometry {
  let encoded = encode_geometry(g)
  let assert Ok(decoded) = parse_geometry(encoded)
  decoded
}

fn encode_geometry(geometry: geokit.Geometry) -> String {
  geojson.geometry_to_json(geometry) |> json.to_string
}

fn parse_geometry(input: String) -> Result(geokit.Geometry, json.DecodeError) {
  json.parse(input, geojson.geometry_decoder())
}

// The first decode error of a failed parse.
fn first_error(result: Result(a, json.DecodeError)) -> decode.DecodeError {
  let assert Error(json.UnableToDecode([error, ..])) = result
  error
}

fn expected(result: Result(a, json.DecodeError)) -> String {
  first_error(result).expected
}

// --- encode: shape sanity via round-trip --------------------------------

pub fn encode_point_round_trip_test() -> Nil {
  let original = geokit.Point(p(35.6812, 139.7671))
  round_trip(original) |> should.equal(original)
}

pub fn encode_line_string_round_trip_test() -> Nil {
  let original = geokit.LineString([p(35.6812, 139.7671), p(34.6937, 135.5023)])
  round_trip(original) |> should.equal(original)
}

pub fn encode_polygon_round_trip_test() -> Nil {
  let ring = [
    p(35.6812, 139.7671),
    p(35.6812, 139.7672),
    p(35.6813, 139.7672),
    p(35.6812, 139.7671),
  ]
  let original = geokit.Polygon([ring])
  round_trip(original) |> should.equal(original)
}

pub fn encode_multi_polygon_round_trip_test() -> Nil {
  let ring_a = [
    p(35.6812, 139.7671),
    p(35.6812, 139.7672),
    p(35.6813, 139.7672),
    p(35.6812, 139.7671),
  ]
  let ring_b = [
    p(34.6937, 135.5023),
    p(34.6937, 135.5024),
    p(34.6938, 135.5024),
    p(34.6937, 135.5023),
  ]
  let original = geokit.MultiPolygon([[ring_a], [ring_b]])
  round_trip(original) |> should.equal(original)
}

// --- encode: shape sanity via substring checks -------------------------

pub fn encode_point_shape_test() -> Nil {
  // GeoJSON coordinate order is [lng, lat] — verify both numbers
  // appear and that lng comes first. Using non-whole-number floats
  // so both target runtimes render them identically.
  let encoded = encode_geometry(geokit.Point(p(35.6812, 139.7671)))
  string.contains(encoded, "\"type\":\"Point\"") |> should.be_true
  string.contains(encoded, "[139.7671,35.6812]") |> should.be_true
}

pub fn encode_polygon_nests_rings_test() -> Nil {
  let encoded =
    encode_geometry(
      geokit.Polygon([
        [p(35.6812, 139.7671), p(35.6813, 139.7672)],
      ]),
    )
  string.contains(encoded, "\"type\":\"Polygon\"") |> should.be_true
  string.contains(encoded, "[[[139.7671,35.6812],[139.7672,35.6813]]]")
  |> should.be_true
}

// --- decode: each geometry type -----------------------------------------

pub fn decode_point_test() -> Nil {
  let assert Ok(geokit.Point(point)) =
    parse_geometry("{\"type\":\"Point\",\"coordinates\":[139.0,35.0]}")
  geokit.latitude(point) |> should.equal(35.0)
  geokit.longitude(point) |> should.equal(139.0)
}

pub fn decode_line_string_test() -> Nil {
  let input = "{\"type\":\"LineString\",\"coordinates\":[[0.0,0.0],[1.0,1.0]]}"
  let assert Ok(geokit.LineString(points)) = parse_geometry(input)
  points
  |> should.equal([p(0.0, 0.0), p(1.0, 1.0)])
}

pub fn decode_polygon_test() -> Nil {
  let input =
    "{\"type\":\"Polygon\",\"coordinates\":[[[0.0,0.0],[1.0,0.0],[1.0,1.0],[0.0,0.0]]]}"
  let assert Ok(geokit.Polygon(rings)) = parse_geometry(input)
  rings
  |> should.equal([[p(0.0, 0.0), p(0.0, 1.0), p(1.0, 1.0), p(0.0, 0.0)]])
}

pub fn decode_multi_polygon_test() -> Nil {
  let input =
    "{\"type\":\"MultiPolygon\",\"coordinates\":[[[[0.0,0.0],[1.0,0.0],[1.0,1.0],[0.0,0.0]]]]}"
  let assert Ok(geokit.MultiPolygon(polygons)) = parse_geometry(input)
  polygons
  |> should.equal([[[p(0.0, 0.0), p(0.0, 1.0), p(1.0, 1.0), p(0.0, 0.0)]]])
}

pub fn decode_polygon_with_no_rings_is_rejected_test() -> Nil {
  parse_geometry("{\"type\":\"Polygon\",\"coordinates\":[]}")
  |> expected
  |> should.equal("Polygon with at least one linear ring")
}

pub fn decode_polygon_with_empty_ring_is_rejected_test() -> Nil {
  parse_geometry("{\"type\":\"Polygon\",\"coordinates\":[[]]}")
  |> expected
  |> should.equal("linear ring with at least 4 positions")
}

pub fn decode_polygon_with_three_position_ring_is_rejected_test() -> Nil {
  let input =
    "{\"type\":\"Polygon\",\"coordinates\":[[[0.0,0.0],[1.0,0.0],[0.0,0.0]]]}"
  parse_geometry(input)
  |> expected
  |> should.equal("linear ring with at least 4 positions")
}

pub fn decode_polygon_with_unclosed_ring_is_rejected_test() -> Nil {
  let input =
    "{\"type\":\"Polygon\",\"coordinates\":[[[0.0,0.0],[1.0,0.0],[1.0,1.0],[0.5,0.5]]]}"
  let error = first_error(parse_geometry(input))
  error.expected
  |> should.equal("closed linear ring (first position equal to last)")
  error.path |> should.equal(["coordinates", "0"])
}

pub fn decode_polygon_whose_ring_ends_on_the_same_latitude_is_rejected_test() -> Nil {
  // The last position shares only the latitude of the first one, or only
  // the longitude, so the ring is still open.
  let same_latitude =
    "{\"type\":\"Polygon\",\"coordinates\":[[[0.0,0.0],[1.0,0.0],[1.0,1.0],[2.0,0.0]]]}"
  let same_longitude =
    "{\"type\":\"Polygon\",\"coordinates\":[[[0.0,0.0],[1.0,0.0],[1.0,1.0],[0.0,2.0]]]}"
  parse_geometry(same_latitude)
  |> expected
  |> should.equal("closed linear ring (first position equal to last)")
  parse_geometry(same_longitude)
  |> expected
  |> should.equal("closed linear ring (first position equal to last)")
}

pub fn decode_multi_polygon_with_invalid_sub_polygon_is_rejected_test() -> Nil {
  let input = "{\"type\":\"MultiPolygon\",\"coordinates\":[[[]]]}"
  let error = first_error(parse_geometry(input))
  error.expected |> should.equal("linear ring with at least 4 positions")
  error.path |> should.equal(["coordinates", "0", "0"])
}

pub fn decode_missing_coordinates_reports_path_test() -> Nil {
  // The error names the missing field so a caller can return a useful
  // 400.
  let error = first_error(parse_geometry("{\"type\":\"Point\"}"))
  error.path |> should.equal(["coordinates"])
}

pub fn decode_non_numeric_coordinates_reports_path_test() -> Nil {
  let input = "{\"type\":\"Point\",\"coordinates\":[\"a\",\"b\"]}"
  let error = first_error(parse_geometry(input))
  string.contains(error.expected, "Float") |> should.be_true
  error.path |> should.equal(["coordinates", "0"])
}

pub fn decode_null_coordinates_reports_path_test() -> Nil {
  let input = "{\"type\":\"Point\",\"coordinates\":[null,null]}"
  parse_geometry(input)
  |> expected
  |> string.contains("Float")
  |> should.be_true
}

// --- altitude (3rd coordinate) is accepted and discarded ----------------

pub fn decode_point_with_altitude_test() -> Nil {
  let assert Ok(geokit.Point(point)) =
    parse_geometry("{\"type\":\"Point\",\"coordinates\":[139.0,35.0,123.4]}")
  geokit.latitude(point) |> should.equal(35.0)
  geokit.longitude(point) |> should.equal(139.0)
}

// --- decode errors -------------------------------------------------------

pub fn decode_invalid_json_test() -> Nil {
  let assert Error(json.UnexpectedByte(_)) = parse_geometry("{not json")
  Nil
}

pub fn decode_unknown_type_test() -> Nil {
  let error =
    first_error(parse_geometry("{\"type\":\"Hexagon\",\"coordinates\":[]}"))
  error.expected
  |> should.equal(
    "Point, MultiPoint, LineString, MultiLineString, Polygon or MultiPolygon",
  )
  error.path |> should.equal(["type"])
}

pub fn decode_multi_point_test() -> Nil {
  // GeoJSON coordinate order is [longitude, latitude]; the decoder swaps
  // it to geokit's latitude, longitude.
  let assert Ok(geokit.MultiPoint([point_a, point_b])) =
    parse_geometry(
      "{\"type\":\"MultiPoint\",\"coordinates\":[[139.0,35.0],[140.0,36.0]]}",
    )
  let assert Ok(expected_a) = geokit.lat_lng(latitude: 35.0, longitude: 139.0)
  let assert Ok(expected_b) = geokit.lat_lng(latitude: 36.0, longitude: 140.0)
  point_a |> should.equal(expected_a)
  point_b |> should.equal(expected_b)
}

pub fn encode_multi_point_round_trips_test() -> Nil {
  let assert Ok(a) = geokit.lat_lng(latitude: 35.0, longitude: 139.0)
  let assert Ok(b) = geokit.lat_lng(latitude: 36.0, longitude: 140.0)
  let encoded = encode_geometry(geokit.MultiPoint([a, b]))
  parse_geometry(encoded) |> should.equal(Ok(geokit.MultiPoint([a, b])))
}

pub fn decode_multi_line_string_test() -> Nil {
  parse_geometry(
    "{\"type\":\"MultiLineString\",\"coordinates\":[[[0,0],[1,1]],[[2,2]]]}",
  )
  |> should.equal(
    Ok(geokit.MultiLineString([[p(0.0, 0.0), p(1.0, 1.0)], [p(2.0, 2.0)]])),
  )
}

pub fn encode_multi_line_string_round_trip_test() -> Nil {
  let original =
    geokit.MultiLineString([
      [p(35.6812, 139.7671), p(34.6937, 135.5023)],
      [],
      [p(-33.5, 151.25)],
    ])
  round_trip(original) |> should.equal(original)
  encode_geometry(geokit.MultiLineString([[p(1.5, 2.5)]]))
  |> should.equal(
    "{\"type\":\"MultiLineString\",\"coordinates\":[[[2.5,1.5]]]}",
  )
}

pub fn decode_unsupported_geometry_collection_test() -> Nil {
  let error =
    first_error(parse_geometry(
      "{\"type\":\"GeometryCollection\",\"geometries\":[]}",
    ))
  error.expected
  |> should.equal(
    "Point, MultiPoint, LineString, MultiLineString, Polygon or MultiPolygon",
  )
  error.path |> should.equal(["type"])
}

pub fn decode_missing_coordinates_test() -> Nil {
  let assert Error(json.UnableToDecode(_)) =
    parse_geometry("{\"type\":\"Point\"}")
  Nil
}

pub fn decode_invalid_position_too_few_test() -> Nil {
  parse_geometry("{\"type\":\"Point\",\"coordinates\":[1.0]}")
  |> expected
  |> should.equal("position of 2 or 3 numbers")
  parse_geometry("{\"type\":\"Point\",\"coordinates\":[1,2,3,4]}")
  |> expected
  |> should.equal("position of 2 or 3 numbers")
}

pub fn decode_lat_out_of_range_test() -> Nil {
  let error =
    first_error(parse_geometry(
      "{\"type\":\"Point\",\"coordinates\":[0.0,95.0]}",
    ))
  error.expected |> should.equal("latitude in [-90, 90]")
  error.path |> should.equal(["coordinates"])
}

pub fn decode_lng_out_of_range_test() -> Nil {
  parse_geometry("{\"type\":\"Point\",\"coordinates\":[200.0,0.0]}")
  |> expected
  |> should.equal("longitude in [-180, 180]")
  parse_geometry("{\"type\":\"LineString\",\"coordinates\":[[0,0],[-181,0]]}")
  |> first_error
  |> fn(error: decode.DecodeError) { #(error.expected, error.path) }
  |> should.equal(#("longitude in [-180, 180]", ["coordinates", "1"]))
}

// --- Feature: encode + decode with typed properties ---------------------

type CityProps {
  CityProps(name: String, population: Int)
}

fn city_to_json(props: CityProps) -> json.Json {
  json.object([
    #("name", json.string(props.name)),
    #("population", json.int(props.population)),
  ])
}

fn city_decoder() -> decode.Decoder(CityProps) {
  use name <- decode.field("name", decode.string)
  use population <- decode.field("population", decode.int)
  decode.success(CityProps(name: name, population: population))
}

pub fn encode_feature_shape_test() -> Nil {
  let feature =
    geojson.Feature(
      geometry: Some(geokit.Point(p(35.6812, 139.7671))),
      properties: CityProps(name: "Tokyo", population: 13_960_000),
      id: Some(geojson.StringId("tokyo")),
    )
  let encoded =
    geojson.feature_to_json(feature, properties: city_to_json) |> json.to_string
  string.contains(encoded, "\"type\":\"Feature\"") |> should.be_true
  string.contains(encoded, "\"geometry\":") |> should.be_true
  string.contains(encoded, "\"properties\":{\"name\":\"Tokyo\"")
  |> should.be_true
  string.contains(encoded, "\"id\":\"tokyo\"") |> should.be_true
}

pub fn encode_feature_round_trip_test() -> Nil {
  let original =
    geojson.Feature(
      geometry: Some(geokit.Point(p(35.6812, 139.7671))),
      properties: CityProps(name: "Tokyo", population: 13_960_000),
      id: Some(geojson.StringId("tokyo")),
    )
  let encoded =
    geojson.feature_to_json(original, properties: city_to_json)
    |> json.to_string
  let assert Ok(decoded) =
    json.parse(encoded, geojson.feature_decoder(properties: city_decoder()))
  decoded |> should.equal(original)
}

pub fn encode_feature_without_id_round_trip_test() -> Nil {
  let original =
    geojson.Feature(
      geometry: Some(geokit.Point(p(35.6812, 139.7671))),
      properties: CityProps(name: "Tokyo", population: 13_960_000),
      id: None,
    )
  let encoded =
    geojson.feature_to_json(original, properties: city_to_json)
    |> json.to_string
  let assert Ok(decoded) =
    json.parse(encoded, geojson.feature_decoder(properties: city_decoder()))
  decoded |> should.equal(original)
}

pub fn decode_feature_int_id_test() -> Nil {
  let input =
    "{\"type\":\"Feature\",\"geometry\":{\"type\":\"Point\",\"coordinates\":[0.0,0.0]},\"properties\":{\"name\":\"X\",\"population\":1},\"id\":42}"
  let assert Ok(feature) =
    json.parse(input, geojson.feature_decoder(properties: city_decoder()))
  feature.id |> should.equal(Some(geojson.IntId(42)))
}

// --- FeatureCollection --------------------------------------------------

pub fn feature_collection_round_trip_test() -> Nil {
  let features = [
    geojson.Feature(
      geometry: Some(geokit.Point(p(35.6812, 139.7671))),
      properties: CityProps(name: "Tokyo", population: 13_960_000),
      id: None,
    ),
    geojson.Feature(
      geometry: Some(geokit.Point(p(34.6937, 135.5023))),
      properties: CityProps(name: "Osaka", population: 2_700_000),
      id: None,
    ),
  ]
  let encoded =
    geojson.feature_collection_to_json(features, properties: city_to_json)
    |> json.to_string
  let assert Ok(decoded) =
    json.parse(
      encoded,
      geojson.feature_collection_decoder(properties: city_decoder()),
    )
  decoded |> should.equal(features)
}

// --- integer coordinates ------------------------------------------------

pub fn decode_point_with_integer_coordinates_test() -> Nil {
  let assert Ok(geokit.Point(point)) =
    parse_geometry("{\"type\":\"Point\",\"coordinates\":[139,35,12]}")
  #(geokit.latitude(point), geokit.longitude(point))
  |> should.equal(#(35.0, 139.0))
}

pub fn decode_mixed_integer_and_float_coordinates_test() -> Nil {
  let assert Ok(geokit.LineString(points)) =
    parse_geometry("{\"type\":\"LineString\",\"coordinates\":[[0,0],[1.5,2]]}")
  points
  |> should.equal([
    geokit.wrap_lat_lng(latitude: 0.0, longitude: 0.0),
    geokit.wrap_lat_lng(latitude: 2.0, longitude: 1.5),
  ])
}

pub fn decode_polygons_with_integer_coordinates_test() -> Nil {
  let ring = "[[0,0],[10,0],[10,10],[0,0]]"
  let expected = [
    geokit.wrap_lat_lng(latitude: 0.0, longitude: 0.0),
    geokit.wrap_lat_lng(latitude: 0.0, longitude: 10.0),
    geokit.wrap_lat_lng(latitude: 10.0, longitude: 10.0),
    geokit.wrap_lat_lng(latitude: 0.0, longitude: 0.0),
  ]
  parse_geometry("{\"type\":\"Polygon\",\"coordinates\":[" <> ring <> "]}")
  |> should.equal(Ok(geokit.Polygon([expected])))
  parse_geometry(
    "{\"type\":\"MultiPolygon\",\"coordinates\":[[" <> ring <> "]]}",
  )
  |> should.equal(Ok(geokit.MultiPolygon([[expected]])))
  parse_geometry("{\"type\":\"MultiPoint\",\"coordinates\":[[1,2],[3,4]]}")
  |> should.equal(
    Ok(
      geokit.MultiPoint([
        geokit.wrap_lat_lng(latitude: 2.0, longitude: 1.0),
        geokit.wrap_lat_lng(latitude: 4.0, longitude: 3.0),
      ]),
    ),
  )
}

// --- signed zero --------------------------------------------------------

pub fn decode_polygon_closed_with_signed_zero_test() -> Nil {
  // The ring starts at 0.0 and ends at -0.0: the same position.
  let input =
    "{\"type\":\"Polygon\",\"coordinates\":[[[0.0,0.0],[1.0,0.0],[1.0,1.0],[-0.0,-0.0]]]}"
  let assert Ok(geokit.Polygon([ring])) = parse_geometry(input)
  list.length(ring)
  |> should.equal(4)
}

// --- huge integers --------------------------------------------------------

// The Erlang JSON parser keeps a huge integer as a bignum, which
// `int.to_float` cannot convert; it must be a decode error, not a crash.
@target(erlang)
pub fn decode_huge_integer_coordinate_is_an_error_test() -> Nil {
  let huge = "1" <> string.repeat("0", 400)
  let input = "{\"type\":\"Point\",\"coordinates\":[" <> huge <> ",0]}"
  parse_geometry(input)
  |> expected
  |> should.equal("Float")
}

pub fn decode_integer_coordinates_test() -> Nil {
  parse_geometry("{\"type\":\"Point\",\"coordinates\":[-180,90]}")
  |> should.equal(Ok(geokit.Point(p(90.0, -180.0))))
}

// --- null geometry and number ids ---------------------------------------

pub fn feature_with_null_geometry_round_trips_test() -> Nil {
  let original =
    geojson.Feature(
      geometry: None,
      properties: CityProps(name: "Nowhere", population: 0),
      id: Some(geojson.IntId(7)),
    )
  let encoded =
    geojson.feature_to_json(original, properties: city_to_json)
    |> json.to_string
  string.contains(encoded, "\"geometry\":null") |> should.be_true
  json.parse(encoded, geojson.feature_decoder(properties: city_decoder()))
  |> should.equal(Ok(original))
}

pub fn decode_feature_float_id_test() -> Nil {
  let input =
    "{\"type\":\"Feature\",\"geometry\":null,\"properties\":null,\"id\":1.5}"
  let assert Ok(feature) =
    json.parse(input, geojson.feature_decoder(properties: decode.dynamic))
  feature.id |> should.equal(Some(geojson.FloatId(1.5)))
}

pub fn decode_feature_with_wrong_type_fails_test() -> Nil {
  let error =
    json.parse(
      "{\"type\":\"Point\",\"coordinates\":[0,0]}",
      geojson.feature_decoder(properties: decode.dynamic),
    )
    |> first_error
  error.expected |> should.equal("Feature")
  error.path |> should.equal(["type"])
}

pub fn decode_feature_collection_with_wrong_type_fails_test() -> Nil {
  json.parse(
    "{\"type\":\"Feature\",\"features\":[]}",
    geojson.feature_collection_decoder(properties: decode.dynamic),
  )
  |> expected
  |> should.equal("FeatureCollection")
}

pub fn decode_feature_collection_reports_bad_feature_path_test() -> Nil {
  let input =
    "{\"type\":\"FeatureCollection\",\"features\":[{\"type\":\"Feature\",\"geometry\":{\"type\":\"Point\",\"coordinates\":[0,99]},\"properties\":null}]}"
  let error =
    json.parse(
      input,
      geojson.feature_collection_decoder(properties: decode.dynamic),
    )
    |> first_error
  error.expected |> should.equal("latitude in [-90, 90]")
  error.path
  |> should.equal(["features", "0", "geometry", "coordinates"])
}
