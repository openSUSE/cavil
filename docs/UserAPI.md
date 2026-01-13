# Cavil User API

## REST API

### Authentication

All user API endpoints use bearer tokens you can generate with the "API Keys" menu entry after logging into Cavil.
These bearer tokens are passed with every request via the `Authorization` header.

```
GET /api/v1/whoami
Authorization: Bearer generated_api_key_here
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

You can use any HTTP user-agent to access API endpoints, `curl` for example is great for testing purposes:

```
$ curl -H 'Authorization: Bearer generated_api_key_here' https://legaldb.suse.de/api/v1/whoami
...
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

### Diagnostics

`GET /api/v1/whoami`

Get information about the user this API key belongs to in JSON format.

**Request:**

```
GET /api/v1/whoami
Host: legaldb.suse.de
Authorization: Bearer generated_api_key_here
```

**Response:**

```
HTTP/1.1 200 OK
Content-Length: 24
Content-Type: application/json

{
  "id": 23,
  "user": "tester"
}
```

### Reports

`GET /api/v1/report/<package_id>.<format>`

Get legal report in plain text or JSON format. Note that the exact report format is not static and will change from
time to time.

**Request:**

```
GET /api/v1/report/23.txt
Host: legaldb.suse.de
Authorization: Bearer generated_api_key_here
```

**Response:**

```
HTTP/1.1 200 OK
Content-Length: 1024
Content-Type: text/plain

# Legal Report

Package: perl-Mojolicious
Checkout: c7cfdab0e71b0bebfdf8b2dc3badfecd
Unpacked: 341 files (2.5MiB)

...
```
