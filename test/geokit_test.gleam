import geokit
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn version_is_set_test() -> Nil {
  geokit.version()
  |> should.equal("0.1.0")
}
