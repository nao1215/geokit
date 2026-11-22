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

`test/differential_test.gleam` checks every public function against values from independent implementations, recorded next to each assertion so they can be regenerated: Python `math` for haversine and bearing on the same radius (6,371,008.8 m), `ngeohash` for geohash, `@mapbox/polyline` for polylines, the OSM slippy-map and Bing quadkey formulas for Web Mercator, and Turf for bbox, centroid and simplify.

## Nightly runs

`.github/workflows/nightly-property.yml` runs the whole suite ten times with `METAMON_RUNS_MULTIPLIER=10`, each pass with a new seed. A failure report prints its seed, so the case can be replayed with `metamon.with_seed` and kept as a regression test.

## Mutation testing

There is no mutation testing tool for Gleam, so `gleam_mutate.py` (from the mutation-testing lab in nao1215/debimate) is run by hand on a copy of the project. It rewrites one operator or boolean result at a time (`==`/`!=`, `&&`/`||`, float comparisons, `-.`/`+.`, `-> True`/`-> False`, a dropped `!`) and runs `gleam test` on the Erlang target. The score is killed / (killed + lived).

| Date | Files | Killed | Lived | Score |
|---|---|---:|---:|---:|
| 2026-11-19 | every module under `src/` | 79 | 13 | 85.9% |

The first run scored 68/92 (73.9%). Every simplify test started its segment at the origin, so `x2 -. x1` and `x2 +. x1` gave the same distance; a diagonal segment and a closed line away from the origin now kill those six mutants. Tile coordinates were never negative in a test and `from_lat_lng` was never given an invalid zoom, an open GeoJSON ring always differed in both coordinates, and no test passed a zero tolerance to `simplify`; tests for each now exist.

The 13 survivors are boundary comparisons where `<.` and `<=.` give the same result at the boundary value (`wrap_longitude` at exactly ±180, `sqrt_nonneg` of 0, the absolute value of 0, the minimum in the bounding box, bearing normalization at 0, rounding of -0 in `polyline`), and point-in-polygon edge tests where an endpoint lies on two edges, so the other edge still reports it.
