{
  "errors" => [
    "Main Dockerfile contains no license: error-missing-main-dockerfile.Dockerfile (expected \"# SPDX-License-Identifier: ...\" comment)"
  ],
  "incomplete_checkout" => 0,
  "main"                => {
    "file"     => "error-missing-main-dockerfile.Dockerfile",
    "licenses" => [],
    "summary"  => "Just a test",
    "type"     => "dockerfile",
    "version"  => "%%PKG_VERSION%%.%RELEASE%"
  },
  "sub" => [
    {
      "file"     => "error-missing-main-dockerfile.Dockerfile",
      "licenses" => [],
      "summary"  => "Just a test",
      "type"     => "dockerfile",
      "version"  => "%%PKG_VERSION%%.%RELEASE%"
    }
  ],
  "warnings" => []
}
