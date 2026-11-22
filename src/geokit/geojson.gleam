//// GeoJSON (RFC 7946) encoders and decoders for geokit geometries and for
//// features with properties of your own type. Encoders return a
//// `json.Json` for `json.to_string`, and decoders are for `json.parse`.
//// GeoJSON writes a position as `[longitude, latitude]`; a third number
//// (altitude) is accepted when decoding and dropped. Decoders reject
//// positions out of range, polygon rings that are open or have fewer
//// than 4 positions, and `GeometryCollection`.

import gleam/bool
import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}

import geokit.{
  type Geometry, type LatLng, LineString, MultiLineString, MultiPoint,
  MultiPolygon, Point, Polygon,
}

/// The `id` of a feature: a string or a number.
pub type FeatureId {
  StringId(String)
  IntId(Int)
  FloatId(Float)
}

/// A GeoJSON feature. `geometry` is `None` for a feature whose geometry
/// is `null`.
pub type Feature(properties) {
  Feature(
    geometry: Option(Geometry),
    properties: properties,
    id: Option(FeatureId),
  )
}

const geometry_types =
  "Point, MultiPoint, LineString, MultiLineString, Polygon or MultiPolygon"

// --- Encoding ------------------------------------------------------------

/// Returns the GeoJSON geometry object for `geometry`. An open polygon
/// ring is closed by repeating its first position at the end.
/// [`geometry_decoder`](#geometry_decoder) rejects the output for a ring
/// with fewer than 3 positions besides the closing one, or for a polygon
/// without rings.
///
/// ## Examples
///
/// ```gleam
/// geokit.wrap_lat_lng(latitude: 35.5, longitude: 139.5)
/// |> geokit.Point
/// |> geometry_to_json
/// |> json.to_string
/// // -> "{\"type\":\"Point\",\"coordinates\":[139.5,35.5]}"
/// ```
pub fn geometry_to_json(geometry: Geometry) -> Json {
  let #(name, coordinates) = case geometry {
    Point(point) -> #("Point", position_to_json(point))
    MultiPoint(points) -> #("MultiPoint", positions_to_json(points))
    LineString(points) -> #("LineString", positions_to_json(points))
    MultiLineString(lines) -> #(
      "MultiLineString",
      json.array(lines, positions_to_json),
    )
    Polygon(rings) -> #("Polygon", json.array(rings, ring_to_json))
    MultiPolygon(polygons) -> #(
      "MultiPolygon",
      json.array(polygons, json.array(_, ring_to_json)),
    )
  }
  json.object([
    #("type", json.string(name)),
    #("coordinates", coordinates),
  ])
}

// GeoJSON requires a closed ring, so an open one gets its first
// position appended.
fn ring_to_json(ring: List(LatLng)) -> Json {
  case ring, list.last(ring) {
    [first, ..], Ok(last) if first != last ->
      positions_to_json(list.append(ring, [first]))
    _, _ -> positions_to_json(ring)
  }
}

fn positions_to_json(points: List(LatLng)) -> Json {
  json.array(points, position_to_json)
}

fn position_to_json(point: LatLng) -> Json {
  json.preprocessed_array([
    json.float(geokit.longitude(point)),
    json.float(geokit.latitude(point)),
  ])
}

