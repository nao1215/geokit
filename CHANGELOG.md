# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project is expected to follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed

- `geojson.feature_decoder` decodes a number id with no fractional part, such as `1.0` or `1.0e300`, to `IntId` on both targets. On Erlang `1.0` used to decode to `FloatId(1.0)` while JavaScript gave `IntId(1)`. A `FloatId` with no fractional part therefore comes back as `IntId` after encoding and decoding.

### Fixed

- `distance` keeps its precision near antipodal points. The haversine form could be off by up to 18 cm there, and Erlang and JavaScript returned values 13 cm apart for the same points; it now uses the Vincenty formula for a sphere, which in a differential run of 3,000 pairs stayed within 6 nanometres of GeographicLib's geodesic on the same sphere. `distance(a, b)` and `distance(b, a)` are still exactly equal.
- `geojson.geometry_decoder` accepts positions with more than three numbers and drops the extra ones, as RFC 7946 section 3.1.1 allows, including integers too large to be coordinates. They used to fail with `position of 2 or 3 numbers`; the message for a position with fewer than two numbers is now `position of at least 2 numbers`.

### Documentation

- The README gave the error of the spherical model against an ellipsoidal distance as under 0.5 %. It reaches 0.56 % for short north-south distances near the equator, and the note now says under 0.6 %.

## [0.9.0] - 2026-11-22

### Breaking

The public API shrinks from 13 modules to 5: `geokit`, `geokit/geohash`, `geokit/polyline`, `geokit/tile` and `geokit/geojson`.

- `latlng`, `geometry`, `distance`, `bearing`, `bbox`, `centroid`, `simplify` and `point_in_polygon` move into `geokit`. Their functions are `lat_lng`, `wrap_lat_lng`, `latitude`, `longitude`, `distance` (meters), `initial_bearing`, `final_bearing`, `bounding_box`, `centroid`, `simplify` and `locate`.
- `mercator` is renamed `tile`. `to_lat_lng` is removed; use `bounds`.
- `bounding_box`, `geohash.decode_bounds` and `tile.bounds` return a `BoundingBox(south_west:, north_east:)` record instead of a tuple.
- Errors that had one variant are now `Nil`: `BBoxError`, `CentroidError`, `SimplifyError` and `PointInPolygonError`. `MercatorError` becomes `TileError`, and `TileCoordOutOfRange` becomes `CoordinateOutOfRange`.
- `geojson` returns `gleam/json` values and decoders: `geometry_to_json`, `feature_to_json`, `feature_collection_to_json`, `geometry_decoder`, `feature_decoder` and `feature_collection_decoder`. `GeoJsonError` and the `encode_*` and `decode_*` functions are removed. `Feature.geometry` is now `Option(Geometry)`, and `FeatureId` gains `FloatId`.
- `polyline.encode` and `decode` take `precision:`, and `encode_with` and `decode_with` are removed. `decode` returns `CoordinateOutOfRange(index:)` for out-of-range coordinates instead of clamping them.
- `geohash.neighbor` and `neighbors` return `NoNeighborBeyondPole` past a pole instead of `EmptyHash`. The direction label is `toward:`.
- Removed: `geokit.version`, `latlng.new_or_panic`, `latlng.equal` (use `==`), `bbox.of_points`, `centroid.of_points` (use `MultiPoint` with the closing vertex left out, or `Polygon` for the area centroid), `distance.haversine_km`, `simplify.line_string` (use `LineString`) and `point_in_polygon.contains` (use `locate`).
- Renamed variants and fields: `LatOutOfRange(lat:)` and `LngOutOfRange(lng:)` become `LatitudeOutOfRange(latitude:)` and `LongitudeOutOfRange(longitude:)`, `InvalidCharacter(char:)` in geohash and polyline becomes `InvalidCharacter(character:)`, `InvalidQuadkeyChar(char:)` becomes `InvalidQuadkeyCharacter(character:)`, and `FeatureId` variants drop the `value:` label.
- Labels on a function's first argument are removed, so `geohash.decode(hash: h)` becomes `geohash.decode(h)`.
- `Geometry` gains `MultiLineString`.
- The minimum `gleam_stdlib` is 0.51.0, the version `gleam_json` 3 needs.

Before:

```gleam
import geokit/distance
import geokit/latlng

let assert Ok(tokyo) = latlng.new(lat: 35.6812, lng: 139.7671)
let assert Ok(osaka) = latlng.new(lat: 34.6937, lng: 135.5023)
distance.haversine(a: tokyo, b: osaka)
```

After:

```gleam
import geokit

let assert Ok(tokyo) = geokit.lat_lng(latitude: 35.6812, longitude: 139.7671)
let assert Ok(osaka) = geokit.lat_lng(latitude: 34.6937, longitude: 135.5023)
geokit.distance(from: tokyo, to: osaka)
```

### Fixed

