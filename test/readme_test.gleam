//// Every code block in `README.md` is exercised here so that a
//// rename or behaviour change in the public API surfaces as a build
//// failure rather than silently-stale documentation. The snippets in
//// this file mirror the README byte-for-byte; the `_test` functions
//// below assert the values the README claims for each snippet.

import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None}
import gleam/string
import gleeunit/should

import geokit/bbox
import geokit/bearing
import geokit/centroid
import geokit/distance
import geokit/geohash
import geokit/geojson
import geokit/geometry
import geokit/latlng
import geokit/mercator
import geokit/polyline
import geokit/simplify

// --- helpers -------------------------------------------------------------

fn close_to(actual: Float, expected: Float, tolerance: Float) -> Bool {
  let diff = case actual >. expected {
    True -> actual -. expected
    False -> expected -. actual
  }
  diff <=. tolerance
}

// --- Haversine distance and initial bearing -----------------------------

pub fn tokyo_to_osaka() -> #(Float, Float) {
  let assert Ok(tokyo) = latlng.new(lat: 35.6812, lng: 139.7671)
  let assert Ok(osaka) = latlng.new(lat: 34.6937, lng: 135.5023)
  #(
    distance.haversine(a: tokyo, b: osaka),
    bearing.initial(from: tokyo, to: osaka),
  )
}

pub fn readme_tokyo_to_osaka_test() -> Nil {
  let #(metres, deg) = tokyo_to_osaka()
  // The README claims ≈ 402_784.74 m and ≈ 255.42°.
  close_to(metres, 402_784.74, 0.01) |> should.be_true
  close_to(deg, 255.42, 0.01) |> should.be_true
}

// --- latlng.wrap normalisation -----------------------------------------

pub fn antimeridian_wrap() -> #(Float, Float) {
  let point = latlng.wrap(lat: 91.0, lng: 181.0)
  #(latlng.lat(point), latlng.lng(point))
}

pub fn readme_antimeridian_wrap_test() -> Nil {
  antimeridian_wrap() |> should.equal(#(90.0, -179.0))
}

// --- Geohash encode, decode, neighbours --------------------------------

pub fn around_tokyo() -> #(String, latlng.LatLng, geohash.Neighbors) {
  let assert Ok(tokyo) = latlng.new(lat: 35.6812, lng: 139.7671)
  let assert Ok(hash) = geohash.encode(point: tokyo, precision: 8)
  let assert Ok(centre) = geohash.decode(hash: hash)
  let assert Ok(neighbours) = geohash.neighbors(hash: hash)
  #(hash, centre, neighbours)
}

pub fn readme_around_tokyo_test() -> Nil {
  let #(hash, centre, neighbours) = around_tokyo()
  // The README states `hash == "xn76urx6"` for Tokyo at precision 8.
  hash |> should.equal("xn76urx6")
  // The centre is the geohash cell's midpoint — close to but not
  // identical to Tokyo; precision 8 is ~38 m × 19 m, so this
  // tolerance is conservative.
  close_to(latlng.lat(centre), 35.6812, 0.001) |> should.be_true
  close_to(latlng.lng(centre), 139.7671, 0.001) |> should.be_true
  // The README claims `neighbors` returns all eight directions.
  // Each direction must yield a hash of the same length.
  let prec = 8
  { neighbours.north |> string_length_check(prec) } |> should.be_true
  { neighbours.east |> string_length_check(prec) } |> should.be_true
  { neighbours.south |> string_length_check(prec) } |> should.be_true
  { neighbours.west |> string_length_check(prec) } |> should.be_true
}

fn string_length_check(s: String, target: Int) -> Bool {
  string.length(s) == target
}

// --- Polyline encode + decode ------------------------------------------

pub fn route() -> #(String, Int) {
  let assert Ok(p1) = latlng.new(lat: 38.5, lng: -120.2)
  let assert Ok(p2) = latlng.new(lat: 40.7, lng: -120.95)
  let assert Ok(p3) = latlng.new(lat: 43.252, lng: -126.453)
  let encoded = polyline.encode(points: [p1, p2, p3])
  let assert Ok(decoded) = polyline.decode(input: encoded)
  #(encoded, list.length(decoded))
}

pub fn readme_route_test() -> Nil {
  let #(encoded, count) = route()
  // The README claims Google's reference output.
  encoded |> should.equal("_p~iF~ps|U_ulLnnqC_mqNvxq`@")
  count |> should.equal(3)
}

// --- GeoJSON Feature round-trip with typed properties ----------------

type City {
  City(name: String, population: Int)
}

fn city_to_json(c: City) -> json.Json {
  json.object([
    #("name", json.string(c.name)),
    #("population", json.int(c.population)),
  ])
}

fn city_decoder() -> decode.Decoder(City) {
  use name <- decode.field("name", decode.string)
  use population <- decode.field("population", decode.int)
  decode.success(City(name: name, population: population))
}

