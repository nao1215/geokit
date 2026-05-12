//// Geometry types shared by [`geokit/bbox`](./bbox.html),
//// [`geokit/centroid`](./centroid.html), and
//// [`geokit/simplify`](./simplify.html).
////
//// The ADT mirrors RFC 7946 GeoJSON (`Point`, `LineString`,
//// `Polygon`, `MultiPolygon`) but only carries geometric data — no
//// properties, no IDs, no coordinate-reference-system metadata —
//// because every consumer in this package operates on coordinates
//// alone.
////
//// `LineString` and `Polygon` rings are simple lists of points; no
//// invariant is enforced at the type level. Operations that require
//// a particular shape (a polygon with a closed exterior ring, for
//// example) document and check their preconditions explicitly.

import geokit/latlng.{type LatLng}

/// A geometry value. Pattern-match to dispatch on the kind of
/// shape; the points are accessible via the [`latlng`](../latlng.html)
/// module.
pub type Geometry {
  /// A single point.
  Point(point: LatLng)
  /// A connected sequence of segments. The list should have at least
  /// two points for the geometry to be meaningful, but the type does
  /// not enforce this.
  LineString(points: List(LatLng))
  /// A polygon defined by one or more rings. The first ring is the
  /// exterior; subsequent rings are interior holes. Each ring should
  /// be closed (first point equal to last); operations that need a
  /// closed ring will close it themselves if necessary.
  Polygon(rings: List(List(LatLng)))
  /// A collection of polygons sharing one geometric meaning (an
  /// archipelago, a country with several territories, ...).
  MultiPolygon(polygons: List(List(List(LatLng))))
}
