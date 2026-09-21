# Changelog

All notable changes to moon-qdrant are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and the project adheres to
[Semantic Versioning](https://semver.org/).

## [0.4.1] - 2026-09-21

### Changed

- The collection write lock was reworked to Qdrant's real service-wide API:
  `collection_lock` / `set_collection_lock` are replaced by `get_locks` /
  `set_locks` (`GET|POST /locks`). Qdrant locks are global, not
  per-collection.
- `service_info` now reads `GET /` (a bare object with `title` / `version` /
  `commit`); the previous `GET /service` path does not exist.
- `list_aliases` now calls `GET /aliases`; `GET /collections/aliases` is not
  a listing endpoint.
- `list_payload_indexes` reads the `payload_schema` of
  `GET /collections/{name}`; Qdrant has no dedicated list-indexes endpoint.
- `ClusterInfo` tolerates single-node responses
  (`{"result":{"status":"disabled"}}`): `peer_id` defaults to `0` and
  `peers` to an empty map when absent.
- `search_points` with `using_vector` embeds the vector name in the vector
  object (`{"name": ..., "vector": [...]}`); the search API has no
  top-level `using` field.

### Fixed

All found by the integration workflow, which runs every client method
against a real Qdrant 1.15.5 container on each push:

- `health()` no longer JSON-parses the plain-text `/healthz` body.
- Requests explicitly send `Accept-Encoding: identity`, avoiding a mio
  deflate-decompression crash on compressed API responses.
- `search_points` sends `limit` in the JSON body (it is not a query
  parameter).
- `MatchKeyword` serializes as `match.value`; Qdrant has no
  `match.keyword`.
- Query-API responses with the `result.points` object shape are accepted in
  addition to plain arrays.
- Facet counts use `POST /collections/{name}/facet` (not
  `/points/facet`), and facet / grouped-search checks create the required
  keyword payload index first.
- Payload index endpoints are `PUT|GET /collections/{name}/index` and
  `DELETE /collections/{name}/index/{field_name}` (not `/indexes`);
  `create_payload_index` sends `field_name` / `field_schema`.
- `delete_payload_by_keys` sends the `keys` array (not `payload`).
- JSON parse errors include the HTTP status, path and a preview of the raw
  response, so integration failures on a real server are diagnosable from
  CI logs.
- The demo runs end to end against a real server (facet index creation and
  named-vector search fixed).

## [0.4.0] - 2026-09-21

### Added

- Named (multi-) vector support:
  - `CollectionConfig::new_named` — create a collection with several named
    vector configurations (e.g. `text` + `image`) in one call;
  - `PointStruct::new_named` — upsert points carrying several vectors;
  - `search_points(..., using_vector=...)` and `search_points_named` — run a
    query against one specific named vector of the collection;
- Advanced search options on `search_points` / `search_points_with_filter`:
  `score_threshold` (keep hits above a score), `offset` (pagination),
  `search_params` (`SearchParams` with `hnsw_ef` and `exact`);
- `search_points_batch` — several searches in one round trip via
  `POST /collections/{name}/points/search/batch`;
- Payload management: `set_payload` (merge), `overwrite_payload` (replace),
  `delete_payload` (whole payload) and `delete_payload_by_keys` (selected
  keys), each selectable by ids or filter;
- `update_collection` — `PATCH /collections/{name}` with `CollectionUpdate`
  (vectors / named vectors / replication_factor / write_consistency_factor);
- Payload indexes: `create_payload_index`, `delete_payload_index`,
  `list_payload_indexes`;
- Snapshots: `list_snapshots`, `create_snapshot`, `delete_snapshot`;
- Query API (`POST /collections/{name}/points/query`): `query_nearest`,
  `query_recommend` and a raw `query_points` for advanced queries;
- Facet counts: `facet_points` with `FacetHit` / `FacetResult` models;
- Grouped search: `search_points_groups` with `ScoredPointGroup` model;
- Collection write lock: `collection_lock` / `set_collection_lock` with
  `CollectionLock` model;
- Server info: `service_info` with `ServiceInfo` model;
- Cluster: `cluster_info` with `ClusterInfo` / `PeerInfo` / `RaftInfo`
  models, `collection_cluster_info` with `CollectionClusterInfo` /
  `LocalShardInfo` / `RemoteShardInfo` / `ShardTransferInfo` models, and
  shard operations `replicate_shard` / `create_shard_replica` /
  `delete_shard_replica`;
- CI now runs `moon check --target native --deny-warn`;
- New `integration.yml` workflow runs `examples/integration_check` (asserts
  every client method against a real Qdrant container) and the demo end to
  end on every push;
- Data models: `NamedVector`, `SearchParams`, `SnapshotInfo`,
  `PayloadIndexInfo`, `CollectionUpdate`, `FacetHit`, `FacetResult`,
  `ScoredPointGroup`, `CollectionLock`, `ServiceInfo`, `ClusterInfo`,
  `PeerInfo`, `RaftInfo`, `CollectionClusterInfo`, `LocalShardInfo`,
  `RemoteShardInfo`, `ShardTransferInfo` with JSON conversion and parsing;
  u64 ids (peer ids, shard ids) are decoded from their exact textual
  representation via `parse_int64` / `int64_of_json`;
- 35 new unit tests (serialization, parsing, request-body construction and
  malformed-input guards for all of the above), demo extended to exercise
  every new capability.

### Changed

- Adapted to the 2026-09-20 MoonBit toolchain: the `VectorProvider`
  implementation is now free of deprecated implicit method promotion, and
  tests qualify package symbols with `@moon-qdrant.*`; `moon check --deny-warn`
  passes cleanly.
- The README was renamed from `README.mbt.md` to `README.md` so GitHub
  renders it on the repository homepage; `moon.mod` now points `readme` at
  the new name.

## [0.3.0] - 2026-09-20

### Added

- `new` accepts an optional `timeout_ms` (default 10 000).
- Write operations accept `wait? : Bool = true` (`upsert_points`,
  `upsert_points_batch`, `delete_points`, `delete_points_by_filter`);
  pass `wait=false` to return without waiting for server-side propagation.
- Read operations expose `with_payload` / `with_vector` as optional
  parameters (`get_point`, `retrieve_points`, `scroll_points`,
  `search_points`, `search_points_with_filter`).
- Error messages now include the request path that failed.

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
[0.2.0]: https://github.com/yuzhiblue/moon-qdrant/releases/tag/v0.2.0
[0.3.0]: https://github.com/yuzhiblue/moon-qdrant/releases/tag/v0.3.0
[0.4.0]: https://github.com/yuzhiblue/moon-qdrant/releases/tag/v0.4.0
