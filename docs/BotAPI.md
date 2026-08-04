# Cavil Bot API

## REST API

### Authentication

All bot API endpoints use previously configured access tokens for authentication. These tokens are passed with every
request via the `Authorization` header.

```
GET /package/1
Authorization: Token configured_access_token_here
Accept: application/json
```

Authentication failures will result in a `403` response.

```
HTTP/1.1 403 Forbidden
Content-Length: 123
Content-Type: application/json
{
  "error": "It appears you have insufficient permissions for accessing this resource"
}
```

### JSON

The API uses the [JSON](https://tools.ietf.org/html/rfc8259) format whenever possible. Some endpoints will however
support multiple representations through content negotiation. So you should explicitly request JSON with an
`Accept: application/json` header, or you might for example receive HTML instead.

### Form parameters

All API endpoints that use form parameters accept them as part of teh URL query string (like
`PATCH /package/23?priority=8`). For longer values, or forms with a larger number of parameters, it is recommended to
use an `application/x-www-form-urlencoded` encoded request body instead.

### Failures

Validation failures and the like will be signaled with a `4xx` or `5xx` response code. When possible additional details
will be included in JSON format.

```
HTTP/1.1 400 Bad Request
Content-Length: 123
Content-Type: application/json
{
  "error": "Invalid request parameters..."
}
```

### Compression

All responses larger than `860` bytes will be automatically `gzip` compressed for user-agents that include an
`Accept-Encoding: gzip` header with their requests.

```
HTTP/1.1 200 Ok
Content-Length: 123
Content-Type: application/json
Vary: Accept-Encoding
Content-Encoding: gzip
...gzip binary data...
```

### Packages

`GET /package/<package_id>`

Get package status in JSON format.

**Request parameters:**

None

**Request body:**

None

**Response:**

```
HTTP/1.1 200 OK
Content-Length: 550
Content-Type: application/json

{
  "checkout_dir": "c7cfdab0e71b0bebfdf8b2dc3badfecd",
  "checksum": "Artistic-2.0-9:xK1e",
  "created": "2024-01-29 15:07:04+01",
  "created_epoch": "1706537224.000000",
  "export_restricted": 0,
  "cla": 0,
  "eula": 0,
  "external_link": "obs#456712",
  "id": 1,
  "imported": "2024-01-29 15:07:04.521134+01",
  "indexed": "2024-01-29 15:07:09.881978+01",
  "login": null,
  "name": "perl-Mojolicious",
  "obsolete": 0,
  "patent": 0,
  "priority": 5,
  "requesting_user": 1,
  "result": null,
  "reviewed": null,
  "reviewed_epoch": null,
  "reviewing_user": null,
  "source": 1,
  "state": "new",
  "trademark": 0,
  "unpacked": "2024-01-29 15:07:06.612077+01"
}
```

---

`PATCH /package/<package_id>`

Update package information.

**Request parameters:**

* `priority` (required): Priority of this package review.

```
PATCH /package/23?priority=8
Authorization: Token configured_access_token_here
Accept: application/json
```

**Request body:**

None

**Response:**

```
HTTP/1.1 200 OK
Content-Length: 550
Content-Type: application/json

{
  "updated": {
    "checkout_dir": "c7cfdab0e71b0bebfdf8b2dc3badfecd",
    "checksum": "Artistic-2.0-9:xK1e",
    "created": "2024-01-29 15:07:04+01",
    "created_epoch": "1706537224.000000",
    "export_restricted": 0,
    "cla": 0,
    "eula": 0,
    "external_link": "obs#456712",
    "id": 23,
    "imported": "2024-01-29 15:07:04.521134+01",
    "indexed": "2024-01-29 15:07:09.881978+01",
    "login": null,
    "name": "perl-Mojolicious",
    "obsolete": 0,
    "patent": 0,
    "priority": 8,
    "requesting_user": 1,
    "result": null,
    "reviewed": null,
    "reviewed_epoch": null,
    "reviewing_user": null,
    "source": 1,
    "state": "new",
    "trademark": 0,
    "unpacked": "2024-01-29 15:07:06.612077+01"
  }
}
```

---

`POST /packages`

Create package.

**Request parameters:**

* `api` (required): Open Build Service API URL prefix or Git repository.

* `project` (required): Open Build Service project name, if applicable.

* `package` (required): Open Build Service or Git package name.

* `rev` (optional): Open Build Service revision or Git commit to check out.

* `created` (optional): Package creation timestamp.

* `external_link` (optional): Short string describing the package source. Configured `external_link_sources` can render
                              values like `obs#123`, `ibs#123`, `soo#org/package!123` and `ssd#org/package!123` as
                              source links with labels.

* `priority` (optional): Priority of this package review.

```
POST /packages
Authorization: Token configured_access_token_here
Accept: application/json
Content-Length: 92
Content-Type: application/x-www-form-urlencoded

api=https%3A%2F%2Fbuild.opensuse.org&package=perl-Mojolicious&project=devel%3Alanguages%3Aperl&external_link=obs#3734
```

**Request body:**

See request parameters. You can use `application/x-www-form-urlencoded` encoded form values as request body.

**Response:**

```
HTTP/1.1 200 OK
Content-Length: 458
Content-Type: application/json

{
  "saved": {
    "checkout_dir": "236d7b56886a0d2799c0d114eddbb7f1",
    "checksum": null,
    "created": "2024-02-23 15:59:28+01",
    "created_epoch": "1708700368.000000",
    "export_restricted": 0,
    "cla": 0,
    "eula": 0,
    "external_link": 'obs#3734',
    "id": 23,
    "imported": null,
    "indexed": null,
    "login": null,
    "name": "perl-Mojolicious",
    "obsolete": 0,
    "patent": 0,
    "priority": 5,
    "requesting_user": 1,
    "result": null,
    "reviewed": null,
    "reviewed_epoch": null,
    "reviewing_user": null,
    "source": 1,
    "state": "new",
    "trademark": 0,
    "unpacked": null
  }
}
```

---

`POST /packages/upload`

Create a package by uploading a source archive directly, instead of having Cavil check it out from a remote. Useful
when the sources are prepared elsewhere (for example a CI pipeline that has already resolved dependencies) and pushed
in. The review (unpack, indexing, report) is started automatically, just like for `POST /packages`.

The request is a `multipart/form-data` upload rather than a URL-encoded form.

**Request parameters:**

* `name` (required): Package name, used for the checkout directory and queue.

* `priority` (required): Priority of this package review.

* `tarball` (required): The source archive file.

* `checksum` (required): MD5 checksum of the archive, in lower-case hex. The upload is rejected with a `Checksum
                         mismatch` error if the received bytes do not match, so a truncated or corrupt archive can
                         never start a review over incomplete sources.

* `external_link` (optional): Short string describing the package source. Configured `external_link_sources` can render
                              values like `obs#123`, `ibs#123`, `soo#org/package!123` and `ssd#org/package!123` as
                              source links with labels.

```
POST /packages/upload
Authorization: Token configured_access_token_here
Accept: application/json
Content-Type: multipart/form-data; boundary=...

...multipart body with name, priority, checksum, external_link and the tarball file...
```

**Request body:**

The `multipart/form-data` encoded form values, including the archive as the `tarball` file part.

**Response:**

Uploading the same archive under the same name again is idempotent: the existing package is returned with `duplicate`
set to `true`, and no second review is started.

```
HTTP/1.1 200 OK
Content-Length: 458
Content-Type: application/json

{
  "duplicate": false,
  "saved": {
    "checkout_dir": "c1ffb4256878c64eb0e40c48f36d24d2",
    "checksum": null,
    "created": "2024-02-23 15:59:28+01",
    "created_epoch": "1708700368.000000",
    "export_restricted": 0,
    "cla": 0,
    "eula": 0,
    "external_link": "gh#org/package!123",
    "id": 23,
    "imported": "2024-02-23 15:59:28.521134+01",
    "indexed": null,
    "login": null,
    "name": "perl-Mojolicious",
    "obsolete": 0,
    "patent": 0,
    "priority": 5,
    "requesting_user": 1,
    "result": null,
    "reviewed": null,
    "reviewed_epoch": null,
    "reviewing_user": null,
    "source": 1,
    "state": "new",
    "trademark": 0,
    "unpacked": null
  }
}
```

A `checksum` that does not match the uploaded archive is rejected.

```
HTTP/1.1 400 Bad Request
Content-Type: application/json

{
  "error": "Checksum mismatch"
}
```

---

`POST /packages/import/<package_id>`

Re-import package. Usually used to reopen a review after it has already been obsoleted.

**Request parameters:**

* `state` (optional): State to put package review in, currently limited to `new`.

* `priority` (optional): Priority of this package review.

* `external_link` (optional): Short string describing the package source. Configured `external_link_sources` can render
                              values like `obs#123`, `ibs#123`, `soo#org/package!123` and `ssd#org/package!123` as
                              source links with labels.

```
POST /packages/import/23
Authorization: Token configured_access_token_here
Accept: application/json
Content-Length: 22
Content-Type: application/x-www-form-urlencoded

external_link=obs#5678
```

**Request body:**

See request parameters. You can use `application/x-www-form-urlencoded` encoded form values as request body.

**Response:**

```
HTTP/1.1 200 OK
Content-Length: 458
Content-Type: application/json

{
  "imported": {
    "checkout_dir": "236d7b56886a0d2799c0d114eddbb7f1",
    "checksum": null,
    "created": "2024-02-23 15:59:28+01",
    "created_epoch": "1708700368.000000",
    "export_restricted": 0,
    "cla": 0,
    "eula": 0,
    "external_link": 'obs#3734',
    "id": 23,
    "imported": null,
    "indexed": null,
    "login": null,
    "name": "perl-Mojolicious",
    "obsolete": 0,
    "patent": 0,
    "priority": 5,
    "requesting_user": 1,
    "result": null,
    "reviewed": null,
    "reviewed_epoch": null,
    "reviewing_user": null,
    "source": 1,
    "state": "new",
    "trademark": 0,
    "unpacked": null
  }
}
```

---

`GET /package/<package_id>/report.txt`

Get package legal report in plain text format.

**Request parameters:**

None

**Request body:**

None

**Response:**

```
HTTP/1.1 200 OK
Content-Length: 1034
Content-Type: application/json

# Legal Report

Package:  perl-Mojolicious
Checkout: 4fcfdab0e71b0bebfdf8b5cc3badfec4

...
```

### Requests

`POST /requests`

Create request for package.

**Request parameters:**

* `package` (required): Package id.

* `external_link` (required): Short string describing the package source. Configured `external_link_sources` can render
                              values like `obs#123`, `ibs#123`, `soo#org/package!123` and `ssd#org/package!123` as
                              source links with labels.

```
POST /requests
Authorization: Token configured_access_token_here
Accept: application/json
Content-Length: 36
Content-Type: application/x-www-form-urlencoded

external_link=obs#4598459&package=6
```

**Request body:**

See request parameters. You can use `application/x-www-form-urlencoded` encoded form values as request body.

**Response:**

```
HTTP/1.1 200 OK
Content-Length: 29
Content-Type: application/json

{
  "created": 'obs#4598459'
}
```

---

`GET /requests`

List open review requests.

**Request parameters:**

None

**Request body:**

None

**Response:**

```
HTTP/1.1 200 OK
Content-Length: 71
Content-Type: application/json

{
  "requests": [
    {
      "external_link": "openSUSE:Test",
      "packages": [2, 3, 4, 5, 6]
    },
    ...
  ]
}
```

---

`DELETE /requests`

Delete review requests.

**Request parameters:**

* `external_link` (required): Short string describing the package source. Special values like `obs#123`, `ibs#123`,
                              `soo#org/package!123` and `ssd#org/package!123` result in links to
                              `https://build.opensuse.org`, `https://build.suse.de`, `https://src.opensuse.org` and
                              `https://src.suse.de`.

```
DELETE /requests
Authorization: Token configured_access_token_here
Accept: application/json
Content-Length: 26
Content-Type: application/x-www-form-urlencoded

external_link=obs#4598459
```

**Request body:**

See request parameters. You can use `application/x-www-form-urlencoded` encoded form values as request body.

**Response:**

```
HTTP/1.1 200 OK
Content-Length: 71
Content-Type: application/json

{
  "removed": [2, 3, 4, 5, 6]
}
```

### Products

`PATCH /products/<product_name>`

Update packages belonging to product.

**Request parameters:**

* `id` (required): Package ids of all packages belonging to the product.

```
PATCH /products/openSUSE:Test
Authorization: Token configured_access_token_here
Accept: application/json
Content-Length: 15
Content-Type: application/x-www-form-urlencoded

id=2&id=4&id=6
```

**Request body:**

See request parameters. You can use `application/x-www-form-urlencoded` encoded form values as request body.

**Response:**

```
HTTP/1.1 200 OK
Content-Length: 21
Content-Type: application/json

{
  "updated": 12
}
```

---

`DELETE /products`

Delete product.

**Request parameters:**

* `name` (required): Product name.

```
DELETE /products
Authorization: Token configured_access_token_here
Accept: application/json
Content-Length: 23
Content-Type: application/x-www-form-urlencoded

name=openSUSE:Factory
```

**Request body:**

See request parameters. You can use `application/x-www-form-urlencoded` encoded form values as request body.

**Response:**

```
HTTP/1.1 200 OK
Content-Length: 19
Content-Type: application/json

{
  "removed": 1
}
```