- `geohash.neighbor` steps east or west across the antimeridian. `neighbor("0", West)` returned `Error(EmptyHash)` and now returns `Ok("p")`.
- `geohash.neighbor` and `neighbors` check every character, not only the last one.
- On JavaScript, `polyline.decode` no longer overflows the stack at about 2,000 points, and `bbox`, `centroid` and `simplify` no longer overflow at about 20,000 points.
- GeoJSON with integer coordinates such as `[139, 35]` decodes on Erlang. Before, it failed on Erlang and succeeded on JavaScript.
- Ring closure checks and `latlng.equal` treat `-0.0` and `0.0` as the same position on both targets.
- `centroid.compute` weights a `MultiPolygon` by area and subtracts holes. Before, it averaged the polygon centroids and ignored holes.
- `simplify.compute` keeps a closed ring valid. Before, a large tolerance collapsed a ring to 2 positions, which `geojson` could not read back.
- `distance.haversine` is accurate for points less than a metre apart.
- `polyline.decode` rejects DEL (0x7F) and runs of more than 10 continuation chunks, and reports the grapheme and its index in `InvalidCharacter`.
- `latlng.new` rejects NaN on JavaScript.

### Changed

- `simplify` is about 7 times faster on 10,000 points.

## [0.8.0] - 2026-11-19

### Removed

- Breaking: `mercator.tile`, the deprecated alias of `mercator.new`; call `mercator.new`.
- Breaking: the `mercator.EmptyQuadkey` error variant. No function has returned it since `from_quadkey("")` started returning the zoom-0 root tile; drop it from `case` arms.

### Added

- GitHub Releases now attach the package tarball, `checksums.txt`, its cosign signature (`checksums.txt.sigstore.json`) and build provenance (`.intoto.jsonl`). See "Verifying releases" in the README.

## [0.7.0] - 2026-09-10

### Added

- `geokit/point_in_polygon`: new module that tells whether a point lies in a `Polygon` or `MultiPolygon`, like Turf's `booleanPointInPolygon`. `contains` counts the boundary as inside (Turf's default) and `locate` returns `Inside` / `OnBoundary` / `Outside`, so `locate(...) == Ok(Inside)` is Turf's `ignoreBoundary: true`; holes are excluded, rings may be open or closed, the test is planar ray casting on lng/lat without antimeridian wrapping, and other geometries return `Error(NotAPolygon)`.

### Changed

- The minimum Gleam version is now 1.14.0 (was 1.15.0). 1.14.0 builds and tests the package unchanged on both targets, and `gleam_stdlib` 1.0 already requires it. CI tests that floor alongside the latest Gleam 1.x.

### Fixed

- `geokit.version()` returned `"0.2.0"` in every release since 0.2.0; it now returns the published package version.

## [0.6.0] - 2026-05-22

### Fixed

- `geokit/geohash`: `geohash.encode` now follows the canonical Wikipedia / `ngeohash` / `pygeohash` / `geohash.org` convention at recursive bisection midpoints — `coordinate >= midpoint` places the bit in the upper half. The previous strict `>` produced different cells from every other geohash implementation for midpoint inputs (the equator, the poles, the prime / anti meridian), silently breaking interop: a hash emitted by geokit for `(0, 0)` decoded in `pygeohash` / `ngeohash` / a JS map widget pointed at a different cell on the opposite side of the equator. Non-midpoint inputs are unaffected. **Breaking** for callers that stored geokit-0.5.x hashes for midpoint inputs — re-encode such hashes before upgrading if exact byte-equality matters. The encode docstring now spells out the convention explicitly. (#31)

## [0.5.0] - 2026-05-20

### Changed

- `geokit/centroid`: `centroid.of_points` now drops the trailing duplicate when the input is a closed ring of three or more vertices (first vertex equal to last — the shape GeoJSON Polygon linear rings carry per RFC 7946 §3.1.6). The unit-square closed ring `[(0,0), (0,1), (1,1), (1,0), (0,0)]` now returns `(0.5, 0.5)` instead of the closing-duplicate-biased `(0.4, 0.4)`. Two-element rings where both vertices are equal are left alone (their mean is already that point). Interior adjacent duplicates are preserved — they may be deliberate. For the geometric (signed-area) centroid, use `centroid.compute(Polygon(...))`. (#26)
- `geokit/geojson`: `InvalidStructure(reason: String)` now carries an actionable reason string instead of the opaque `"JSON shape did not match expected GeoJSON"` for every JSON-decoder failure. The new reason names the failing field path (e.g. `"at coordinates"`) and quotes the expected/found pair the underlying decoder reported (e.g. `"expected List(Float), got Nil"`), so a caller routing to a 400 response can attach the failing position without re-parsing the input. Inputs whose root cause is one of the existing specific variants (`InvalidPosition`, `InvalidLatLng`, `InvalidPolygon`, `UnknownType`) still surface those variants instead. (#25)

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
