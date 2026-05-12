# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project is expected to follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-05-12

Initial release. The ten modules below cover spherical-earth math,
location-string encodings, Web Mercator tile / quadkey conversion,
and basic geometry operations. The package targets both Erlang and
JavaScript.

### Added

- `geokit/latlng` — opaque `LatLng` type with validated `new`,
  longitude-wrap `wrap`, accessors `lat` / `lng`, and value
  equality `equal`.
- `geokit/distance` — `haversine` great-circle distance (in metres
  and kilometres) using the WGS84 mean Earth radius (6_371_008.8 m).
- `geokit/bearing` — `initial` and `final` compass bearing in
  degrees in `[0, 360)`.
- `geokit/geohash` — Niemeyer base32 geohash: `encode` /
  `decode` / `decode_bounds` / eight-direction `neighbor` and
  `neighbors`.
- `geokit/polyline` — Google Encoded Polyline algorithm: `encode` /
  `decode` at precision 5 (default), plus `encode_with` /
  `decode_with` for arbitrary precision (Valhalla / OSRM compatible).
- `geokit/mercator` — Web Mercator (EPSG:3857) opaque `Tile` type,
  `from_lat_lng` / `to_lat_lng` / `bounds`, Bing quadkey
  encode / decode.
- `geokit/geometry` — `Geometry` ADT (`Point` / `LineString` /
  `Polygon` / `MultiPolygon`) used by the geometry ops below.
- `geokit/bbox` — axis-aligned bounding box of a `Geometry`.
- `geokit/centroid` — signed-area-weighted centroid for polygons,
  arithmetic mean for line strings.
- `geokit/simplify` — Douglas-Peucker polyline simplification.

### Notes

- All trigonometric functions come from
  [`gleam_community_maths`](https://hex.pm/packages/gleam_community_maths) —
  no FFI is used.
- The lat/lng plane is treated as Cartesian for bounding-box,
  centroid, and simplification ops. For polygons spanning more than
  a few degrees, project to Web Mercator via `geokit/mercator`
  before computing area-sensitive properties.
- Spherical-earth distances are reported using the WGS84 mean
  Earth radius (6_371_008.8 m). Error against an ellipsoidal
  Vincenty distance is bounded by 0.5 % anywhere on Earth.
- Niemeyer geohash uses **strict** greater-than comparison at cell
  midpoints (matching `ngeohash`, OpenStreetMap's tile boundaries,
  and most server-side implementations). At the boundary `(0, 0)` a
  precision-5 hash is `"7zzzz"`, not `"s0000"` — the latter would
  require non-strict comparison and is not the standard.
