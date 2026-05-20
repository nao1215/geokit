//// GeoJSON (RFC 7946) encode / decode.
////
//// Maps geokit's [`Geometry`](../geometry.html) ADT to and from the
//// JSON shapes defined in RFC 7946:
////
//// - `Point` / `MultiPoint` / `LineString` / `Polygon` /
////   `MultiPolygon` round-trip through this module.
//// - `MultiLineString` and `GeometryCollection` are valid GeoJSON
////   types but are not currently representable in `Geometry`;
////   decoding returns [`UnsupportedType`](#GeoJsonError).
////
//// Coordinate order in GeoJSON is `[longitude, latitude]`, opposite
//// of the `lat: ..., lng: ...` constructors elsewhere in geokit.
//// The encoder and decoder handle the swap so callers never see the
//// reversed order. Altitude (a third coordinate) is accepted on
//// decode but discarded.
////
//// Properties on [`Feature`](#Feature) and `FeatureCollection` are
//// user-typed: pass a `Json` builder when encoding and a
//// `decode.Decoder` when decoding. Use `gleam/dynamic/decode.dynamic`
//// and `gleam/json.null()` if you don't care about properties.

import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

import geokit/geometry.{type Geometry}
import geokit/latlng.{type LatLng}

// --- Public types --------------------------------------------------------

/// Errors returned by the decoders.
pub type GeoJsonError {
  /// The input was not valid JSON.
  InvalidJson(reason: String)
  /// The input was valid JSON but the structure did not match the
  /// expected GeoJSON shape (missing field, wrong field type, ...).
  InvalidStructure(reason: String)
  /// The `type` field carried a string that is not a known GeoJSON
  /// geometry or container type.
  UnknownType(type_: String)
  /// The `type` is a valid GeoJSON type but cannot be represented in
  /// geokit's `Geometry` ADT (`MultiLineString`, `GeometryCollection`).
  UnsupportedType(type_: String)
  /// A coordinate array did not have the expected shape — fewer than
  /// two elements, or non-numeric entries.
  InvalidPosition(coords: List(Float))
  /// A coordinate pair was structurally valid but the values fell
  /// outside the documented domain of `latlng.new`.
  InvalidLatLng(error: latlng.LatLngError)
  /// A Polygon (or `MultiPolygon` sub-polygon) failed an RFC 7946
  /// §3.1.6 invariant. The accompanying `reason` names the specific
  /// violation: a Polygon with no rings, a ring with fewer than four
  /// positions, or a ring whose first position is not equal to its
  /// last.
  InvalidPolygon(reason: String)
}

/// A GeoJSON `id` value. RFC 7946 §3.2 allows either a JSON string
/// or a JSON number; this type captures both losslessly.
pub type FeatureId {
  StringId(value: String)
  IntId(value: Int)
}

/// A GeoJSON Feature. Properties are user-typed: the type parameter
/// `properties` is whatever your application chooses (often a record
/// type, sometimes a `dict.Dict(String, dynamic.Dynamic)` for fully
/// dynamic payloads).
pub type Feature(properties) {
  Feature(geometry: Geometry, properties: properties, id: Option(FeatureId))
}

// --- Encoding ------------------------------------------------------------

/// Encode a `Geometry` as a GeoJSON string. The result is a compact
/// JSON document with no whitespace.
///
/// ```gleam
/// import geokit/geojson
/// import geokit/geometry
/// import geokit/latlng
///
/// let assert Ok(p) = latlng.new(lat: 35.0, lng: 139.0)
/// geojson.encode_geometry(geometry: geometry.Point(p))
/// // == "{\"type\":\"Point\",\"coordinates\":[139.0,35.0]}"
/// ```
pub fn encode_geometry(geometry geometry: Geometry) -> String {
  geometry |> geometry_to_json |> json.to_string
}

/// Encode a `Feature` as a GeoJSON string. Pass a function that turns
/// your properties type into a `Json` value.
pub fn encode_feature(
  feature feature: Feature(p),
  properties to_json: fn(p) -> Json,
) -> String {
  feature |> feature_to_json(to_json) |> json.to_string
}

