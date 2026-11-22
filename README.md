# geokit

[![CI](https://github.com/nao1215/geokit/actions/workflows/ci.yml/badge.svg)](https://github.com/nao1215/geokit/actions/workflows/ci.yml)
[![Gitleaks](https://github.com/nao1215/geokit/actions/workflows/gitleaks.yml/badge.svg)](https://github.com/nao1215/geokit/actions/workflows/gitleaks.yml)
[![Trivy](https://github.com/nao1215/geokit/actions/workflows/trivy.yml/badge.svg)](https://github.com/nao1215/geokit/actions/workflows/trivy.yml)
[![OSV-Scanner](https://github.com/nao1215/geokit/actions/workflows/osv-scan.yml/badge.svg)](https://github.com/nao1215/geokit/actions/workflows/osv-scan.yml)
[![Hex](https://img.shields.io/hexpm/v/geokit)](https://hex.pm/packages/geokit)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/geokit/)
[![Hex Downloads](https://img.shields.io/hexpm/dt/geokit)](https://hex.pm/packages/geokit)
[![License](https://img.shields.io/github/license/nao1215/geokit)](https://github.com/nao1215/geokit/blob/main/LICENSE)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/nao1215/geokit/badge)](https://scorecard.dev/viewer/?uri=github.com/nao1215/geokit)

Distance, bearing, geohash, polyline, GeoJSON, map tiles and polygon
operations for Gleam, on the Erlang and JavaScript targets.

```sh
gleam add geokit
```

## Usage

Distance and bearing between two points:

```gleam
import geokit

pub fn tokyo_to_osaka() -> #(Float, Float) {
  let assert Ok(tokyo) = geokit.lat_lng(latitude: 35.6812, longitude: 139.7671)
  let assert Ok(osaka) = geokit.lat_lng(latitude: 34.6937, longitude: 135.5023)
  #(
    geokit.distance(from: tokyo, to: osaka),
    geokit.initial_bearing(from: tokyo, to: osaka),
  )
  // -> #(402_784.74, 255.42), in meters and degrees
}
```

Reading GeoJSON with [gleam_json](https://hexdocs.pm/gleam_json/) and testing a point against it:

```gleam
import geokit
import geokit/geojson
import gleam/json

pub fn inside_park(input: String) -> Result(geokit.Location, Nil) {
  let assert Ok(park) = json.parse(input, geojson.geometry_decoder())
  let bench = geokit.wrap_lat_lng(latitude: 2.0, longitude: 2.0)
  geokit.locate(bench, in: park)
  // -> Ok(geokit.Inside) for a polygon around (0, 0) to (10, 10)
}
```

Geohash, encoded polyline and Web Mercator tile:

```gleam
import geokit
import geokit/geohash
import geokit/polyline
import geokit/tile

pub fn encodings() -> #(String, String, String) {
  let assert Ok(tokyo) = geokit.lat_lng(latitude: 35.6812, longitude: 139.7671)
  let assert Ok(osaka) = geokit.lat_lng(latitude: 34.6937, longitude: 135.5023)
  let assert Ok(hash) = geohash.encode(tokyo, precision: 8)
  let assert Ok(route) = polyline.encode([tokyo, osaka], precision: 5)
  let assert Ok(tokyo_tile) = tile.from_lat_lng(tokyo, zoom: 5)
  #(hash, route, tile.to_quadkey(tokyo_tile))
  // -> #("xn76urx6", "o~wxEkgatYzz_E~}_Y", "13300")
}
```

The API reference is on [HexDocs](https://hexdocs.pm/geokit/).

## Notes

- Distance and bearing use a sphere with the mean Earth radius (6,371,008.8 m). The error against an ellipsoidal distance stays under 0.5 %.
- Bounding box, centroid, simplification and point-in-polygon treat longitude and latitude as a flat plane. Errors grow on shapes wider than a few degrees.
- Nothing wraps around the antimeridian. Split a shape that crosses it into a `MultiPolygon`, as RFC 7946 §3.1.9 recommends.

How the package is tested is described in [doc/testing.md](https://github.com/nao1215/geokit/blob/main/doc/testing.md).

## Verifying releases

Each GitHub Release attaches the Hex package tarball (`geokit-<version>.tar`),
`checksums.txt`, a cosign signature bundle (`checksums.txt.sigstore.json`) and
build provenance (`geokit-<version>.intoto.jsonl`). Download the assets, then:

```sh
gh attestation verify geokit-<version>.tar --repo nao1215/geokit

cosign verify-blob \
  --bundle checksums.txt.sigstore.json \
  --certificate-identity-regexp '^https://github\.com/nao1215/geokit/\.github/workflows/release\.yml@refs/tags/v' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  checksums.txt
sha256sum --check checksums.txt
```

## License

[MIT](https://github.com/nao1215/geokit/blob/main/LICENSE)
