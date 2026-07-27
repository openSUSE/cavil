{
  "errors"              => [],
  "incomplete_checkout" => 0,
  "main"                => {
    "file"                 => "Dockerfile",
    "legal_review_notices" => ["Vendored Go toolchain is not part of the image"],
    "license"              => "BSD-3-Clause AND MIT",
    "licenses"             => ["BSD-3-Clause AND MIT"],
    "summary"              => "Environment for Go 1.16 development",
    "type"                 => "dockerfile",
    "version"              => "%%PKG_VERSION%%.%RELEASE%"
  },
  "sub" => [
    {
      "file"                 => "Dockerfile",
      "legal_review_notices" => ["Vendored Go toolchain is not part of the image"],
      "licenses"             => ["BSD-3-Clause AND MIT"],
      "summary"              => "Environment for Go 1.16 development",
      "type"                 => "dockerfile",
      "version"              => "%%PKG_VERSION%%.%RELEASE%"
    },
    {
      "file"                 => "Dockerfile.custom",
      "legal_review_notices" => ["Custom flavor builds without the debug tooling"],
      "licenses"             => ["BSD-3-Clause"],
      "summary"              => "Custom Go 1.16 development container",
      "type"                 => "dockerfile",
      "version"              => "%%PKG_VERSION%%.%RELEASE%"
    },
    {
      "file"                 => "dummy.Dockerfile",
      "legal_review_notices" => [],
      "licenses"             => ["BSD-3-Clause"],
      "summary"              => "Whatever",
      "type"                 => "dockerfile"
    }
  ],
  "warnings" => []
}