/// Encode a list of features as a GeoJSON `FeatureCollection`.
pub fn encode_feature_collection(
  features features: List(Feature(p)),
  properties to_json: fn(p) -> Json,
) -> String {
  let entries = [
    #("type", json.string("FeatureCollection")),
    #(
      "features",
      json.preprocessed_array(
        list.map(features, fn(f) { feature_to_json(f, to_json) }),
      ),
    ),
  ]
  json.object(entries) |> json.to_string
}

// --- Decoding ------------------------------------------------------------

/// Decode a GeoJSON geometry string back to a `Geometry`.
pub fn decode_geometry(input input: String) -> Result(Geometry, GeoJsonError) {
  parse_with(input, geometry_decoder())
}

/// Decode a GeoJSON Feature. Pass a decoder for your properties type.
/// To accept any shape, pass `decode.dynamic`.
pub fn decode_feature(
  input input: String,
  properties properties: Decoder(p),
) -> Result(Feature(p), GeoJsonError) {
  parse_with(input, feature_decoder(properties))
}

/// Decode a GeoJSON FeatureCollection into a list of features.
pub fn decode_feature_collection(
  input input: String,
  properties properties: Decoder(p),
) -> Result(List(Feature(p)), GeoJsonError) {
  parse_with(input, feature_collection_decoder(properties))
}

// --- Geometry → JSON -----------------------------------------------------

fn geometry_to_json(g: Geometry) -> Json {
  case g {
    geometry.Point(p) -> object_with_coords("Point", position_to_json(p))
    geometry.MultiPoint(points) ->
      object_with_coords(
        "MultiPoint",
        json.preprocessed_array(list.map(points, position_to_json)),
      )
    geometry.LineString(points) ->
      object_with_coords(
        "LineString",
        json.preprocessed_array(list.map(points, position_to_json)),
      )
    geometry.Polygon(rings) ->
      object_with_coords("Polygon", rings_to_json(rings))
    geometry.MultiPolygon(polygons) ->
      object_with_coords(
        "MultiPolygon",
        json.preprocessed_array(list.map(polygons, rings_to_json)),
      )
  }
}

fn rings_to_json(rings: List(List(LatLng))) -> Json {
  json.preprocessed_array(
    list.map(rings, fn(ring) {
      json.preprocessed_array(list.map(ring, position_to_json))
    }),
  )
}

fn position_to_json(p: LatLng) -> Json {
  // GeoJSON order: [longitude, latitude].
  json.preprocessed_array([
    json.float(latlng.lng(p)),
    json.float(latlng.lat(p)),
  ])
}

fn object_with_coords(type_name: String, coordinates: Json) -> Json {
  json.object([
    #("type", json.string(type_name)),
    #("coordinates", coordinates),
  ])
}

// --- Feature → JSON ------------------------------------------------------

