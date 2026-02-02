# Cavil User API

## Authentication

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

## MCP API

The [Model Context Protocol](https://modelcontextprotocol.io/) (MCP) is a standard that allows Large Language Models
(LLMs) to interact with web services. MCP is supported natively by Cavil. An MCP endpoint is available with API key
authentication under the path `/mcp`.

Many features have access restrictions, and which are available to you will depend on the type of API key being used
(read-only or read-write), and which roles your user account has assigned.

**Important**: Embargoed package updates cannot be processed with AI and are completely hidden from MCP tools. That
means you have to manually review them in the UI.

Most MCP clients today support Bearer token authentication, so that is what Cavil relies on as well. More
authentication mechanisms will be added as the technology evolves.

This example configuration in the `mcp.json` format, which is commonly used by MCP clients, shows how to include a
Cavil API key by setting the Authorization HTTP header:

```
{
  "mcpServers": {
    "cavil": {
      "url": "https://legaldb.suse.de/mcp",
      "headers": {
        "Authorization": "Bearer generated_api_key_here"
      }
    }
  }
}
```

### 3rd Party MCP Clients

While most MCP clients will work with Cavil, we recommend the use of models specifically designed for legal
professionals.

#### gemini-cli

Once you have installed and set up [gemini-cli](https://github.com/google-gemini/gemini-cli), you can use the gemini
mcp command to add Cavil:

```
gemini mcp add cavil https://legaldb.suse.de/mcp -H 'Authorization: Bearer generated_api_key_here' -t http
```

After restarting gemini-cli, it will automatically discover available Cavil tools and make use of them on its own:

```
╭──────────────────────────────────────────────────────────────────────────────╮
│  > You are a legal reviewer for SUSE Linux Enterprise. Take a look at legal  │
│    report 1 and make a recommendation if that package update should be       │
│    accepted for distribution to customers.                                   │
╰──────────────────────────────────────────────────────────────────────────────╯

 ╭─────────────────────────────────────────────────────────────────────────────╮
 │ ✔ cavil_get_report (cavil MCP Server) {"package_id":1}                      │
 │                                                                             │
 │    ...                                                                      │
 ╰─────────────────────────────────────────────────────────────────────────────╯

✦ Based on my review of the legal report for perl-Mojolicious version 7.25, I
  recommend acceptance of the package for distribution.

  Justification:

   1. Licenses: The package is primarily licensed under the Artistic License
      2.0, with other files covered by compatible and acceptable licenses
      such as Apache-2.0, MIT, and CC-BY-SA-4.0. These are all standard and
      approved open-source licenses.
   2. High-Risk Item: The single file flagged with "Risk 9 (Unknown)",
      Mojolicious-7.25/lib/Mojolicious/Guides/Contributing.pod, is a false
      positive. The flagged text is a standard part of a contributor's guide,
      instructing on code review practices, and is not a license.
   3. No Other Issues: The report does not indicate any other legal
      encumbrances. The email addresses and URLs are standard for an
      open-source project and do not present any concerns.

  The package is legally sound and meets the criteria for inclusion in SUSE
  Linux Enterprise.

```

#### opencode

Once you have installed and set up [opencode](https://opencode.ai/) for use with your preferred model, you can add
Cavil to the "mcp" section of the `opencode.json` config file:

```
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "cavil": {
      "type": "remote",
      "url": "https://legaldb.suse.de/mcp",
      "enabled": true,
      "headers": {
        "Authorization": "Bearer generated_api_key_here"
      }
    }
  }
}
```

After restarting opencode, it will automatically discover available Cavil tools and make use of them on its own:

```
> You are a legal reviewer for SUSE Linux Enterprise. Take a look at report 476346 and make a recommendation if that
> package update should be accepted for distribution to customers. Don't be too critical of legal risks classified as
> low by the license scanner. Only give a short summary with the reason for your decision.

* cavil_get_report [package_id=476346]

Recommendation: Accept the update for distribution.

Reason: The legal report for perl-Mojolicious (report 476346) shows all detected license risks as low. The main license
findings are standard open source licenses (MIT, Artistic-2.0, BSD-3-Clause, CC-BY-SA-4.0, OFL-1.1), which are
compatible with SUSE's distribution policies. There is one unmatched keyword related to mixed license statements, but
it references recognized open source and documentation licenses only. No significant legal or compliance barriers are
present.
```

## REST API

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
  "write_access": false
}
```

### Reports

`GET /api/v1/report/<package_id>.<format>`

Get legal report in plain text or JSON format. Additionally to `txt` and `json`, the extended report format used for
MCP is available with the format identifier `mcp`. Note that the exact report format is not static and will change from
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


## System Notice

Diff to closest match 12345:

  Found new license MIT (risk 1) not present in old report


## Licenses

### Risk 1 (Low)

* BSD-3-Clause: 30 files
* MIT: 10 files
...
```
