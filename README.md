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

## Modules

| Module | What it does |
|---|---|
| [`geokit/latlng`](https://hexdocs.pm/geokit/geokit/latlng.html) | Opaque `LatLng` (geographic coordinate), constructor with validation, longitude-wrap helper. |
| [`geokit/distance`](https://hexdocs.pm/geokit/geokit/distance.html) | Haversine great-circle distance in metres and kilometres. |
| [`geokit/bearing`](https://hexdocs.pm/geokit/geokit/bearing.html) | Initial and final compass bearing between two points. |
| [`geokit/geohash`](https://hexdocs.pm/geokit/geokit/geohash.html) | Niemeyer geohash: encode, decode, decode bounds, eight-direction neighbours. |
| [`geokit/polyline`](https://hexdocs.pm/geokit/geokit/polyline.html) | Google Encoded Polyline (precision 5 and 6). |
| [`geokit/mercator`](https://hexdocs.pm/geokit/geokit/mercator.html) | Web Mercator (EPSG:3857) tile and Bing quadkey conversion. |
| [`geokit/geometry`](https://hexdocs.pm/geokit/geokit/geometry.html) | `Geometry` ADT (`Point` / `LineString` / `Polygon` / `MultiPolygon`) shared by the ops below. |
| [`geokit/bbox`](https://hexdocs.pm/geokit/geokit/bbox.html) | Axis-aligned bounding box of a geometry. |
| [`geokit/centroid`](https://hexdocs.pm/geokit/geokit/centroid.html) | Geometric centroid (signed-area weighted for polygons). |
| [`geokit/simplify`](https://hexdocs.pm/geokit/geokit/simplify.html) | Douglas-Peucker line simplification. |

## Examples

### Haversine distance and initial bearing

```gleam
import geokit/bearing
import geokit/distance
import geokit/latlng

pub fn tokyo_to_osaka() -> #(Float, Float) {
  let assert Ok(tokyo) = latlng.new(lat: 35.6812, lng: 139.7671)
  let assert Ok(osaka) = latlng.new(lat: 34.6937, lng: 135.5023)
  #(
    distance.haversine(a: tokyo, b: osaka),
    // ≈ 402_785 m
    bearing.initial(from: tokyo, to: osaka),
    // ≈ 254.0°
  )
}
```

### Geohash encode / decode / neighbour lookup

```gleam
import geokit/geohash
import geokit/latlng

pub fn around_tokyo() -> String {
  let assert Ok(tokyo) = latlng.new(lat: 35.6812, lng: 139.7671)
  let assert Ok(hash) = geohash.encode(point: tokyo, precision: 8)
  // hash == "xn76urx6"
  let assert Ok(neighbours) = geohash.neighbors(hash: hash)
  // neighbours.north, neighbours.east, ... eight directions
  hash
}
```

### Google Encoded Polyline

```gleam
import geokit/latlng
import geokit/polyline

pub fn route() -> String {
  let assert Ok(p1) = latlng.new(lat: 38.5, lng: -120.2)
  let assert Ok(p2) = latlng.new(lat: 40.7, lng: -120.95)
  let assert Ok(p3) = latlng.new(lat: 43.252, lng: -126.453)
  polyline.encode(points: [p1, p2, p3])
  // == "_p~iF~ps|U_ulLnnqC_mqNvxq`@"
}
```

### Web Mercator tile and quadkey

```gleam
import geokit/latlng
import geokit/mercator

pub fn tokyo_tile_at_zoom_5() -> #(Int, Int, String) {
  let assert Ok(tokyo) = latlng.new(lat: 35.6812, lng: 139.7671)
  let assert Ok(tile) = mercator.from_lat_lng(point: tokyo, zoom: 5)
  #(mercator.x(tile: tile), mercator.y(tile: tile), mercator.to_quadkey(tile: tile))
}
```

### Bounding box, centroid, simplify

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
  // sw / ne are the SW / NE corners.
  let assert Ok(centre) = centroid.compute(geometry: polygon)
  // centre ≈ (5.0, 5.0).
  let assert Ok(reduced) =
    simplify.line_string(points: [a, b, c, d], tolerance: 0.001)
  #(sw, ne, centre, reduced)
}
```

## Notes

- Latitudes are in degrees in `[-90, 90]`; longitudes in degrees in
  `[-180, 180]`. The opaque `LatLng` type enforces this at
  construction; use `latlng.wrap` when your source data may be
  denormalised.
- Distance and bearing use the **spherical-earth** approximation with
  the WGS84 mean radius of 6_371_008.8 m. The error against an
  ellipsoidal (Vincenty) distance is bounded by 0.5 % anywhere on
  Earth.
- All polygon / line operations treat the lat/lng plane as flat — no
  projection is applied. For polygons spanning more than a few
  degrees, project to Web Mercator via `geokit/mercator` first.
- Bounding boxes do **not** wrap around the antimeridian.

## License

[MIT](LICENSE)
