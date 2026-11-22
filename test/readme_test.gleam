//// Mirrors the code blocks in README.md and checks the values they
//// claim. Keep the function bodies identical to the README.

import geokit
import geokit/geohash
import geokit/geojson
import geokit/polyline
import geokit/tile
import gleam/float
import gleam/json

pub fn tokyo_to_osaka() -> #(Float, Float) {
  let assert Ok(tokyo) = geokit.lat_lng(latitude: 35.6812, longitude: 139.7671)
  let assert Ok(osaka) = geokit.lat_lng(latitude: 34.6937, longitude: 135.5023)
  #(
    geokit.distance(from: tokyo, to: osaka),
    geokit.initial_bearing(from: tokyo, to: osaka),
  )
}

pub fn inside_park(input: String) -> Result(geokit.Location, Nil) {
  let assert Ok(park) = json.parse(input, geojson.geometry_decoder())
  let bench = geokit.wrap_lat_lng(latitude: 2.0, longitude: 2.0)
  geokit.locate(bench, in: park)
}

pub fn encodings() -> #(String, String, String) {
  let assert Ok(tokyo) = geokit.lat_lng(latitude: 35.6812, longitude: 139.7671)
  let assert Ok(osaka) = geokit.lat_lng(latitude: 34.6937, longitude: 135.5023)
  let assert Ok(hash) = geohash.encode(tokyo, precision: 8)
  let assert Ok(route) = polyline.encode([tokyo, osaka], precision: 5)
  let assert Ok(tokyo_tile) = tile.from_lat_lng(tokyo, zoom: 5)
  #(hash, route, tile.to_quadkey(tokyo_tile))
}

pub fn readme_tokyo_to_osaka_test() {
  let #(meters, degrees) = tokyo_to_osaka()
  assert float.to_precision(meters, 2) == 402_784.74
  assert float.to_precision(degrees, 2) == 255.42
}

pub fn readme_inside_park_test() {
  let input =
    "{\"type\":\"Polygon\",\"coordinates\":[[[0,0],[10,0],[10,10],[0,10],[0,0]]]}"
  assert inside_park(input) == Ok(geokit.Inside)
}

pub fn readme_encodings_test() {
  let #(hash, route, quadkey) = encodings()
  assert hash == "xn76urx6"
  assert route == "o~wxEkgatYzz_E~}_Y"
  assert quadkey == "13300"
}
