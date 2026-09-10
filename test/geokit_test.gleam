import geokit
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn version_matches_gleam_toml_test() -> Nil {
  // Must equal `version` in gleam.toml; the release checklist updates both.
  geokit.version()
  |> should.equal("0.7.0")
}
