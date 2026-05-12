# geokit

[![Package Version](https://img.shields.io/hexpm/v/geokit)](https://hex.pm/packages/geokit)
[![Downloads](https://img.shields.io/hexpm/dt/geokit)](https://hex.pm/packages/geokit)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/geokit/)
[![CI](https://github.com/nao1215/geokit/actions/workflows/ci.yml/badge.svg)](https://github.com/nao1215/geokit/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/nao1215/geokit)](LICENSE)

Spherical-earth math, location encodings, and geometry operations for
Gleam. Runs on the Erlang and JavaScript targets.

```sh
gleam add geokit
```

## Usage

Haversine distance and initial bearing:

```gleam
import geokit/bearing
import geokit/distance
import geokit/latlng

pub fn tokyo_to_osaka() -> #(Float, Float) {
  let assert Ok(tokyo) = latlng.new(lat: 35.6812, lng: 139.7671)
  let assert Ok(osaka) = latlng.new(lat: 34.6937, lng: 135.5023)
  #(
    distance.haversine(a: tokyo, b: osaka),
    // ≈ 402_784.74 m
    bearing.initial(from: tokyo, to: osaka),
    // ≈ 255.42°
  )
}
```

Normalising denormalised coordinates with `latlng.wrap`:

```gleam
import geokit/latlng

pub fn antimeridian_wrap() -> #(Float, Float) {
  // A reading 1° past the antimeridian wraps to the western
  // hemisphere; latitudes above 90° are clamped to the pole.
  let point = latlng.wrap(lat: 91.0, lng: 181.0)
  #(latlng.lat(point), latlng.lng(point))
  // == #(90.0, -179.0)
}
```

Geohash encode, decode, and neighbour lookup:

```gleam
import geokit/geohash
import geokit/latlng

pub fn around_tokyo() -> Nil {
  let assert Ok(tokyo) = latlng.new(lat: 35.6812, lng: 139.7671)
  let assert Ok(hash) = geohash.encode(point: tokyo, precision: 8)
  // hash == "xn76urx6"

  let assert Ok(centre) = geohash.decode(hash: hash)
  // centre ≈ tokyo (within the cell's precision)

  let assert Ok(neighbours) = geohash.neighbors(hash: hash)
  // neighbours.north, neighbours.east, ... eight directions
  Nil
}
```

Google Encoded Polyline:

```gleam
import geokit/latlng
import geokit/polyline

pub fn route() -> Nil {
  let assert Ok(p1) = latlng.new(lat: 38.5, lng: -120.2)
  let assert Ok(p2) = latlng.new(lat: 40.7, lng: -120.95)
  let assert Ok(p3) = latlng.new(lat: 43.252, lng: -126.453)

  let encoded = polyline.encode(points: [p1, p2, p3])
  // encoded == "_p~iF~ps|U_ulLnnqC_mqNvxq`@"

  let assert Ok(_decoded) = polyline.decode(input: encoded)
  Nil
}
```

GeoJSON encode and decode (RFC 7946) — Feature with typed properties:

```gleam
import gleam/dynamic/decode
import gleam/json
import gleam/option.{None}

import geokit/geojson
import geokit/geometry
import geokit/latlng

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
```

Decoding a `FeatureCollection` from an external source — pass
`decode.dynamic` when you don't care about typed properties:

```gleam
import gleam/dynamic/decode
import gleam/list

import geokit/geojson

pub fn parse_collection(input: String) -> Int {
  let assert Ok(features) =
    geojson.decode_feature_collection(
      input: input,
      properties: decode.dynamic,
    )
  list.length(features)
}
```

Web Mercator tile and Bing quadkey:

```gleam
import geokit/latlng
import geokit/mercator

pub fn tokyo_tile_at_zoom_5() -> #(Int, Int, String) {
  let assert Ok(tokyo) = latlng.new(lat: 35.6812, lng: 139.7671)
  let assert Ok(tile) = mercator.from_lat_lng(point: tokyo, zoom: 5)
  #(
    mercator.x(tile: tile),
    mercator.y(tile: tile),
    mercator.to_quadkey(tile: tile),
  )
}
```

Bounding box, centroid, line simplification:

```gleam
import geokit/bbox
import geokit/centroid
import geokit/geometry
import geokit/latlng
import geokit/simplify

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
```

Full API reference: <https://hexdocs.pm/geokit/>.

## Notes

- Latitudes are in degrees in `[-90, 90]`; longitudes in degrees in
  `[-180, 180]`. The opaque `LatLng` type enforces this at
  construction; use `latlng.wrap` when your source data may be
  denormalised.
- Distance and bearing use the spherical-earth approximation with the
  WGS84 mean radius of 6_371_008.8 m. The error against an
  ellipsoidal (Vincenty) distance is bounded by 0.5 % anywhere on
  Earth.
- All polygon and line operations treat the lat/lng plane as flat — no
  projection is applied. For polygons spanning more than a few
  degrees, project to Web Mercator via `geokit/mercator` first.
- Bounding boxes do not wrap around the antimeridian.

## License

[MIT](LICENSE)
