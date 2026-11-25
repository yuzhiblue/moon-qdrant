# Changelog

All notable changes to moon-qdrant are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and the project adheres to
[Semantic Versioning](https://semver.org/).

## [0.8.1] - 2026-11-25

### Fixed

- **`rrf_fuse` no longer double-counts duplicate ids within one channel**: a
  merged list containing the same id twice used to add its reciprocal-rank
  contribution twice, letting one duplicated channel outrank genuine agreement
  between two channels. Each channel now contributes at most once.
- **`rrf_fuse` keeps the score and payload from the same hit**: when an id
  appears in several channels, the fused `score` and `payload` now both come
  from the highest-scoring copy, so tenant fields and business keys can no
  longer disagree with the value used to rank the document.
- **`scroll_all` accepts an exact `max_pages` boundary**: consuming the last
  page exactly at `max_pages` used to raise "exceeded max_pages" even when the
  server had already reported completion. The limit is now only enforced
  while more pages remain; repeated offsets are still rejected.

### Added

- Two regression tests for the fusion fixes (89 unit tests total), and an
  exact-boundary export check in `examples/rag_case`.

## [0.8.0] - 2026-11-25

### Added

- **Client-side retrieval semantics layer (`retrieval.mbt`)** — logic the
  Qdrant server does not perform and which is independent of HTTP transport:
  - `rrf_fuse`: reciprocal rank fusion across arbitrary ranked channels
    (different collections, queries or providers), with a total ordering for
    deterministic ties;
  - `dedupe_hits`: keep the best-ranked copy of each business document by a
    payload key (default `doc_id`);
  - `TenantScope`: mandatory tenant condition injection into user filters
    plus verification of returned payloads, so a provider that ignores the
    filter cannot leak another tenant's data;
  - `chunk_points`: bounded batch partitioning for large writes;
  - `scroll_all`: accumulates every scroll page with an explicit safety bound
    against repeated offsets or runaway pagination.
- **`examples/rag_case`**: a multi-tenant enterprise knowledge-base case —
  two retrieval channels, tenant-scoped filters, RRF fusion, deduplication,
  bounded batch writes and paged export. Added to the CI integration workflow.
- 6 unit tests for the new pure logic (87 total).

### Changed

- README now documents the client-side net contribution and the business
  case instead of describing the library as only a 1:1 endpoint mapping.

## [0.7.2] - 2026-11-22

### Changed

- **Upgrade `gaato/mttp` to 0.5.2** and drop the now-unneeded standalone
  `moonbitlang/async` dependency: the old 0.3.0 transport no longer compiles
  under moonc 0.10.22 (shipped by the continuously-updated CI toolchain)
  because of a `FixedArray[Byte]` / `MutArrayView[Byte]` mismatch inside
  mttp's socket layer. API surface is unchanged.
- Replace deprecated `Int64::from_int` / `Double::from_int` calls with
  `Int::to_int64` / `Int::to_double` so `moon check --deny-warn` stays clean
  on current toolchains.

## [0.7.1] - 2026-11-22

### Fixed

- **`parse_int64` no longer wraps values above `Int64::max`**: they now
  return `None`, so a Qdrant point id or count above 2^63-1 fails loudly
  instead of silently becoming a negative id that would target the wrong
  point on later reads/deletes. (Such ids still cannot be represented by
  this client; they are simply no longer corrupted.)
- **`upsert_points_batch` collects named-vector keys from every point**,
  not just the first. A vector name that only appeared on later points in
  the batch was silently dropped from the request.
- **`CollectionUpdate::to_json` keeps both dense and named vector configs**
  when both are set: the unnamed config is written under the `""` key of
  the same `vectors` object instead of being overwritten.
- **`PayloadIndexInfo::from_json` reads Qdrant's real descriptor shape**
  (`{data_type, points, params, ...}`), including `field_name` when present;
  the legacy `field_schema` key is still honoured.
- **`url_encode` replaces lone surrogates with U+FFFD** instead of emitting
  invalid UTF-8 for malformed UTF-16 input.

### Changed

- The payload-index parse test no longer depends on map iteration order.

## [0.7.0] - 2026-11-12

### Breaking

- **Counting fields are now `Int64`** (Qdrant reports them as u64):
  `count_points`, `CollectionInfo.points_count`, `SnapshotInfo.size` and
  `FacetHit.count`. Counts above 2^31-1 no longer saturate.
- **Peer ids are now decimal `String`s.** Qdrant peer ids are random u64
  values and roughly half of them exceed `Int64::max`, where the previous
  `Int64` representation wrapped silently. `ClusterInfo.peer_id`,
  `RaftInfo.leader`, `CollectionClusterInfo.peer_id`,
  `RemoteShardInfo.peer_id`, `ShardTransferInfo.from` / `.to` and the peer
  arguments of `replicate_shard` / `create_shard_replica` /
  `delete_shard_replica` / `collection_cluster_op_body` now carry the exact
  decimal text; request bodies serialize it back as an exact JSON number
  (`peer_id_to_json`), so ids beyond 2^63 round-trip losslessly. New
  `u64_text_of_json` helper.
- **`PayloadIndexInfo` now surfaces the real index descriptor**: new
  `field_name` (previously smuggled into `field_schema`) and `points_count`
  fields; `field_schema` is now the descriptor object exactly as Qdrant
  reports it (including `data_type`, `points` and index `params`) instead of
  the field name string.

### Changed

- Dependencies follow gaato's rename: `gaato/mttp_async@0.1.0` +
  `gaato/mttp@0.2.0` → `gaato/mttp@0.3.0` (the 0.2 modules are deprecated;
  0.3.0 keeps the same API shape under one module).

### Fixed

- **`url_encode` supports supplementary-plane characters**: emoji and other
  astral characters arrive as UTF-16 surrogate pairs and were previously
  percent-encoded as two broken 3-byte sequences; they are now combined into
  their full code point and encoded as 4-byte UTF-8.
- **`collection_info` surfaces named-vector configs**: for named-vector
  collections `CollectionInfo.named_vectors` maps each vector name to its
  `VectorParams` (previously `vectors` was `None` and the per-name config was
  dropped). Dense collections keep using `vectors`.
- The demo uses a 60s timeout so snapshot creation on slow filesystems is
  not mistaken for a transport failure.

## [0.6.0] - 2026-11-12

### Changed

- **HTTP transport migrated from `oboard/mio@0.5.4` to `gaato/mttp_async@0.1.0`**
  (+ `gaato/mttp@0.2.0`, `moonbitlang/async@0.22.9`). The public API surface is
  unchanged; only the `QdrantClient.http` field's type changed (it was never
  externally constructible). Gains:
  - the dependency tree is fully current (no legacy-manifest / `try?` sources),
    so `moon publish` to mooncakes.io works again — the bikallem/compress CI
    patch (`scripts/compress-patch/`) and the workflow migrate-legacy loop were
    removed;
  - gzip/deflate/br/zstd responses are decompressed correctly, so the old
    `Accept-Encoding: identity` workaround is gone;
  - retries with a retry budget, per-attempt (`timeout_ms`) and whole-call
    deadlines, and redirects are now handled by the transport.
