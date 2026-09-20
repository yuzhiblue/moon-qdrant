# Changelog

All notable changes to moon-qdrant are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and the project adheres to
[Semantic Versioning](https://semver.org/).

## [Unreleased]

- Planned: API docs polish.

## [0.2.0] - 2026-09-20

### Added

- Typed payload filter DSL: `Condition` (match_value / match_keyword /
  match_values / range / is_empty / is_null) and a `Filter` builder over
  `must` / `should` / `must_not`, with `search_points_with_filter` as the
  type-safe search entry point;
- `scroll_points` — `POST /collections/{name}/points/scroll`, paginated
  point listing with filter and offset;
- `count_points` — `POST /collections/{name}/points/count`, exact or
  estimated count with optional filter;
- `retrieve_points` — `POST /collections/{name}/points`, batch fetch by ids;
- `delete_points_by_filter` — bulk delete via a `Filter`;
- `create_alias` / `delete_alias` / `list_aliases` — collection alias
  management via `/collections/aliases`;
- The end-to-end demo now exercises all of the above.

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

## 0.3.0

- `new` accepts an optional `timeout_ms` (default 10 000).
- Write operations accept `wait? : Bool = true` (`upsert_points`,
  `upsert_points_batch`, `delete_points`, `delete_points_by_filter`);
  pass `wait=false` to return without waiting for server-side propagation.
- Read operations expose `with_payload` / `with_vector` as optional
  parameters (`get_point`, `retrieve_points`, `scroll_points`,
  `search_points`, `search_points_with_filter`).
- Error messages now include the request path that failed.
