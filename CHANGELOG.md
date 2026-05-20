# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project is expected to follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed

- `geokit/geojson`: `geojson.decode_geometry` now rejects empty Polygons and malformed linear rings instead of producing `Ok(Polygon([]))` / `Ok(Polygon([[]]))`. Per RFC 7946 §3.1.6 a Polygon's `coordinates` must contain at least one linear ring, each linear ring must have at least four positions, and its first position must equal its last. Violations now surface as `Error(InvalidPolygon(reason: String))` — a new `GeoJsonError` variant — with the specific rule named. `MultiPolygon` sub-polygons receive the same validation. The previous one-position-ring case (which already returned `InvalidStructure`) now also routes through `InvalidPolygon` for symmetry. (#24)

## [0.4.0] - 2026-05-18

### Added

- `geokit/latlng`: `latlng.new_or_panic(lat, lng)` — panicking constructor for compile-time-known coordinates (curated city lists, landmark fixtures, hand-coded routes) where wrapping every literal in `let assert Ok(...)` is noise rather than safety. Panics with the offending value when latitude is outside `[-90, 90]` or longitude is outside `[-180, 180]`. The companion `latlng.new` (returns `Result`) remains the right call for runtime input (user-typed, parsed-from-file, network-supplied) where the rejection must be handled. (#19)

### Fixed

- `geokit/mercator`: `mercator.from_quadkey("")` now decodes to the zoom-0 root tile `Tile(zoom: 0, x: 0, y: 0)` instead of returning `Error(EmptyQuadkey)`. At zoom 0 the whole world is one tile whose canonical Bing-Maps quadkey is the empty string (per the Microsoft Bing Maps Tile System spec), and `mercator.to_quadkey` already emits `""` for it — without this fix the `to_quadkey → from_quadkey` round-trip broke at zoom 0. The `EmptyQuadkey` variant of `MercatorError` is retained for backwards compatibility (no function in this module emits it any more) so callers' pattern matches still compile. (#20)

## [0.3.0] - 2026-05-16

### Added

- `geokit/geometry`: new `MultiPoint(points: List(LatLng))` variant on the `Geometry` ADT for non-connected point collections (geotagged events, IoT readings, customer pins, point clouds). Mirrors GeoJSON `MultiPoint` (RFC 7946 §3.1.3). `bbox.compute` and `centroid.compute` accept it and return the same coordinate-only answer they would have produced for the `LineString` workaround, but the type now matches the data's structure — operators that require connected segments will naturally reject `MultiPoint` at the type level instead of silently misbehaving. `simplify.compute` treats `MultiPoint` as a no-op (a bag of unconnected points has no inter-point edges to collapse). (#16)
- `geokit/geojson`: encode and decode `MultiPoint`, closing the round-trip gap previously surfaced as `UnsupportedType("MultiPoint")` by `decode_geometry`. The decoder still reports `UnsupportedType` for the two remaining unsupported types (`MultiLineString`, `GeometryCollection`). (#16)

### Changed

- `geokit/bbox.of_points` and `geokit/centroid.of_points` now wrap callers in the new `MultiPoint` variant rather than `LineString`. Same behaviour (both helpers operate on coordinates only), but the constructed `Geometry` value no longer falsely implies edge / ordering semantics for a flat bag of points.

## [0.2.0] - 2026-05-14

### Added

- `geokit/bbox.of_points` and `geokit/centroid.of_points`:
  convenience entry points that take a flat `List(LatLng)` for
  callers who don't already have a `Geometry` value. Mirrors the
  shape `geokit/simplify` already exposes via
  `simplify.line_string` versus `simplify.compute`, and removes
  the noise of wrapping a bag of points in a `LineString` (which
  implies edge / ordering semantics the bbox and centroid algorithms
  don't actually depend on). Implemented as
  `bbox.compute(LineString(points))` and
  `centroid.compute(LineString(points))` so behaviour, including
  empty-input `EmptyGeometry` errors, stays identical. (#13)

## [0.1.0] - 2026-05-12

Initial release. Eleven modules covering spherical-earth math,
location-string encodings, Web Mercator tile / quadkey conversion,
basic geometry operations, and RFC 7946 GeoJSON I/O. Runs on both
the Erlang and JavaScript targets.

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
- `geokit/geojson` — RFC 7946 GeoJSON encode / decode for `Geometry`,
  `Feature(properties)`, and `FeatureCollection`. Properties are
  user-typed via an injected `Json` builder (encode) and
  `decode.Decoder` (decode), so application records flow through
  end-to-end without dynamic conversion. `MultiPoint`,
  `MultiLineString`, and `GeometryCollection` are rejected with
  `UnsupportedType` since they are not currently representable in
  the `Geometry` ADT.
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
