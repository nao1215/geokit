import gleam/dynamic/decode
import gleam/json
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

import geokit/geojson
import geokit/geometry
import geokit/latlng

// --- helpers -------------------------------------------------------------

fn p(lat: Float, lng: Float) -> latlng.LatLng {
  let assert Ok(point) = latlng.new(lat: lat, lng: lng)
  point
}

// Round-trip a Geometry through encode + decode. Used by the encode
// tests so they stay target-portable: the JavaScript runtime renders
// whole-number floats as `0` while Erlang renders them as `0.0`, so a
// byte-exact assertion on the encoded string would diverge between
// targets. A round-trip is the contract that actually matters.
fn round_trip(g: geometry.Geometry) -> geometry.Geometry {
  let encoded = geojson.encode_geometry(geometry: g)
  let assert Ok(decoded) = geojson.decode_geometry(input: encoded)
  decoded
}

// --- encode: shape sanity via round-trip --------------------------------

pub fn encode_point_round_trip_test() -> Nil {
  let original = geometry.Point(p(35.6812, 139.7671))
  round_trip(original) |> should.equal(original)
}

pub fn encode_line_string_round_trip_test() -> Nil {
  let original =
    geometry.LineString([p(35.6812, 139.7671), p(34.6937, 135.5023)])
  round_trip(original) |> should.equal(original)
}

pub fn encode_polygon_round_trip_test() -> Nil {
  let ring = [
    p(35.6812, 139.7671),
    p(35.6812, 139.7672),
    p(35.6813, 139.7672),
    p(35.6812, 139.7671),
  ]
  let original = geometry.Polygon([ring])
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
  let original = geometry.MultiPolygon([[ring_a], [ring_b]])
  round_trip(original) |> should.equal(original)
}

// --- encode: shape sanity via substring checks -------------------------

pub fn encode_point_shape_test() -> Nil {
  // GeoJSON coordinate order is [lng, lat] — verify both numbers
  // appear and that lng comes first. Using non-whole-number floats
  // so both target runtimes render them identically.
  let encoded =
    geojson.encode_geometry(geometry: geometry.Point(p(35.6812, 139.7671)))
  string.contains(encoded, "\"type\":\"Point\"") |> should.be_true
  string.contains(encoded, "[139.7671,35.6812]") |> should.be_true
}

pub fn encode_polygon_nests_rings_test() -> Nil {
  let encoded =
    geojson.encode_geometry(
      geometry: geometry.Polygon([
        [p(35.6812, 139.7671), p(35.6813, 139.7672)],
      ]),
    )
  string.contains(encoded, "\"type\":\"Polygon\"") |> should.be_true
  string.contains(encoded, "[[[139.7671,35.6812],[139.7672,35.6813]]]")
  |> should.be_true
}

// --- decode: each geometry type -----------------------------------------

pub fn decode_point_test() -> Nil {
  let assert Ok(geometry.Point(point)) =
    geojson.decode_geometry(
      input: "{\"type\":\"Point\",\"coordinates\":[139.0,35.0]}",
    )
  latlng.lat(point) |> should.equal(35.0)
  latlng.lng(point) |> should.equal(139.0)
}

pub fn decode_line_string_test() -> Nil {
  let input = "{\"type\":\"LineString\",\"coordinates\":[[0.0,0.0],[1.0,1.0]]}"
  let assert Ok(geometry.LineString(points)) =
    geojson.decode_geometry(input: input)
  points
  |> should.equal([p(0.0, 0.0), p(1.0, 1.0)])
}

pub fn decode_polygon_test() -> Nil {
  let input =
    "{\"type\":\"Polygon\",\"coordinates\":[[[0.0,0.0],[1.0,0.0],[1.0,1.0],[0.0,0.0]]]}"
  let assert Ok(geometry.Polygon(rings)) = geojson.decode_geometry(input: input)
  rings
  |> should.equal([[p(0.0, 0.0), p(0.0, 1.0), p(1.0, 1.0), p(0.0, 0.0)]])
}

pub fn decode_multi_polygon_test() -> Nil {
  let input =
    "{\"type\":\"MultiPolygon\",\"coordinates\":[[[[0.0,0.0],[1.0,0.0],[1.0,1.0],[0.0,0.0]]]]}"
  let assert Ok(geometry.MultiPolygon(polygons)) =
    geojson.decode_geometry(input: input)
  polygons
  |> should.equal([[[p(0.0, 0.0), p(0.0, 1.0), p(1.0, 1.0), p(0.0, 0.0)]]])
}

