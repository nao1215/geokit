# Testing

`gleam test` runs everything below on the Erlang and JavaScript targets. CI runs it on Linux, macOS and Windows with the latest Gleam 1.x, and on the Gleam floor (1.14.0, OTP 27, Node 22).

## Examples and unit tests

Each module has a `test/<module>_test.gleam` with fixed inputs and expected outputs, including the documented edge cases (poles, the antimeridian, empty inputs, invalid hashes and polylines). `test/readme_test.gleam` runs the README snippets. Fixed bugs keep their reproduction in a `test/regression_*_test.gleam` file.

## Generated properties

`test/dig_round2_property_based_test.gleam` and `test/point_in_polygon_property_test.gleam` use metamon: distance is non-negative, symmetric and obeys the triangle inequality; bearings stay in [0, 360); geohash prefixes, alphabet, bounds and neighbours; polyline round trips at precision 5 and 6; Web Mercator tiles contain their point and quadkeys round-trip; bbox, centroid and simplify are order-invariant and keep endpoints; point-in-polygon agrees with closed-form oracles for rectangles with holes and diamonds.

## Metamorphic relations

`test/metamorphic_test.gleam` and the invariance tests in `test/point_in_polygon_property_test.gleam` compare two runs instead of one expected value:

- Distance does not change when both points move by the same longitude or are mirrored together across the equator or the prime meridian.
- Mirroring both points across the prime meridian turns the initial bearing b into 360 - b, and across the equator into 180 - b.
- The tile of a point at zoom z + 1 is a child of its tile at zoom z, and its quadkey extends the parent's by one digit.
- Douglas-Peucker with a larger tolerance keeps a subsequence of the points kept with a smaller one.
- Point-in-polygon answers do not change under translation, mirroring, ring orientation, ring start vertex or a repeated closing vertex.

## Differential testing

`test/dig_round1_differential_test.gleam` checks every public function against values from independent implementations, recorded next to each assertion so they can be regenerated: Python `math` for haversine and bearing on the same radius (6,371,008.8 m), `ngeohash` for geohash, `@mapbox/polyline` for polylines, the OSM slippy-map and Bing quadkey formulas for Web Mercator, and Turf for bbox, centroid and simplify.

## Nightly runs

`.github/workflows/nightly-property.yml` runs the whole suite ten times with `METAMON_RUNS_MULTIPLIER=10`, each pass with a new seed. A failure report prints its seed, so the case can be replayed with `metamon.with_seed` and kept as a regression test.