- `QdrantClient::close()` is new: release the client's connection pool.

## [0.5.1] - 2026-11-12

### Fixed

- **Point ids above 2^53 are no longer rounded on the wire**:
  `delete_points` and `retrieve_points` built their id arrays with
  `Json::number(id.to_double())`, which turns `9007199254740993` into
  `9007199254740992` — a read returned the neighbouring point and a delete
  removed it. Both now use the new `point_ids_to_json` helper (shared with the
  payload selectors), which keeps the exact decimal text via `int64_to_json`.
  Response decoding is pinned by a test that parses a real
  `{"id":9007199254740993,...}` payload.
- **Collection cluster / shard operations no longer get HTTP 400**: Qdrant's
  `ClusterOperations` is an untagged enum of single-key objects, e.g.
  `{"replicate_shard":{"shard_id":0,"from_peer_id":1,"to_peer_id":2}}`. The
  client sent a flat `{"method":"replicate_shard", ...}` body, which matches
  no variant. `collection_cluster_op_body` now emits the required wrapping.
  `create_shard_replica` / `delete_shard_replica` were also not real Qdrant
  operation names; they now map to `replicate_shard` and `drop_replica`.
  `create_shard_replica` accepts an optional `from_peer_id~`; when it is
  omitted the new `shard_source_peer` helper looks up a peer holding the
  shard. The previous `0` default made Qdrant answer
  `400 Peer 0 does not exist` on real clusters. On a single node Qdrant
  still answers cluster operations with `400 Distributed mode disabled`;
  that is a server-side limit, not the malformed-body 400 above.
- **Integration check no longer times out on slow filesystems**: creating a
  collection snapshot took >10s against a local Windows Qdrant while the
  client default was 10s, so a successful 200 was reported as a transport
  error. The check now uses a 60s timeout.
- **Reads with `with_vector=false` / `with_payload=false` no longer look like
  missing points**: Qdrant omits those keys, but `PointStruct::from_json`
  required `vector` and returned None, so `get_point` reported a 404 and
  `retrieve_points` / `scroll_points` raised on perfectly valid results.
  Missing or null `vector` / `payload` now parse as an empty vector / empty
  payload object. Verified against a live Qdrant.
- **Batch upsert rejects dense/named mixes in both orders**: the check only
  ran when the first point had named vectors; a dense-first batch silently
  emitted zero-dimensional vectors for its named points.

### Added

- `point_ids_to_json` and `shard_source_peer` public helpers; unit tests for large-id wire text,
  response decoding and cluster op bodies; a real-Qdrant integration check
  that upserts / reads / retrieves / deletes id `9007199254740993` next to
  its neighbour `9007199254740992`.

### Known limitations

- Counting fields (`count_points`, `CollectionInfo.points_count`,
  `SnapshotInfo.size`, `FacetHit.count`) are `Int32` and saturate above
  2^31-1, while Qdrant reports them as u64. Fixing this needs a breaking
  change to `Int64`.