pub fn decode_polygon_with_no_rings_is_rejected_test() -> Nil {
  let result =
    geojson.decode_geometry(input: "{\"type\":\"Polygon\",\"coordinates\":[]}")
  case result {
    Error(geojson.InvalidPolygon(reason: _)) -> Nil
    _ -> should.fail()
  }
}

pub fn decode_polygon_with_empty_ring_is_rejected_test() -> Nil {
  let result =
    geojson.decode_geometry(
      input: "{\"type\":\"Polygon\",\"coordinates\":[[]]}",
    )
  case result {
    Error(geojson.InvalidPolygon(reason: _)) -> Nil
    _ -> should.fail()
  }
}

pub fn decode_polygon_with_three_position_ring_is_rejected_test() -> Nil {
  let input =
    "{\"type\":\"Polygon\",\"coordinates\":[[[0.0,0.0],[1.0,0.0],[0.0,0.0]]]}"
  case geojson.decode_geometry(input: input) {
    Error(geojson.InvalidPolygon(reason: _)) -> Nil
    _ -> should.fail()
  }
}

pub fn decode_polygon_with_unclosed_ring_is_rejected_test() -> Nil {
  let input =
    "{\"type\":\"Polygon\",\"coordinates\":[[[0.0,0.0],[1.0,0.0],[1.0,1.0],[0.5,0.5]]]}"
  case geojson.decode_geometry(input: input) {
    Error(geojson.InvalidPolygon(reason: _)) -> Nil
    _ -> should.fail()
  }
}

pub fn decode_multi_polygon_with_invalid_sub_polygon_is_rejected_test() -> Nil {
  let input = "{\"type\":\"MultiPolygon\",\"coordinates\":[[[]]]}"
  case geojson.decode_geometry(input: input) {
    Error(geojson.InvalidPolygon(reason: _)) -> Nil
    _ -> should.fail()
  }
}

// --- altitude (3rd coordinate) is accepted and discarded ----------------

pub fn decode_point_with_altitude_test() -> Nil {
  let assert Ok(geometry.Point(point)) =
    geojson.decode_geometry(
      input: "{\"type\":\"Point\",\"coordinates\":[139.0,35.0,123.4]}",
    )
  latlng.lat(point) |> should.equal(35.0)
  latlng.lng(point) |> should.equal(139.0)
}

// --- decode errors -------------------------------------------------------

pub fn decode_invalid_json_test() -> Nil {
  let assert Error(geojson.InvalidJson(_)) =
    geojson.decode_geometry(input: "{not json")
  Nil
}

pub fn decode_unknown_type_test() -> Nil {
  let assert Error(geojson.UnknownType("Hexagon")) =
    geojson.decode_geometry(input: "{\"type\":\"Hexagon\",\"coordinates\":[]}")
  Nil
}

pub fn decode_multi_point_test() -> Nil {
  let assert Ok(geometry.MultiPoint([point_a, point_b])) =
    geojson.decode_geometry(
      // GeoJSON coordinate order is [longitude, latitude] — the
      // decoder is expected to swap to geokit's `lat, lng` shape.
      input: "{\"type\":\"MultiPoint\",\"coordinates\":[[139.0,35.0],[140.0,36.0]]}",
    )
  let assert Ok(expected_a) = latlng.new(lat: 35.0, lng: 139.0)
  let assert Ok(expected_b) = latlng.new(lat: 36.0, lng: 140.0)
  let assert True = point_a == expected_a
  let assert True = point_b == expected_b
  Nil
}

pub fn encode_multi_point_round_trips_test() -> Nil {
  let assert Ok(a) = latlng.new(lat: 35.0, lng: 139.0)
  let assert Ok(b) = latlng.new(lat: 36.0, lng: 140.0)
  let encoded = geojson.encode_geometry(geometry: geometry.MultiPoint([a, b]))
  let assert Ok(geometry.MultiPoint([decoded_a, decoded_b])) =
    geojson.decode_geometry(input: encoded)
  let assert True = decoded_a == a
  let assert True = decoded_b == b
  Nil
}

