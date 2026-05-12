# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project is expected to follow [Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-05-12

Initial release. Ten modules covering spherical-earth math,
location-string encodings, Web Mercator tile / quadkey conversion,
and basic geometry operations. Runs on both the Erlang and JavaScript
targets.

### Added

- `geokit/latlng` — opaque `LatLng` type with validated `new`,
  longitude-wrap `wrap`, accessors `lat` / `lng`, and value
  equality `equal`.
- `geokit/distance` — `haversine` and `haversine_km` great-circle
  distance using the WGS84 mean Earth radius (6_371_008.8 m).
- `geokit/bearing` — `initial` and `final` compass bearing in
  degrees in `[0, 360)`.
- `geokit/geohash` — Niemeyer base32 geohash: `encode` / `decode` /
  `decode_bounds` / eight-direction `neighbor` and `neighbors`.
  Decode operations accept upper-case input.
- `geokit/polyline` — Google Encoded Polyline algorithm: `encode` /
  `decode` at precision 5 (default), plus `encode_with` /
  `decode_with` for precision in `[1, 11]`. Out-of-range precision
  returns `Error(PrecisionOutOfRange)`.
- `geokit/mercator` — Web Mercator (EPSG:3857) opaque `Tile` type
  with `new`, `from_lat_lng`, `to_lat_lng`, `bounds`. Bing-style
  quadkey encode / decode via `to_quadkey` / `from_quadkey`;
  quadkey length is bounded by the documented `[0, 30]` zoom range.
- `geokit/geometry` — `Geometry` ADT (`Point` / `LineString` /
  `Polygon` / `MultiPolygon`) shared by the operations below.
- `geokit/bbox` — `compute` axis-aligned bounding box of a `Geometry`.
- `geokit/centroid` — `compute` centroid (signed-area-weighted for
  polygons, arithmetic mean for line strings).
- `geokit/simplify` — Douglas-Peucker line simplification:
  `compute` is `Geometry`-polymorphic; `line_string` accepts a bare
  `List(LatLng)`.

### Deprecated

- `geokit/mercator.tile` — superseded by `geokit/mercator.new`,
  named for parity with `geokit/latlng.new`. Kept as an alias for
  one release cycle; will be removed in v1.0.

### Notes

- All trigonometric functions come from
  [`gleam_community_maths`](https://hex.pm/packages/gleam_community_maths)
  — no FFI is used.
- The lat/lng plane is treated as Cartesian for bounding-box,
  centroid, and simplification operations. For polygons spanning
  more than a few degrees, project to Web Mercator via
  `geokit/mercator` before computing area-sensitive properties.
- Spherical-earth distances use the WGS84 mean Earth radius
  (6_371_008.8 m). Error against an ellipsoidal (Vincenty) distance
  is bounded by 0.5 % anywhere on Earth.
- Niemeyer geohash uses strict greater-than comparison at cell
  midpoints (matching `ngeohash`, OpenStreetMap's tile boundaries,
  and most server-side implementations). At the boundary `(0, 0)`
  a precision-5 hash is `"7zzzz"`, not `"s0000"`.

### Quality assurance

The release was hardened by three rounds of `gleam-dig-bug`:

- Differential testing against reference implementations
  (Python `math`, `ngeohash`, `@mapbox/polyline`, OSM tile / Bing
  quadkey formulas, `@turf/bbox` / `@turf/centroid` / `@turf/simplify`).
- Property-based and metamorphic testing using
  [`metamon`](https://github.com/nao1215/metamon).
- Random and mutation fuzzing of every parser-shaped public function.

Final state: 213 tests pass on both Erlang and JavaScript targets;
`gleam run -m glinter` reports zero warnings or errors under
`warnings_as_errors = true`; the CI matrix is green on
Linux / macOS / Windows × Erlang / JavaScript.
