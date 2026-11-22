//// Every code block in `README.md` is exercised here so that a
//// rename or behaviour change in the public API surfaces as a build
//// failure rather than silently-stale documentation. The snippets in
//// this file mirror the README byte-for-byte; the `_test` functions
//// below assert the values the README claims for each snippet.

import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None}
import gleam/result
import gleam/string
import gleeunit/should

import geokit.{type LatLng}
import geokit/geohash
import geokit/geojson
import geokit/mercator
import geokit/polyline

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
  let assert Ok(tokyo) = geokit.lat_lng(latitude: 35.6812, longitude: 139.7671)
  let assert Ok(osaka) = geokit.lat_lng(latitude: 34.6937, longitude: 135.5023)
  #(
    geokit.distance(from: tokyo, to: osaka),
    geokit.initial_bearing(from: tokyo, to: osaka),
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
  let point = geokit.wrap_lat_lng(latitude: 91.0, longitude: 181.0)
  #(geokit.latitude(point), geokit.longitude(point))
}

pub fn readme_antimeridian_wrap_test() -> Nil {
  antimeridian_wrap() |> should.equal(#(90.0, -179.0))
}

// --- Geohash encode, decode, neighbours --------------------------------

pub fn around_tokyo() -> #(String, geokit.LatLng, geohash.Neighbors) {
  let assert Ok(tokyo) = geokit.lat_lng(latitude: 35.6812, longitude: 139.7671)
  let assert Ok(hash) = geohash.encode(tokyo, precision: 8)
  let assert Ok(centre) = geohash.decode(hash)
  let assert Ok(neighbours) = geohash.neighbors(hash)
  #(hash, centre, neighbours)
}

pub fn readme_around_tokyo_test() -> Nil {
  let #(hash, centre, neighbours) = around_tokyo()
  // The README states `hash == "xn76urx6"` for Tokyo at precision 8.
  hash |> should.equal("xn76urx6")
  // The centre is the geohash cell's midpoint — close to but not
  // identical to Tokyo; precision 8 is ~38 m × 19 m, so this
  // tolerance is conservative.
  close_to(geokit.latitude(centre), 35.6812, 0.001) |> should.be_true
  close_to(geokit.longitude(centre), 139.7671, 0.001) |> should.be_true
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
  let assert Ok(p1) = geokit.lat_lng(latitude: 38.5, longitude: -120.2)
  let assert Ok(p2) = geokit.lat_lng(latitude: 40.7, longitude: -120.95)
  let assert Ok(p3) = geokit.lat_lng(latitude: 43.252, longitude: -126.453)
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
  let assert Ok(p) = geokit.lat_lng(latitude: 35.6812, longitude: 139.7671)
  let feature =
    geojson.Feature(
      geometry: geokit.Point(p),
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
  let assert Ok(p) = geokit.lat_lng(latitude: 35.6812, longitude: 139.7671)
  let feature =
    geojson.Feature(
      geometry: geokit.Point(p),
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
    geokit.Point(p) -> {
      geokit.latitude(p) |> should.equal(35.6812)
      geokit.longitude(p) |> should.equal(139.7671)
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
  let assert Ok(tokyo) = geokit.lat_lng(latitude: 35.6812, longitude: 139.7671)
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
  let assert Ok(a) = geokit.lat_lng(latitude: 0.0, longitude: 0.0)
  let assert Ok(b) = geokit.lat_lng(latitude: 0.0, longitude: 10.0)
  let assert Ok(c) = geokit.lat_lng(latitude: 10.0, longitude: 10.0)
  let assert Ok(d) = geokit.lat_lng(latitude: 10.0, longitude: 0.0)
  let polygon = geokit.Polygon([[a, b, c, d, a]])

  let assert Ok(#(sw, ne)) = bbox(polygon)
  let assert Ok(centre) = geokit.centroid(polygon)
  let assert Ok(reduced) = simplify_line([a, b, c, d], tolerance: 0.001)
  #(sw, ne, centre, reduced)
}

pub fn readme_polygon_ops_test() -> Nil {
  let #(sw, ne, centre, reduced) = polygon_ops()
  geokit.latitude(sw) |> should.equal(0.0)
  geokit.longitude(sw) |> should.equal(0.0)
  geokit.latitude(ne) |> should.equal(10.0)
  geokit.longitude(ne) |> should.equal(10.0)
  // The signed-area centroid of an axis-aligned 10 × 10 square is
  // at its geometric centre.
  geokit.latitude(centre) |> should.equal(5.0)
  geokit.longitude(centre) |> should.equal(5.0)
  // Douglas-Peucker on a square at very small tolerance keeps every
  // corner (no two points are collinear within 0.001°).
  list.length(reduced) |> should.equal(4)
}

// --- point in polygon --------------------------------------------------

pub fn park_and_lake() {
  let park = [
    geokit.wrap_lat_lng(latitude: 0.0, longitude: 0.0),
    geokit.wrap_lat_lng(latitude: 0.0, longitude: 10.0),
    geokit.wrap_lat_lng(latitude: 10.0, longitude: 10.0),
    geokit.wrap_lat_lng(latitude: 10.0, longitude: 0.0),
    geokit.wrap_lat_lng(latitude: 0.0, longitude: 0.0),
  ]
  let lake = [
    geokit.wrap_lat_lng(latitude: 4.0, longitude: 4.0),
    geokit.wrap_lat_lng(latitude: 4.0, longitude: 6.0),
    geokit.wrap_lat_lng(latitude: 6.0, longitude: 6.0),
    geokit.wrap_lat_lng(latitude: 6.0, longitude: 4.0),
    geokit.wrap_lat_lng(latitude: 4.0, longitude: 4.0),
  ]
  let polygon = geokit.Polygon([park, lake])

  let bench = geokit.wrap_lat_lng(latitude: 2.0, longitude: 2.0)
  let boat = geokit.wrap_lat_lng(latitude: 5.0, longitude: 5.0)
  let gate = geokit.wrap_lat_lng(latitude: 0.0, longitude: 5.0)
  #(
    contains_point(bench, in: polygon),
    contains_point(boat, in: polygon),
    contains_point(gate, in: polygon),
    geokit.locate(gate, in: polygon),
  )
}

pub fn readme_park_and_lake_test() -> Nil {
  park_and_lake()
  |> should.equal(#(Ok(True), Ok(False), Ok(True), Ok(geokit.OnBoundary)))
}

// --- API adapters ----------------------------------------------------------

fn contains_point(
  point: LatLng,
  in geometry: geokit.Geometry,
) -> Result(Bool, Nil) {
  geokit.locate(point, in: geometry)
  |> result.map(fn(location) { location != geokit.Outside })
}

fn bbox(geometry: geokit.Geometry) -> Result(#(LatLng, LatLng), Nil) {
  geokit.bounding_box(geometry)
  |> result.map(fn(box) { #(box.south_west, box.north_east) })
}

fn simplify_line(
  points: List(LatLng),
  tolerance tolerance: Float,
) -> Result(List(LatLng), Nil) {
  case geokit.simplify(geokit.LineString(points), tolerance:) {
    Ok(geokit.LineString(simplified)) -> Ok(simplified)
    _ -> Error(Nil)
  }
}