// Mirror of the README snippet. The body matches byte-for-byte; the
// `Nil` return is intentional so the snippet stays readable in the
// docs.
pub fn round_trip() -> Nil {
  let assert Ok(p) = latlng.new(lat: 35.6812, lng: 139.7671)
  let feature =
    geojson.Feature(
      geometry: geometry.Point(p),
      properties: City(name: "Tokyo", population: 13_960_000),
      id: None,
    )
  let encoded =
    geojson.encode_feature(feature: feature, properties: city_to_json)
  let assert Ok(_decoded) =
    geojson.decode_feature(input: encoded, properties: city_decoder())
  Nil
}

// Internal variant returning the decoded value so the test can
// inspect it. Not exported; not part of the README.
fn round_trip_inspect() -> geojson.Feature(City) {
  let assert Ok(p) = latlng.new(lat: 35.6812, lng: 139.7671)
  let feature =
    geojson.Feature(
      geometry: geometry.Point(p),
      properties: City(name: "Tokyo", population: 13_960_000),
      id: None,
    )
  let encoded =
    geojson.encode_feature(feature: feature, properties: city_to_json)
  let assert Ok(decoded) =
    geojson.decode_feature(input: encoded, properties: city_decoder())
  decoded
}

pub fn readme_geojson_round_trip_test() -> Nil {
  // Running the README mirror must not panic.
  round_trip()
  // Inspect the actual decoded value via the test-only helper.
  let f = round_trip_inspect()
  f.properties |> should.equal(City("Tokyo", 13_960_000))
  case f.geometry {
    geometry.Point(p) -> {
      latlng.lat(p) |> should.equal(35.6812)
      latlng.lng(p) |> should.equal(139.7671)
    }
    _ -> should.be_true(False)
  }
}

// --- GeoJSON FeatureCollection decoding --------------------------------

pub fn parse_collection(input: String) -> Int {
  let assert Ok(features) =
    geojson.decode_feature_collection(input: input, properties: decode.dynamic)
  list.length(features)
}

pub fn readme_parse_collection_test() -> Nil {
  let input =
    "{\"type\":\"FeatureCollection\",\"features\":[{\"type\":\"Feature\",\"geometry\":{\"type\":\"Point\",\"coordinates\":[139.7671,35.6812]},\"properties\":{\"name\":\"Tokyo\"}}]}"
  parse_collection(input) |> should.equal(1)
}

// --- Web Mercator tile and Bing quadkey -------------------------------

pub fn tokyo_tile_at_zoom_5() -> #(Int, Int, String) {
  let assert Ok(tokyo) = latlng.new(lat: 35.6812, lng: 139.7671)
  let assert Ok(tile) = mercator.from_lat_lng(point: tokyo, zoom: 5)
  #(
    mercator.x(tile: tile),
    mercator.y(tile: tile),
    mercator.to_quadkey(tile: tile),
  )
}

pub fn readme_tokyo_tile_at_zoom_5_test() -> Nil {
  // OSM slippy-map tile (28, 12) at z=5 covers Tokyo. Bing quadkey
  // "13300" is the corresponding interleaved representation.
  tokyo_tile_at_zoom_5() |> should.equal(#(28, 12, "13300"))
}

// --- bbox / centroid / simplify ----------------------------------------

pub fn polygon_ops() {
  let assert Ok(a) = latlng.new(lat: 0.0, lng: 0.0)
  let assert Ok(b) = latlng.new(lat: 0.0, lng: 10.0)
  let assert Ok(c) = latlng.new(lat: 10.0, lng: 10.0)
  let assert Ok(d) = latlng.new(lat: 10.0, lng: 0.0)
  let polygon = geometry.Polygon([[a, b, c, d, a]])

  let assert Ok(#(sw, ne)) = bbox.compute(geometry: polygon)
  let assert Ok(centre) = centroid.compute(geometry: polygon)
  let assert Ok(reduced) =
    simplify.line_string(points: [a, b, c, d], tolerance: 0.001)
  #(sw, ne, centre, reduced)
}

pub fn readme_polygon_ops_test() -> Nil {
  let #(sw, ne, centre, reduced) = polygon_ops()
  latlng.lat(sw) |> should.equal(0.0)
  latlng.lng(sw) |> should.equal(0.0)
  latlng.lat(ne) |> should.equal(10.0)
  latlng.lng(ne) |> should.equal(10.0)
  // The signed-area centroid of an axis-aligned 10 × 10 square is
  // at its geometric centre.
  latlng.lat(centre) |> should.equal(5.0)
  latlng.lng(centre) |> should.equal(5.0)
  // Douglas-Peucker on a square at very small tolerance keeps every
  // corner (no two points are collinear within 0.001°).
  list.length(reduced) |> should.equal(4)
}