- Qdrant peer ids are random u64 values; ids above `Int64::max` wrap during
  parsing because the client models them as `Int64`.
- `url_encode` covers BMP characters only; collection names containing
  supplementary-plane characters (emoji) are percent-encoded incorrectly.
- `collection_info().vectors` is `None` for named-vector collections; the
  per-name vector config is not surfaced.
- `list_payload_indexes()` puts the field name into `field_schema`; the
  real index descriptor is dropped.

## [0.5.0] - 2026-10-13

### Breaking

- **Point ids are now `Int64`** (was `Int32`), matching Qdrant's u64 point
  ids. `PointStruct.id`, `ScoredPoint.id`, the `id` argument of `get_point`,
  the `ids` arguments of `delete_points` / `retrieve_points` / payload
  operations, and the scroll `offset` are all `Int64`. Ids beyond the 32-bit
  range now round-trip exactly instead of being silently truncated; large-id
  round trips are covered by unit and real-server integration tests.

## [0.4.6] - 2026-10-13

### Fixed

- **health() no longer raises on transport failures**: a server that is down
  or unreachable now reports `false` (unhealthy) instead of propagating a
  network error, so readiness probes can safely rely on the Bool return.
- **Dense vector updates serialized for current Qdrant**: PATCH
  `/collections/{name}` now sends `{"vectors": {"": {size, distance}}}` as
  required by Qdrant >= 1.13 (a vector name is mandatory in updates); the
  previous bare params object was rejected.
- **URL encoding for path segments**: collection, field and snapshot names
  are now percent-encoded, so names containing spaces or reserved
  characters no longer corrupt the request URL.

### Added

- `url_encode/1` public helper; new unit tests for the dense update wire
  shape and URL encoding; the integration check now exercises
  `update_collection` against a real server.

## [0.4.5] - 2026-10-13

### Fixed

- **Batch vector layout for named-vector points**: the column-oriented batch
  body now transposes named vectors into an object mapping each vector name
  to the array of per-point vectors (e.g. `{"text": [[...], [...]]}`).
  Previously each named point's `{name: [...]}` vector object was emitted
  inside the array, which Qdrant rejected with
  `400: data did not match any variant of untagged enum BatchVectorStruct`.
- **Dense batch test assertions corrected** (verified against a real Qdrant
  instance in CI: 3 base points + 2 batch points = 5, 3 after cleanup).



### Fixed

- **Batch upsert now targets `PUT /collections/{name}/points`** with the
  column-oriented `{"batch": {ids, vectors, payloads}}` body (the classic
  batch loading endpoint). The previous `POST /points/batch` attempt hit the
  newer multi-operation endpoint, which expects `{"operations": [...]}` and
  rejected the batch body with `400 missing field operations`. This was
  caught by the real-Qdrant integration test.



### Changed

- **Migrated to the new-style MoonBit syntax** required by toolchains
  `>= 0.1.20261012` (moonc `v0.10.15`): optional named parameters now use
  `~` (was `?`) and `Int` is now `Int32` throughout the public API. The
  migration was applied with `moon fmt`; the API shape is unchanged.
- **CI now migrates the legacy `moon.mod.json` manifests** of the transitive
  dependencies `bikallem/blit` and `bikallem/compress` (no newer upstream
  release exists) before building, so the project stays green on the latest
  toolchain.



### Fixed

- **Batch upsert now uses `POST /collections/{name}/points/batch`** instead of
  `PUT`. The batch endpoint only accepts POST; the previous method returned
  404 for both dense and named-vector points. Named-vector points keep their
  `{ "name": [...] }` vector objects (regression fixed in 0.4.1 on GitHub
  main but not shipped to mooncakes).
- **`set_payload` / `overwrite_payload` no longer swapped**: `set_payload`
  now uses `POST /points/payload` (merge: keeps existing fields) and
  `overwrite_payload` uses `PUT /points/payload` (replace: removes fields
  absent from the new object). Previously the two methods were reversed and
  `set_payload` silently dropped existing payload fields.
- **`delete_payload` now targets `POST /points/payload/clear`** (the clear
  payload endpoint) with a body that contains only the point selector
  (`points` or `filter`). The previous implementation hit `/payload/delete`
  with a stray `"payload": {}` field, which Qdrant rejects with 400.
- **`delete_payload_by_keys` no longer sends the stray `"payload": {}`**
  field; the body is now `{ "keys": [...], "points" | "filter": ... }`.
- **Peer and shard ids are serialized losslessly**: `int64_to_json` keeps the
  exact decimal text via the JSON number `repr`, so u64 peer ids beyond 2^53
  are no longer rounded to a different value. Replicate / create / delete
  shard replica operations now send valid ids (previously 400 on
  distributed clusters).

### Changed

- Integration check now covers batch upsert (dense and named-vector),
  set/overwrite merge-vs-replace semantics, and full payload deletion
  against a real Qdrant server.
- Added a unit test pinning `int64_to_json` to the exact decimal text.

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
