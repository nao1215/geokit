//// Top-level entry point for the `geokit` package.
////
//// The package is organised by domain:
////
//// - [`geokit/latlng`](./geokit/latlng.html) — opaque `LatLng` type
////   and accessors.
//// - [`geokit/distance`](./geokit/distance.html) — great-circle
////   distance via the haversine formula.
//// - [`geokit/bearing`](./geokit/bearing.html) — initial and final
////   compass bearing between two points.
//// - [`geokit/geohash`](./geokit/geohash.html) — Niemeyer geohash
////   encoding / decoding with neighbour lookup.
//// - [`geokit/polyline`](./geokit/polyline.html) — Google Encoded
////   Polyline algorithm.
//// - [`geokit/mercator`](./geokit/mercator.html) — Web Mercator tile
////   and quadkey conversion.
//// - [`geokit/geometry`](./geokit/geometry.html) — `Geometry` ADT
////   (`Point` / `LineString` / `Polygon`) shared by `bbox`,
////   `centroid`, and `simplify`.
//// - [`geokit/bbox`](./geokit/bbox.html) — bounding box computation.
//// - [`geokit/centroid`](./geokit/centroid.html) — geometric
////   centroid.
//// - [`geokit/simplify`](./geokit/simplify.html) — Douglas-Peucker
////   line simplification.

/// The package version string. Useful for runtime diagnostics and
/// version reporting in dependent applications.
pub fn version() -> String {
  "0.2.0"
}
