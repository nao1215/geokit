# Testing

`gleam test` runs everything below on the Erlang and JavaScript targets. CI runs it on Linux, macOS and Windows with the latest Gleam 1.x, and on the Gleam floor (1.14.0, OTP 27, Node 22).

## Examples and unit tests

`test/geokit_test.gleam` and one test file per encoding module hold fixed inputs and expected outputs, including the documented edge cases (poles, the antimeridian, empty inputs, invalid hashes and polylines). `test/readme_test.gleam` runs the README examples. Fixed bugs keep their reproduction in a `test/regression_*_test.gleam` file.

## Generated properties

`test/property_test.gleam` and `test/point_in_polygon_property_test.gleam` use metamon: distance is non-negative, symmetric and obeys the triangle inequality; bearings stay in [0, 360); geohash prefixes, alphabet, bounds and neighbors; polyline round trips at precision 5 and 6; Web Mercator tiles contain their point and quadkeys round-trip; bbox, centroid and simplify are order-invariant and keep endpoints; point-in-polygon agrees with closed-form oracles for rectangles with holes and diamonds.

## Metamorphic relations

`test/metamorphic_test.gleam` and the invariance tests in `test/point_in_polygon_property_test.gleam` compare two runs instead of one expected value:

- Distance does not change when both points move by the same longitude or are mirrored together across the equator or the prime meridian.
- Mirroring both points across the prime meridian turns the initial bearing b into 360 - b, and across the equator into 180 - b.
- The tile of a point at zoom z + 1 is a child of its tile at zoom z, and its quadkey extends the parent's by one digit.
- Douglas-Peucker with a larger tolerance keeps a subsequence of the points kept with a smaller one.
- Point-in-polygon answers do not change under translation, mirroring, ring orientation, ring start vertex or a repeated closing vertex.

## Differential testing

`test/differential_test.gleam` checks every public function against values from independent implementations, recorded next to each assertion so they can be regenerated: Python `math` for distance and bearing on the same radius (6,371,008.8 m), `ngeohash` for geohash, `@mapbox/polyline` for polylines, the OSM slippy-map and Bing quadkey formulas for Web Mercator, and Turf for bbox, centroid and simplify. `test/regression_distance_antipodal_test.gleam` checks near-antipodal and very short distances against GeographicLib geodesics on the same sphere, to within a millimetre.

## Nightly runs

`.github/workflows/nightly-property.yml` runs the whole suite ten times with `METAMON_RUNS_MULTIPLIER=10`, each pass with a new seed. A failure report prints its seed, so the case can be replayed with `Config(..default_config(), seed: Some(seed))` and kept as a regression test.

## Mutation testing

`gleam run -m metamon/mutation -- run` changes one operator, `!` or boolean literal in a module under `src/` at a time and runs `gleam test --target erlang` on each change; `gleam run -m metamon/mutation -- gate` then fails on a survivor that `doc/mutation/baseline.json` does not list, and `gleam run -m metamon/mutation -- baseline` records a full run as the baseline. `.github/workflows/mutation.yml` mutates the modules a pull request changes and runs the gate; the weekly run mutates every module.

The first run (2026-11-27) scored 87.8%. Tests were then added for polyline precision 1, tile zoom 30, a point on the antimeridian at the last tile column, and a tie between two farthest points in `simplify`, and the score rose to 89.6%. Two later runs gave the same survivors. The 29 left change nothing that a caller can see:

- `geokit` (18): latitude and longitude clamps at exactly the bound, the shift by 180 degrees in `wrap_longitude` and `final_bearing`, which is the same modulo 360 either way, the order of the endpoints in `distance`, the reduction in `normalize_degrees`, whose floor is only -1, 0 or 1 for its inputs (and Gleam's division by zero gives 0), and endpoint comparisons in the point-in-polygon edge test that the other half of `between` or the side test already decides.
- `geokit/internal/douglas_peucker` (4): the size checks of the ring fallback, which return the same four vertices, the closing vertex as a candidate, which is never farther than the others, and the tie rule of `farthest_from_chord`, which picks the same ring in the tie test.
- `geokit/internal/centroid` (3): ring orientation at zero area and the closing of rings that are already closed.
- `geokit/geohash` (1): lowercasing `A`, which is not in the geohash alphabet either way.
- `geokit/geojson` (1): an integer of exactly 10^9, which is outside the coordinate range either way.
- `geokit/polyline` (1): encoding 0 as a negative number, which writes the same `?`.
- `geokit/tile` (1): `2 * bit_y` and `2 / bit_y`, equal for a bit of 0 or 1.

<!-- mutation:start -->
| Module | Killed | Lived | Timed out | Score |
|---|---:|---:|---:|---:|
| `geokit` | 64 | 18 | 0 | 78.0% |
| `geokit/geohash` | 41 | 1 | 0 | 97.6% |
| `geokit/geojson` | 5 | 1 | 0 | 83.3% |
| `geokit/internal/centroid` | 34 | 3 | 0 | 91.9% |
| `geokit/internal/douglas_peucker` | 21 | 4 | 0 | 84.0% |
| `geokit/polyline` | 40 | 1 | 0 | 97.6% |
| `geokit/tile` | 45 | 1 | 0 | 97.8% |
| all | 250 | 29 | 0 | 89.6% |
<!-- mutation:end -->
