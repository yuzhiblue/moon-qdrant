# Changelog

All notable changes to moon-qdrant are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and the project adheres to
[Semantic Versioning](https://semver.org/).

## [Unreleased]

- Planned: publish to mooncakes.io, API docs polish.

## [0.1.0] - 2026-09-17

Initial release targeting the September MoonBit hackathon.

### Added

- `QdrantClient` over `oboard/mio` with `api-key` header support:
  - `health()` — `GET /healthz`
  - `list_collections()` — `GET /collections`
  - `create_collection()` — `PUT /collections/{name}`
  - `collection_info()` — `GET /collections/{name}`
  - `delete_collection()` — `DELETE /collections/{name}`
  - `collection_exists()` — `GET /collections/{name}` (404 → false)
  - `upsert_points()` — `PUT /collections/{name}/points`
  - `upsert_points_batch()` — `PUT /collections/{name}/points/batch`
  - `get_point()` — `GET /collections/{name}/points/{id}` (404 → None)
  - `delete_points()` — `POST /collections/{name}/points/delete`
  - `search_points()` — `POST /collections/{name}/points/search`,
    with optional payload filter
- Data models with JSON conversion: `Distance`, `VectorParams`,
  `CollectionConfig`, `CollectionInfo`, `CollectionList`,
  `PointStruct`, `ScoredPoint`
- `VectorProvider` trait implemented by `QdrantClient` for a
  service-agnostic interface
- End-to-end example (`examples/demo`) and health-check CLI (`cmd/main`)
- 12 unit tests covering serialization and response parsing
- CI workflow (ubuntu / macos / windows): check, test, fmt, info

[0.1.0]: https://github.com/yuzhiblue/moon-qdrant/releases/tag/v0.1.0