/// Returns the GeoJSON feature object for `feature`, encoding its
/// properties with `properties`. A `None` geometry is written as `null`
/// and a `None` id is left out.
///
/// ## Examples
///
/// ```gleam
/// Feature(geometry: None, properties: "Tokyo", id: Some(IntId(1)))
/// |> feature_to_json(properties: fn(name) {
///   json.object([#("name", json.string(name))])
/// })
/// |> json.to_string
/// // -> "{\"type\":\"Feature\",\"geometry\":null,\"properties\":{\"name\":\"Tokyo\"},\"id\":1}"
/// ```
pub fn feature_to_json(
  feature: Feature(p),
  properties properties: fn(p) -> Json,
) -> Json {
  let entries = [
    #("type", json.string("Feature")),
    #("geometry", json.nullable(feature.geometry, geometry_to_json)),
    #("properties", properties(feature.properties)),
  ]
  json.object(case feature.id {
    None -> entries
    Some(id) -> list.append(entries, [#("id", id_to_json(id))])
  })
}

fn id_to_json(id: FeatureId) -> Json {
  case id {
    StringId(value) -> json.string(value)
    IntId(value) -> json.int(value)
    FloatId(value) -> json.float(value)
  }
}

/// Returns the GeoJSON feature collection object for `features`,
/// encoding each feature's properties with `properties`.
///
/// ## Examples
///
/// ```gleam
/// [Feature(geometry: None, properties: Nil, id: None)]
/// |> feature_collection_to_json(properties: fn(_) { json.null() })
/// |> json.to_string
/// // -> "{\"type\":\"FeatureCollection\",\"features\":[{\"type\":\"Feature\",\"geometry\":null,\"properties\":null}]}"
/// ```
pub fn feature_collection_to_json(
  features: List(Feature(p)),
  properties properties: fn(p) -> Json,
) -> Json {
  json.object([
    #("type", json.string("FeatureCollection")),
    #("features", json.array(features, feature_to_json(_, properties:))),
  ])
}

// --- Decoding ------------------------------------------------------------

/// Returns a decoder for a GeoJSON geometry object. Integer and
/// fractional coordinates are both accepted.
///
/// ## Examples
///
/// ```gleam
/// json.parse(
///   "{\"type\":\"Point\",\"coordinates\":[139.5,35.5]}",
///   geometry_decoder(),
/// )
/// // -> Ok(Point(geokit.wrap_lat_lng(latitude: 35.5, longitude: 139.5)))
/// ```
///
/// ```gleam
/// json.parse(
///   "{\"type\":\"Circle\",\"coordinates\":[139.5,35.5]}",
///   geometry_decoder(),
/// )
/// // -> Error(json.UnableToDecode([decode.DecodeError(
/// //   expected: "Point, MultiPoint, LineString, MultiLineString, Polygon or MultiPolygon",
/// //   found: "String",
/// //   path: ["type"],
/// // )]))
/// ```
pub fn geometry_decoder() -> Decoder(Geometry) {
  use name <- decode.field("type", decode.string)
  case name {
    "Point" -> coordinates(position_decoder(), Point)
    "MultiPoint" -> coordinates(decode.list(position_decoder()), MultiPoint)
    "LineString" -> coordinates(decode.list(position_decoder()), LineString)
    "MultiLineString" ->
      coordinates(decode.list(decode.list(position_decoder())), MultiLineString)
    "Polygon" -> coordinates(rings_decoder(), Polygon)
    "MultiPolygon" -> coordinates(decode.list(rings_decoder()), MultiPolygon)
    _ ->
      decode.field(
        "type",
        decode.failure(MultiPoint([]), geometry_types),
        decode.success,
      )
  }
}

fn coordinates(
  decoder: Decoder(a),
  to_geometry: fn(a) -> Geometry,
) -> Decoder(Geometry) {
  use value <- decode.field("coordinates", decoder)
  decode.success(to_geometry(value))
}

// A polygon is one or more linear rings: closed, with at least four
// positions (RFC 7946 section 3.1.6).
fn rings_decoder() -> Decoder(List(List(LatLng))) {
  use rings <- decode.then(decode.list(ring_decoder()))
  use <- bool.guard(when: rings != [], return: decode.success(rings))
  decode.failure([], "Polygon with at least one linear ring")
}

fn ring_decoder() -> Decoder(List(LatLng)) {
  use ring <- decode.then(decode.list(position_decoder()))
  case ring, list.last(ring) {
    [first, _, _, _, ..], Ok(last) if first == last -> decode.success(ring)
    [_, _, _, _, ..], _ ->
      decode.failure(ring, "closed linear ring (first position equal to last)")
    _, _ -> decode.failure(ring, "linear ring with at least 4 positions")
  }
}

fn position_decoder() -> Decoder(LatLng) {
  use numbers <- decode.then(decode.list(number_decoder()))
  let origin = geokit.wrap_lat_lng(latitude: 0.0, longitude: 0.0)
  case numbers {
    [longitude, latitude] | [longitude, latitude, _] ->
      case geokit.lat_lng(latitude:, longitude:) {
        Ok(point) -> decode.success(point)
        Error(geokit.LatitudeOutOfRange(_)) ->
          decode.failure(origin, "latitude in [-90, 90]")
        Error(geokit.LongitudeOutOfRange(_)) ->
          decode.failure(origin, "longitude in [-180, 180]")
      }
    _ -> decode.failure(origin, "position of 2 or 3 numbers")
  }
}

// JSON has a single number type; `1` and `1.0` are the same coordinate.
// The Erlang JSON parser yields an Int for `1`, so accept both. A huge
// integer stays a bignum on Erlang and `int.to_float` would raise on
// it, so integers beyond `max_integer_coordinate` are a decode failure;
// coordinates are degrees, so no valid position comes near the bound.
fn number_decoder() -> Decoder(Float) {
  decode.one_of(decode.float, [
    {
      use value <- decode.then(decode.int)
      case int.absolute_value(value) <= max_integer_coordinate {
        True -> decode.success(int.to_float(value))
        False -> decode.failure(0.0, "Float")
      }
    },
  ])
}

const max_integer_coordinate: Int = 1_000_000_000

/// Returns a decoder for a GeoJSON feature object, decoding its
/// properties with `properties`. A `null` geometry decodes to `None` and
/// a missing or `null` id to `None`.
///
/// ## Examples
///
/// ```gleam
/// json.parse(
///   "{\"type\":\"Feature\",\"geometry\":null,\"properties\":{\"name\":\"Tokyo\"},\"id\":1}",
///   feature_decoder(properties: decode.at(["name"], decode.string)),
/// )
/// // -> Ok(Feature(geometry: None, properties: "Tokyo", id: Some(IntId(1))))
/// ```
///
/// ```gleam
/// json.parse(
///   "{\"type\":\"Point\",\"coordinates\":[0,0]}",
///   feature_decoder(properties: decode.dynamic),
/// )
/// |> result.is_error
/// // -> True
/// ```
///
/// ## Target specific behavior
///
/// On JavaScript a number id with no fractional part, such as `1.0`,
/// decodes to `IntId`. On Erlang `1.0` decodes to `FloatId(1.0)`.
pub fn feature_decoder(
  properties properties: Decoder(p),
) -> Decoder(Feature(p)) {
  use _ <- decode.field("type", constant("Feature"))
  use geometry <- decode.field("geometry", decode.optional(geometry_decoder()))
  use properties <- decode.field("properties", properties)
  use id <- decode.optional_field("id", None, decode.optional(id_decoder()))
  decode.success(Feature(geometry:, properties:, id:))
}

fn id_decoder() -> Decoder(FeatureId) {
  decode.one_of(decode.map(decode.string, StringId), [
    decode.map(decode.int, IntId),
    decode.map(decode.float, FloatId),
  ])
}

/// Returns a decoder for a GeoJSON feature collection object, decoding
/// each feature's properties with `properties`.
///
/// ## Examples
///
/// ```gleam
/// json.parse(
///   "{\"type\":\"FeatureCollection\",\"features\":[]}",
///   feature_collection_decoder(properties: decode.dynamic),
/// )
/// // -> Ok([])
/// ```
///
/// ```gleam
/// json.parse(
///   "{\"type\":\"Feature\",\"features\":[]}",
///   feature_collection_decoder(properties: decode.dynamic),
/// )
/// // -> Error(json.UnableToDecode([decode.DecodeError(
/// //   expected: "FeatureCollection",
/// //   found: "String",
/// //   path: ["type"],
/// // )]))
/// ```
pub fn feature_collection_decoder(
  properties properties: Decoder(p),
) -> Decoder(List(Feature(p))) {
  use _ <- decode.field("type", constant("FeatureCollection"))
  use features <- decode.field(
    "features",
    decode.list(feature_decoder(properties:)),
  )
  decode.success(features)
}

// Succeeds on the string `expected` only.
fn constant(expected: String) -> Decoder(Nil) {
  use value <- decode.then(decode.string)
  use <- bool.guard(when: value == expected, return: decode.success(Nil))
  decode.failure(Nil, expected)
}