pub fn decode_unsupported_geometry_collection_test() -> Nil {
  let assert Error(geojson.UnsupportedType("GeometryCollection")) =
    geojson.decode_geometry(
      input: "{\"type\":\"GeometryCollection\",\"geometries\":[]}",
    )
  Nil
}

pub fn decode_missing_coordinates_test() -> Nil {
  let assert Error(geojson.InvalidStructure(_)) =
    geojson.decode_geometry(input: "{\"type\":\"Point\"}")
  Nil
}

pub fn decode_invalid_position_too_few_test() -> Nil {
  let assert Error(geojson.InvalidPosition([1.0])) =
    geojson.decode_geometry(input: "{\"type\":\"Point\",\"coordinates\":[1.0]}")
  Nil
}

pub fn decode_lat_out_of_range_test() -> Nil {
  let assert Error(geojson.InvalidLatLng(latlng.LatOutOfRange(lat: 95.0))) =
    geojson.decode_geometry(
      input: "{\"type\":\"Point\",\"coordinates\":[0.0,95.0]}",
    )
  Nil
}

pub fn decode_lng_out_of_range_test() -> Nil {
  let assert Error(geojson.InvalidLatLng(latlng.LngOutOfRange(lng: 200.0))) =
    geojson.decode_geometry(
      input: "{\"type\":\"Point\",\"coordinates\":[200.0,0.0]}",
    )
  Nil
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
      geometry: geometry.Point(p(35.6812, 139.7671)),
      properties: CityProps(name: "Tokyo", population: 13_960_000),
      id: Some(geojson.StringId("tokyo")),
    )
  let encoded =
    geojson.encode_feature(feature: feature, properties: city_to_json)
  string.contains(encoded, "\"type\":\"Feature\"") |> should.be_true
  string.contains(encoded, "\"geometry\":") |> should.be_true
  string.contains(encoded, "\"properties\":{\"name\":\"Tokyo\"")
  |> should.be_true
  string.contains(encoded, "\"id\":\"tokyo\"") |> should.be_true
}

pub fn encode_feature_round_trip_test() -> Nil {
  let original =
    geojson.Feature(
      geometry: geometry.Point(p(35.6812, 139.7671)),
      properties: CityProps(name: "Tokyo", population: 13_960_000),
      id: Some(geojson.StringId("tokyo")),
    )
  let encoded =
    geojson.encode_feature(feature: original, properties: city_to_json)
  let assert Ok(decoded) =
    geojson.decode_feature(input: encoded, properties: city_decoder())
  decoded |> should.equal(original)
}

pub fn encode_feature_without_id_round_trip_test() -> Nil {
  let original =
    geojson.Feature(
      geometry: geometry.Point(p(35.6812, 139.7671)),
      properties: CityProps(name: "Tokyo", population: 13_960_000),
      id: None,
    )
  let encoded =
    geojson.encode_feature(feature: original, properties: city_to_json)
  let assert Ok(decoded) =
    geojson.decode_feature(input: encoded, properties: city_decoder())
  decoded |> should.equal(original)
}

pub fn decode_feature_int_id_test() -> Nil {
  let input =
    "{\"type\":\"Feature\",\"geometry\":{\"type\":\"Point\",\"coordinates\":[0.0,0.0]},\"properties\":{\"name\":\"X\",\"population\":1},\"id\":42}"
  let assert Ok(feature) =
    geojson.decode_feature(input: input, properties: city_decoder())
  feature.id |> should.equal(Some(geojson.IntId(42)))
}

// --- FeatureCollection --------------------------------------------------

pub fn feature_collection_round_trip_test() -> Nil {
  let features = [
    geojson.Feature(
      geometry: geometry.Point(p(35.6812, 139.7671)),
      properties: CityProps(name: "Tokyo", population: 13_960_000),
      id: None,
    ),
    geojson.Feature(
      geometry: geometry.Point(p(34.6937, 135.5023)),
      properties: CityProps(name: "Osaka", population: 2_700_000),
      id: None,
    ),
  ]
  let encoded =
    geojson.encode_feature_collection(
      features: features,
      properties: city_to_json,
    )
  let assert Ok(decoded) =
    geojson.decode_feature_collection(
      input: encoded,
      properties: city_decoder(),
    )
  decoded |> should.equal(features)
}