fn feature_to_json(feature: Feature(p), to_json: fn(p) -> Json) -> Json {
  let base = [
    #("type", json.string("Feature")),
    #("geometry", geometry_to_json(feature.geometry)),
    #("properties", to_json(feature.properties)),
  ]
  let entries = case feature.id {
    None -> base
    Some(id) -> list.append(base, [#("id", id_to_json(id))])
  }
  json.object(entries)
}

fn id_to_json(id: FeatureId) -> Json {
  case id {
    StringId(value: value) -> json.string(value)
    IntId(value: value) -> json.int(value)
  }
}

// --- JSON → Geometry (decoder pipeline) ----------------------------------

fn parse_with(
  input: String,
  decoder: Decoder(Result(t, GeoJsonError)),
) -> Result(t, GeoJsonError) {
  case json.parse(from: input, using: decoder) {
    Error(err) -> Error(json_error_to_geojson(err))
    Ok(Ok(value)) -> Ok(value)
    Ok(Error(geojson_err)) -> Error(geojson_err)
  }
}

fn json_error_to_geojson(err: json.DecodeError) -> GeoJsonError {
  case err {
    json.UnexpectedEndOfInput -> InvalidJson("unexpected end of input")
    json.UnexpectedByte(byte) -> InvalidJson("unexpected byte: " <> byte)
    json.UnexpectedSequence(seq) -> InvalidJson("unexpected sequence: " <> seq)
    json.UnableToDecode(errors) ->
      InvalidStructure(decode_errors_to_reason(errors))
  }
}

/// Project a `decode.DecodeError` list into a single, human-actionable
/// reason string. The previous implementation collapsed every shape
/// mismatch into the opaque `"JSON shape did not match expected
/// GeoJSON"` regardless of the underlying cause. Now the reason
/// names the failing path, the expected type, and the value that
/// was actually found so a caller routing on the reason string can
/// triage a 400 response without re-parsing the JSON.
fn decode_errors_to_reason(errors: List(decode.DecodeError)) -> String {
  case errors {
    [] -> "JSON shape did not match expected GeoJSON"
    [first, ..] -> decode_error_to_reason(first)
  }
}

fn decode_error_to_reason(err: decode.DecodeError) -> String {
  let path = case err.path {
    [] -> "<root>"
    _ -> string.join(err.path, ".")
  }
  "at " <> path <> ": expected " <> err.expected <> ", got " <> err.found
}

fn geometry_decoder() -> Decoder(Result(Geometry, GeoJsonError)) {
  use type_ <- decode.field("type", decode.string)
  case type_ {
    "Point" -> {
      use coords <- decode.field("coordinates", decode.list(decode.float))
      decode.success(raw_point_to_geometry(coords))
    }
    "MultiPoint" -> {
      use coords <- decode.field(
        "coordinates",
        decode.list(decode.list(decode.float)),
      )
      decode.success(raw_multi_point_to_geometry(coords))
    }
    "LineString" -> {
      use coords <- decode.field(
        "coordinates",
        decode.list(decode.list(decode.float)),
      )
      decode.success(raw_line_string_to_geometry(coords))
    }
    "Polygon" -> {
      use coords <- decode.field(
        "coordinates",
        decode.list(decode.list(decode.list(decode.float))),
      )
      decode.success(raw_polygon_to_geometry(coords))
    }
    "MultiPolygon" -> {
      use coords <- decode.field(
        "coordinates",
        decode.list(decode.list(decode.list(decode.list(decode.float)))),
      )
      decode.success(raw_multi_polygon_to_geometry(coords))
    }
    "MultiLineString" | "GeometryCollection" ->
      decode.success(Error(UnsupportedType(type_)))
    other -> decode.success(Error(UnknownType(other)))
  }
}

fn raw_point_to_geometry(coords: List(Float)) -> Result(Geometry, GeoJsonError) {
  use point <- result.map(parse_position(coords))
  geometry.Point(point)
}

fn raw_line_string_to_geometry(
  coords: List(List(Float)),
) -> Result(Geometry, GeoJsonError) {
  use points <- result.map(list.try_map(coords, parse_position))
  geometry.LineString(points)
}

fn raw_multi_point_to_geometry(
  coords: List(List(Float)),
) -> Result(Geometry, GeoJsonError) {
  use points <- result.map(list.try_map(coords, parse_position))
  geometry.MultiPoint(points)
}

fn raw_polygon_to_geometry(
  coords: List(List(List(Float))),
) -> Result(Geometry, GeoJsonError) {
  use rings <- result.map(parse_rings(coords))
  geometry.Polygon(rings)
}

fn raw_multi_polygon_to_geometry(
  coords: List(List(List(List(Float)))),
) -> Result(Geometry, GeoJsonError) {
  use polygons <- result.map(list.try_map(coords, parse_rings))
  geometry.MultiPolygon(polygons)
}

fn parse_rings(
  raw: List(List(List(Float))),
) -> Result(List(List(LatLng)), GeoJsonError) {
  use _ <- result.try(check_polygon_has_ring(raw))
  use rings <- result.try(
    list.try_map(raw, fn(ring) { list.try_map(ring, parse_position) }),
  )
  use _ <- result.map(check_all_rings(rings))
  rings
}

fn check_all_rings(rings: List(List(LatLng))) -> Result(Nil, GeoJsonError) {
  case rings {
    [] -> Ok(Nil)
    [head, ..rest] ->
      case check_linear_ring(head) {
        Ok(Nil) -> check_all_rings(rest)
        Error(e) -> Error(e)
      }
  }
}

fn check_polygon_has_ring(
  raw: List(List(List(Float))),
) -> Result(Nil, GeoJsonError) {
  case raw {
    [] ->
      Error(InvalidPolygon(
        reason: "Polygon must contain at least one linear ring (RFC 7946 §3.1.6)",
      ))
    _ -> Ok(Nil)
  }
}

fn check_linear_ring(ring: List(LatLng)) -> Result(Nil, GeoJsonError) {
  case ring {
    [first, _, _, _, ..] ->
      case last_in_list(ring) {
        Ok(last) ->
          case
            latlng.lat(first) == latlng.lat(last)
            && latlng.lng(first) == latlng.lng(last)
          {
            True -> Ok(Nil)
            False ->
              Error(InvalidPolygon(
                reason: "linear ring must be closed: first position must equal last (RFC 7946 §3.1.6)",
              ))
          }
        Error(Nil) ->
          Error(InvalidPolygon(
            reason: "linear ring must have at least four positions (RFC 7946 §3.1.6)",
          ))
      }
    _ ->
      Error(InvalidPolygon(
        reason: "linear ring must have at least four positions (RFC 7946 §3.1.6)",
      ))
  }
}

fn last_in_list(items: List(a)) -> Result(a, Nil) {
  case items {
    [] -> Error(Nil)
    [only] -> Ok(only)
    [_, ..rest] -> last_in_list(rest)
  }
}

fn parse_position(coords: List(Float)) -> Result(LatLng, GeoJsonError) {
  case coords {
    [lng, lat] -> wrap_position(lng, lat)
    [lng, lat, _altitude] -> wrap_position(lng, lat)
    _ -> Error(InvalidPosition(coords))
  }
}

fn wrap_position(lng: Float, lat: Float) -> Result(LatLng, GeoJsonError) {
  case latlng.new(lat: lat, lng: lng) {
    Ok(p) -> Ok(p)
    Error(e) -> Error(InvalidLatLng(e))
  }
}

// --- JSON → Feature ------------------------------------------------------

fn feature_decoder(
  properties_decoder: Decoder(p),
) -> Decoder(Result(Feature(p), GeoJsonError)) {
  use type_ <- decode.field("type", decode.string)
  case type_ {
    "Feature" -> {
      use raw_geometry <- decode.field("geometry", geometry_decoder())
      use props <- decode.field("properties", properties_decoder)
      use id <- decode.optional_field("id", None, decode.optional(id_decoder()))
      decode.success(
        result.map(raw_geometry, fn(g) {
          Feature(geometry: g, properties: props, id: id)
        }),
      )
    }
    other -> {
      use _ <- decode.then(decode.success(Nil))
      decode.success(Error(UnknownType(other)))
    }
  }
}

fn id_decoder() -> Decoder(FeatureId) {
  decode.one_of(decode.map(decode.string, StringId), [
    decode.map(decode.int, IntId),
  ])
}

fn feature_collection_decoder(
  properties_decoder: Decoder(p),
) -> Decoder(Result(List(Feature(p)), GeoJsonError)) {
  use type_ <- decode.field("type", decode.string)
  case type_ {
    "FeatureCollection" -> {
      use features <- decode.field(
        "features",
        decode.list(feature_decoder(properties_decoder)),
      )
      decode.success(result.all(features))
    }
    other -> {
      use _ <- decode.then(decode.success(Nil))
      decode.success(Error(UnknownType(other)))
    }
  }
}
