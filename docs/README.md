# Documentation

For an introduction to Cavil itself, and a quick development environment to try it in, see the
[project README](../README.md).

The [**Architecture**](Architecture.md) overview is the best starting point for how Cavil actually works: the
components and how they communicate, the review workflow and access levels, pattern matching and automated snippet
resolution, and SBOM generation.

### Reviewing and curating

* [License Pattern Lifecycle](PatternLifecycle.md)

  A plain-language guide, written for lawyers and reviewers, to how a piece of text becomes a reusable license
  pattern — the review queues, who proposes what, and what "missing license" means.

* [User API](UserAPI.md)

  Legal reports and SPDX documents over HTTP, the MCP endpoint for AI assisted review, and the agent skills that ship
  with Cavil for triaging the review queue.

* [Contributors](Contributors.md)

  The contributor workflow for volunteers to help with curating license patterns.

### Running an instance

* [Setup](Setup.md)

  A guide to setting up a fresh Cavil instance for production.

* [Maintenance](Maintenance.md)

  Steps to keep your Cavil instance running smoothly.

* [Bot API](BotAPI.md)

  The REST API bots use to connect Cavil with source code management systems such as the Open Build Service and Gitea.
