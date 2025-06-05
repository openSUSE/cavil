{
  "errors"              => [],
  "incomplete_checkout" => 0,
  "main"                => {
    "file"     => "Dockerfile",
    "license"  => "BSD-3-Clause AND MIT",
    "licenses" => ["BSD-3-Clause AND MIT"],
    "summary"  => "Environment for Go 1.16 development",
    "type"     => "dockerfile",
    "version"  => "%%PKG_VERSION%%.%RELEASE%"
  },
  "sub" => [
    {
      "file"     => "Dockerfile",
      "licenses" => ["BSD-3-Clause AND MIT"],
      "summary"  => "Environment for Go 1.16 development",
      "type"     => "dockerfile",
      "version"  => "%%PKG_VERSION%%.%RELEASE%"
    },
    {"file" => "dummy.Dockerfile", "licenses" => ["BSD-3-Clause"], "summary" => "Whatever", "type" => "dockerfile"}
  ],
  "warnings" => []
}
