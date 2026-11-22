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
  let encoded = geojson.encode_geometry(geometry: g)
  let assert Ok(decoded) = geojson.decode_geometry(input: encoded)
  decoded
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
  let encoded =
    geojson.encode_geometry(geometry: geokit.Point(p(35.6812, 139.7671)))
  string.contains(encoded, "\"type\":\"Point\"") |> should.be_true
  string.contains(encoded, "[139.7671,35.6812]") |> should.be_true
}

pub fn encode_polygon_nests_rings_test() -> Nil {
  let encoded =
    geojson.encode_geometry(
      geometry: geokit.Polygon([
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
    geojson.decode_geometry(
      input: "{\"type\":\"Point\",\"coordinates\":[139.0,35.0]}",
    )
  geokit.latitude(point) |> should.equal(35.0)
  geokit.longitude(point) |> should.equal(139.0)
}

pub fn decode_line_string_test() -> Nil {
  let input = "{\"type\":\"LineString\",\"coordinates\":[[0.0,0.0],[1.0,1.0]]}"
  let assert Ok(geokit.LineString(points)) =
    geojson.decode_geometry(input: input)
  points
  |> should.equal([p(0.0, 0.0), p(1.0, 1.0)])
}

pub fn decode_polygon_test() -> Nil {
  let input =
    "{\"type\":\"Polygon\",\"coordinates\":[[[0.0,0.0],[1.0,0.0],[1.0,1.0],[0.0,0.0]]]}"
  let assert Ok(geokit.Polygon(rings)) = geojson.decode_geometry(input: input)
  rings
  |> should.equal([[p(0.0, 0.0), p(0.0, 1.0), p(1.0, 1.0), p(0.0, 0.0)]])
}

pub fn decode_multi_polygon_test() -> Nil {
  let input =
    "{\"type\":\"MultiPolygon\",\"coordinates\":[[[[0.0,0.0],[1.0,0.0],[1.0,1.0],[0.0,0.0]]]]}"
  let assert Ok(geokit.MultiPolygon(polygons)) =
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

pub fn decode_polygon_whose_ring_ends_on_the_same_latitude_is_rejected_test() -> Nil {
  // The last position shares only the latitude of the first one, or only
  // the longitude, so the ring is still open.
  let same_latitude =
    "{\"type\":\"Polygon\",\"coordinates\":[[[0.0,0.0],[1.0,0.0],[1.0,1.0],[2.0,0.0]]]}"
  let same_longitude =
    "{\"type\":\"Polygon\",\"coordinates\":[[[0.0,0.0],[1.0,0.0],[1.0,1.0],[0.0,2.0]]]}"
  case geojson.decode_geometry(input: same_latitude) {
    Error(geojson.InvalidPolygon(reason: _)) -> Nil
    _ -> should.fail()
  }
  case geojson.decode_geometry(input: same_longitude) {
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

pub fn decode_missing_coordinates_reports_path_test() -> Nil {
  // Previously surfaced as the opaque "JSON shape did not match
  // expected GeoJSON"; the reason now names the failing field path
  // and the decoder's expected/found pair so a caller can return
  // a useful 400.
  case geojson.decode_geometry(input: "{\"type\":\"Point\"}") {
    Error(geojson.InvalidStructure(reason: reason)) -> {
      string.contains(reason, "coordinates") |> should.be_true
    }
    _ -> should.fail()
  }
}

pub fn decode_non_numeric_coordinates_reports_path_test() -> Nil {
  let input = "{\"type\":\"Point\",\"coordinates\":[\"a\",\"b\"]}"
  case geojson.decode_geometry(input: input) {
    Error(geojson.InvalidStructure(reason: reason)) -> {
      string.contains(reason, "Float") |> should.be_true
    }
    _ -> should.fail()
  }
}

pub fn decode_null_coordinates_reports_path_test() -> Nil {
  let input = "{\"type\":\"Point\",\"coordinates\":[null,null]}"
  case geojson.decode_geometry(input: input) {
    Error(geojson.InvalidStructure(reason: reason)) -> {
      string.contains(reason, "Float") |> should.be_true
    }
    _ -> should.fail()
  }
}

// --- altitude (3rd coordinate) is accepted and discarded ----------------

pub fn decode_point_with_altitude_test() -> Nil {
  let assert Ok(geokit.Point(point)) =
    geojson.decode_geometry(
      input: "{\"type\":\"Point\",\"coordinates\":[139.0,35.0,123.4]}",
    )
  geokit.latitude(point) |> should.equal(35.0)
  geokit.longitude(point) |> should.equal(139.0)
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
  let assert Ok(geokit.MultiPoint([point_a, point_b])) =
    geojson.decode_geometry(
      // GeoJSON coordinate order is [longitude, latitude] — the
      // decoder is expected to swap to geokit's `lat, lng` shape.
      input: "{\"type\":\"MultiPoint\",\"coordinates\":[[139.0,35.0],[140.0,36.0]]}",
    )
  let assert Ok(expected_a) = geokit.lat_lng(latitude: 35.0, longitude: 139.0)
  let assert Ok(expected_b) = geokit.lat_lng(latitude: 36.0, longitude: 140.0)
  let assert True = point_a == expected_a
  let assert True = point_b == expected_b
  Nil
}

pub fn encode_multi_point_round_trips_test() -> Nil {
  let assert Ok(a) = geokit.lat_lng(latitude: 35.0, longitude: 139.0)
  let assert Ok(b) = geokit.lat_lng(latitude: 36.0, longitude: 140.0)
  let encoded = geojson.encode_geometry(geometry: geokit.MultiPoint([a, b]))
  let assert Ok(geokit.MultiPoint([decoded_a, decoded_b])) =
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
  let assert Error(geojson.InvalidLatLng(geokit.LatitudeOutOfRange(
    latitude: 95.0,
  ))) =
    geojson.decode_geometry(
      input: "{\"type\":\"Point\",\"coordinates\":[0.0,95.0]}",
    )
  Nil
}

pub fn decode_lng_out_of_range_test() -> Nil {
  let assert Error(geojson.InvalidLatLng(geokit.LongitudeOutOfRange(
    longitude: 200.0,
  ))) =
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
      geometry: geokit.Point(p(35.6812, 139.7671)),
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
      geometry: geokit.Point(p(35.6812, 139.7671)),
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
      geometry: geokit.Point(p(35.6812, 139.7671)),
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
      geometry: geokit.Point(p(35.6812, 139.7671)),
      properties: CityProps(name: "Tokyo", population: 13_960_000),
      id: None,
    ),
    geojson.Feature(
      geometry: geokit.Point(p(34.6937, 135.5023)),
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

// --- integer coordinates ------------------------------------------------

pub fn decode_point_with_integer_coordinates_test() -> Nil {
  let assert Ok(geokit.Point(point)) =
    geojson.decode_geometry(
      input: "{\"type\":\"Point\",\"coordinates\":[139,35,12]}",
    )
  #(geokit.latitude(point), geokit.longitude(point))
  |> should.equal(#(35.0, 139.0))
}

pub fn decode_mixed_integer_and_float_coordinates_test() -> Nil {
  let assert Ok(geokit.LineString(points)) =
    geojson.decode_geometry(
      input: "{\"type\":\"LineString\",\"coordinates\":[[0,0],[1.5,2]]}",
    )
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
  geojson.decode_geometry(
    input: "{\"type\":\"Polygon\",\"coordinates\":[" <> ring <> "]}",
  )
  |> should.equal(Ok(geokit.Polygon([expected])))
  geojson.decode_geometry(
    input: "{\"type\":\"MultiPolygon\",\"coordinates\":[[" <> ring <> "]]}",
  )
  |> should.equal(Ok(geokit.MultiPolygon([[expected]])))
  geojson.decode_geometry(
    input: "{\"type\":\"MultiPoint\",\"coordinates\":[[1,2],[3,4]]}",
  )
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
  let assert Ok(geokit.Polygon([ring])) = geojson.decode_geometry(input: input)
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
  case geojson.decode_geometry(input: input) {
    Error(geojson.InvalidStructure(_)) -> Nil
    _ -> should.be_true(False)
  }
}

pub fn decode_integer_coordinates_test() -> Nil {
  geojson.decode_geometry(
    input: "{\"type\":\"Point\",\"coordinates\":[-180,90]}",
  )
  |> should.equal(Ok(geokit.Point(p(90.0, -180.0))))
}
