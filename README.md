# yuzhiblue/moon-qdrant

[![CI](https://github.com/yuzhiblue/moon-qdrant/actions/workflows/check.yml/badge.svg)](https://github.com/yuzhiblue/moon-qdrant/actions/workflows/check.yml)
[![Integration](https://github.com/yuzhiblue/moon-qdrant/actions/workflows/integration.yml/badge.svg)](https://github.com/yuzhiblue/moon-qdrant/actions/workflows/integration.yml)

A MoonBit client for the [Qdrant](https://qdrant.tech/) vector database REST API.

moon-qdrant lets MoonBit programs manage Qdrant collections, upsert points,
and run vector searches without leaving the MoonBit ecosystem. It is built on
`gaato/mttp` for HTTP transport (HTTP/1.1 with retries, deadlines and
transparent compression), the MoonBit core JSON library, and adds a
client-side retrieval layer for tenant isolation, multi-channel fusion,
deduplication and bounded batch writes.

## Positioning: reuse boundary and net contribution

Several MoonBit packages now overlap with parts of this project. We state the
boundary explicitly instead of claiming a gap that no longer exists.

| Existing package | What it already provides | What this project does **not** claim |
|---|---|---|
| `lexchb/moon_vector` (0.1.1) | Qdrant REST v2 through a `VectorStore` trait, typed filters including geo/nested, in-memory local backend, `PointId = Num(UInt64) \| Uuid` | First Qdrant client; broadest filter DSL |
| `moonbitstack/moonqdrant` (0.1.1) | Qdrant as a `moonrag` `VectorStore` (7 methods), cosine recomputed locally | RAG pipeline, embeddings, chunking |
| `niuniu513-ask/MoonRetrieve` (0.6.0) | Zero-FFI local tokenisation (zh/en/jp), BM25 inverted index, RRF hybrid search | BM25, tokenisation, local-first search |
| `heyq02/moomem`, `NaIWaniubi/moonseek`, `walkzzz/agentskills.mbt` | Vector + BM25 with RRF, full-text engines, exported `rrf_fuse` | Generic RRF algorithm |
| `trkbt10/vcdb` (0.3.2) | A vector database server (HNSW / IVF) with a REST-style gateway | Being a vector engine or server |

After subtracting that overlap, the net contribution is:

1. **Qdrant operations coverage.** Cluster / shard operations, service write
   locks, snapshots, aliases, facets, grouped and batch search, payload-index
   management, the Query API and service info. The other Qdrant packages
   expose roughly 7–11 store methods and none of these admin endpoints.
2. **A tenant-safety envelope** (`TenantScope`) that both injects the
   mandatory `tenant_id` condition and verifies returned payloads, so a
   provider that silently ignores a filter cannot leak another tenant's data.
3. **A stable cross-channel result contract** (`RankedHit`) with total
   ordering, one RRF contribution per channel even for duplicate ids,
   score/payload pairing from the same hit, and business-key deduplication
   (`dedupe_hits`). The RRF arithmetic itself is standard and is not claimed
   as a novel algorithm.
4. **Bounded I/O helpers** (`chunk_points`, `scroll_all`) with an explicit
   page bound and repeated-offset detection.
5. **Exact `u64` wire handling** for point ids and peer ids, including ids
   above 2^53 that a JSON `Double` cannot represent exactly.

The lexical channel is deliberately **not** implemented by this library:
tokenisation and BM25 already exist in `MoonRetrieve`. `examples/rag_case`
uses a small literal term scorer only to show how an external lexical channel
plugs into the `RankedHit` contract; a production pipeline can feed
`MoonRetrieve`'s BM25 scores in unchanged.

## What Qdrant does and what this client does

Qdrant already implements vector search, payload filtering, scroll pagination,
named vectors, and **server-side RRF** through Query API `prefetch` plus
`fusion` (`rrf` / `dbsf`). That fusion is scoped to prefetches inside one
query against one collection. This library does not reimplement those server
capabilities. It handles only work that crosses a request or provider
boundary:

| Concern | Qdrant server | moon-qdrant client |
|---|---|---|
| Vector similarity, payload filter, one scroll page | yes | builds requests, parses responses |
| RRF inside one Query API call | yes (`fusion: "rrf"`) | not used |
| RRF across independent collections, queries or providers | not one request | `rrf_fuse` |
| Tenant condition and verification of returned payloads | filter only | `TenantScope` injects **and** verifies |
| Business-document deduplication across channels | no | `dedupe_hits` |
| Batch-size bound, all-page accumulation | one page at a time | `chunk_points`, `scroll_all` |
| Exact `u64` ids / peer ids over JSON | wire-defined | `Int64` plus textual `repr` |

CI runs the full end-to-end suite against both `qdrant/qdrant:v1.15.5` and
`v1.20.2`. The service `/locks` assertions are version-gated: Qdrant
deprecated that endpoint in 1.15 and removed it in 1.16, so they run only on
the older server. Everything else is asserted on both versions.

## Recall channels: input and output

The concrete case below is exercised by `retrieval_test.mbt` and
`examples/rag_case/main.mbt`. The pure channel logic is verified by
`moon test`; only the Qdrant round trip needs a server.

The example inserts a second point with the same `doc_id` as `kb-004` so
deduplication is observable. Scores below are from a real Qdrant 1.20.2 run.

**Semantic channel**
- input: vector `[0.1, 0.2, 0.3, 0.4]`, filter `tenant_id=acme AND lang=zh`
- output: `kb-001` (1.0000), `kb-002` (0.9938), `kb-003` (0.9844),
  `kb-004` (0.9759), `kb-004` duplicate (0.9722)

**Lexical channel**
- input: terms `["retrieval", "recall"]`, same tenant filter
- output: `kb-004` (1.0), its duplicate (1.0), `kb-002` (0.5); `kb-001` is not
  a term hit at all

The two channels disagree on the top hit, which is why a single score scale
cannot decide the answer.

**Client fusion** (`rrf_fuse`, k=60, limit=5)
- input: the two ranked lists above
- output (RRF score): `kb-004` (0.032018, 2 sources), `kb-002` (0.032002,
  2 sources), `kb-004` duplicate (0.031514, 2 sources), `kb-001` (0.016393,
  1 source), `kb-003` (0.015873, 1 source)

**Tenant guard + deduplication**
- input: fused list plus a foreign-tenant document
- output: the foreign document is dropped; the two `kb-004` copies collapse
  into one

## Install

```bash
moon add yuzhiblue/moon-qdrant
```

## Quick start

Start a local Qdrant server (Docker):

```bash
docker run -p 6333:6333 qdrant/qdrant
```

Then use the client:

```moonbit nocheck
let client = QdrantClient::new("http://localhost:6333")

// health check
let ok = client.health()

// create a collection with 4-dimensional cosine vectors
client.create_collection(
  "demo",
  CollectionConfig::new(VectorParams::new(4, Distance::Cosine)),
)

// list collections
let names = client.list_collections()

// inspect a collection
let info = client.collection_info("demo")

// does it exist?
let exists = client.collection_exists("demo")

// write some points
client.upsert_points("demo", [
  PointStruct::new(1, [0.1, 0.2, 0.3, 0.4], { "tag": "alpha" }),
  PointStruct::new(2, [0.5, 0.6, 0.7, 0.8], { "tag": "beta" }),
])

// ids are Int64, matching Qdrant's u64 point ids. Even ids above 2^53,
// where a Double can no longer hold every integer, round-trip exactly:
client.upsert_points("demo", [
  PointStruct::new(
    9007199254740993L,
    [0.2, 0.3, 0.4, 0.5],
    { "tag": "big" },
  ),
])

// read one back
let point = client.get_point("demo", 1)

// search for the most similar points
let hits = client.search_points("demo", [0.1, 0.2, 0.3, 0.4], limit=2)

// search with a payload filter
let filtered = client.search_points(
  "demo",
  [0.1, 0.2, 0.3, 0.4],
  limit=2,
  filter={ "must": [{ "key": "tag", "match": { "value": "alpha" } }] },
)

// delete points by id
client.delete_points("demo", [2])

// drop the collection
client.delete_collection("demo")
```

### Advanced search

`search_points` accepts optional `score_threshold` (keep only hits above a
score), `offset` (pagination), `using_vector` (pick a named vector to query
against) and `search_params` (HNSW tuning / exact search):

```moonbit nocheck
// only hits scoring 0.9 or better, skipping the first hit

///|
let hits = client.search_points(
  "demo",
  [0.1, 0.2, 0.3, 0.4],
  2,
  score_threshold=Some(0.9),
  offset=Some(1),
  search_params=Some(SearchParams::new(exact=Some(true))),
)

// several searches in one round trip

///|
let batch = client.search_points_batch("demo", [
  { "vector": [0.1, 0.2, 0.3, 0.4], "limit": 2 },
  { "vector": [0.9, 0.8, 0.7, 0.6], "limit": 2 },
])
```

### Named vectors

Qdrant collections can store several vectors per point. moon-qdrant supports
this end to end: create the collection with named configurations, upsert
points with several vectors, and search against one of them.

```moonbit nocheck
let named : Map[String, VectorParams] = Map([])
named["text"] = VectorParams::new(4, Distance::Cosine)
named["image"] = VectorParams::new(8, Distance::Dot)
client.create_collection("multi", CollectionConfig::new_named(named))

let vectors : Map[String, Array[Double]] = Map([])
vectors["text"] = [0.1, 0.2, 0.3, 0.4]
vectors["image"] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]
client.upsert_points("multi", [PointStruct::new_named(1, vectors, { "tag": "a" })])

// search against the "text" vector
let hits = client.search_points(
  "multi",
  [0.1, 0.2, 0.3, 0.4],
  1,
  using_vector=Some("text"),
)
// or via a NamedVector input
let hits = client.search_points_named(
  "multi",
  NamedVector::new("image", [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]),
  1,
)
```

### Payload management

```moonbit nocheck
// merge fields into the payload of points 1 and 2
client.set_payload("demo", { "active": true }, ids=Some([1, 2]))
// replace the whole payload of points matching a filter
client.overwrite_payload(
  "demo",
  { "state": "new" },
  filter=Some(Filter::new().must(Condition::match_keyword("tag", "alpha"))),
)
// drop selected keys from point 1
client.delete_payload_by_keys("demo", ["active"], ids=Some([1]))
// drop the whole payload of all points matching a filter
client.delete_payload("demo", filter=Some(Filter::new()))
```

### Query API and facets

The Qdrant query API (`POST /collections/{name}/points/query`) is exposed
through `query_nearest` (nearest neighbor) and `query_recommend`
(recommendation from positive / negative examples), plus a raw `query_points`
for advanced queries:

```moonbit nocheck
// nearest neighbor
let hits = client.query_nearest("demo", [0.1, 0.2, 0.3, 0.4], 2)

// recommendation: like the positive vectors, unlike the negative ones
let positive : Array[Json] = [
  Json::array([0.1, 0.2, 0.3, 0.4]),
  Json::number(3), // point ids are accepted too
]
let negative : Array[Json] = [Json::array([0.9, 0.8, 0.7, 0.6])]
let recs = client.query_recommend(
  "demo",
  positive,
  negative=Some(negative),
  limit=5,
)

// facet: how many points carry each distinct value of a payload field
let facet = client.facet_points("demo", "tag", 10)
for hit in facet.hits {
  println(hit.value.stringify() + ": " + hit.count.to_string())
}

// grouped search: top hits per distinct payload value
let groups = client.search_points_groups(
  "demo",
  [0.1, 0.2, 0.3, 0.4],
  2,     // hits per group
  "tag", // group-by field
  10,    // max groups
)
for group in groups {
  println(
    "group " + group.id.stringify() + " -> " +
    group.hits.length().to_string() + " hits",
  )
}
```

### Cluster, locks and server info

```moonbit nocheck
// cluster state (works on single-node deployments too)
let cluster = client.cluster_info()
println("cluster status: " + cluster.status)
println("peers: " + cluster.peers.length().to_string())

// per-collection shard / replica layout
let layout = client.collection_cluster_info("demo")
for shard in layout.local_shards {
  println(
    "shard " + shard.shard_id.to_string() + ": " +
    shard.state + " (" + shard.points_count.to_string() + " points)",
  )
}

// shard lifecycle (multi-node clusters). Qdrant's cluster API takes a
// single-key operation object; `create_shard_replica` maps to the
// `replicate_shard` operation and `delete_shard_replica` to `drop_replica`,
// the operation names Qdrant actually accepts. The source peer is looked up
// automatically; pass `from_peer_id=...` to override. A single-node server
// answers any cluster operation with "Distributed mode disabled" — that is a
// server limit, not a malformed request.
client.replicate_shard("demo", 0L, 1L, 2L)
client.create_shard_replica("demo", 0L, 2L)
client.delete_shard_replica("demo", 0L, 2L)

// write lock + server version. The /locks calls work only on Qdrant ≤ 1.15;
// the endpoint was removed in 1.16. Check service_info().version first.
client.set_locks(true, error_message=Some("maintenance"))
let lock = client.get_locks()
println("writes locked: " + lock.write.to_string())
let info = client.service_info()
match info.version {
  Some(v) => println("qdrant version: " + v)
  None => ()
}
```

### Collection updates, payload indexes and snapshots

```moonbit nocheck
// update replication settings
client.update_collection(
  "demo",
  CollectionUpdate::new(replication_factor=Some(2)),
)

// index a payload field for fast filtered access
client.create_payload_index("demo", "tag", "keyword")
let indexes = client.list_payload_indexes("demo")
client.delete_payload_index("demo", "tag")

// snapshot the collection for backup / migration
let snap = client.create_snapshot("demo")
let snapshots = client.list_snapshots("demo")
client.delete_snapshot("demo", snap.name)
```

## Examples

Health-check CLI (needs a running Qdrant server):

```bash
moon run cmd/main -- http://localhost:6333
```

End-to-end demo: create collection, upsert points, search (with and without
a payload filter), read a point, delete points, drop the collection:

```bash
docker run -p 6333:6333 qdrant/qdrant
moon run examples/demo -- http://localhost:6333
```

Multi-tenant hybrid retrieval case: a dense-vector semantic channel and a
literal-term lexical channel over the same tenant-scoped collection, followed
by RRF fusion, tenant verification, deduplication and paged export. The run
prints each channel's input and output before the fused result:

```bash
moon run examples/rag_case -- http://localhost:6333
```

## Retrieval semantics (client-side)

Qdrant performs vector search, filtering and pagination; it also offers
server-side RRF inside a single Query API call. The following work happens in
`retrieval.mbt` because it spans channels or requests:

- `rrf_fuse` — rank fusion of several independently produced lists; the
  arithmetic is standard RRF, the contribution here is the cross-channel
  `RankedHit` contract and its deterministic, duplication-safe accounting
- `dedupe_hits` — keep the best hit per business document id (payload key)
- `TenantScope` — inject a mandatory tenant condition and verify returned
  payloads, so a provider that ignores filters cannot leak another tenant's data
- `chunk_points` — bounded batch partitioning for large writes
- `scroll_all` — accumulate all scroll pages with an explicit safety bound

## Status / roadmap

Implemented:

- [x] `GET /healthz` health check
- [x] `GET /collections` list collections
- [x] `PUT /collections/{name}` create collection (single or named vectors)
- [x] `PATCH /collections/{name}` update collection settings
- [x] `GET /collections/{name}` collection info
- [x] `DELETE /collections/{name}` delete collection
- [x] `GET /collections/{name}/exists` collection existence check
- [x] `PUT /collections/{name}/points` upsert points (dense or named vectors)
- [x] `GET /collections/{name}/points/{id}` get a point
- [x] `POST /collections/{name}/points/delete` delete points by id or filter
- [x] `POST /collections/{name}/points/search` vector search with payload
  filters, score_threshold, offset, named-vector `using` and search params
- [x] `POST /collections/{name}/points/search/batch` batch search
- [x] `POST /collections/{name}/points/search/groups` grouped search
- [x] typed filter DSL (`Condition` / `Filter` builder over must/should/must_not)
- [x] `PUT /collections/{name}/points/batch` batch upsert
- [x] `POST /collections/{name}/points/scroll` paginated point scrolling
- [x] `POST /collections/{name}/points/count` point count (exact or estimated)
- [x] `POST /collections/{name}/points` batch retrieve by ids
- [x] `PUT|POST /collections/{name}/points/payload` set / overwrite payload
- [x] `POST /collections/{name}/points/payload/delete` delete payload
  (whole payload or selected keys)
- [x] `PUT|GET /collections/{name}/index` / `DELETE /collections/{name}/index/{field}` payload indexes
- [x] `POST /collections/{name}/points/query` query API
  (`query_nearest` / `query_recommend` / raw `query_points`)
- [x] `POST /collections/{name}/facet` facet counts
- [x] `POST /collections/aliases` / `GET /aliases` collection aliases
- [x] `GET|POST|DELETE /collections/{name}/snapshots` snapshot management
- [x] `GET|POST /locks` service write lock (Qdrant ≤ 1.15 only; deprecated in
  1.15 and removed in 1.16)
- [x] `GET /` server info (version / commit)
- [x] `GET /cluster` cluster state (status, peers, raft info)
- [x] `GET /collections/{name}/cluster` per-collection shard / replica layout
- [x] `POST /collections/{name}/cluster` shard operations
  (`replicate_shard`, `create_shard_replica`, `delete_shard_replica`)
- [x] unified `VectorProvider` trait (extensible to other vector services)

Planned:

- [ ] cluster telemetry (`GET /cluster/telemetry`)

## Development

```bash
moon check --deny-warn
moon test
moon fmt
```

### Integration testing against a real Qdrant

Unit tests cover the pure logic (models, JSON conversion, request bodies).
The end-to-end path is verified in CI against a real Qdrant server
(`.github/workflows/integration.yml` starts a `qdrant/qdrant` container and
runs `examples/integration_check`, which asserts every client method against
the live API, then runs the demo end to end and the multi-tenant RAG case).

Locally, start Qdrant and run the same checks:

```bash
docker run -p 6333:6333 qdrant/qdrant
moon run examples/integration_check -- http://localhost:6333
moon run examples/demo -- http://localhost:6333
moon run examples/rag_case -- http://localhost:6333
```

## Reproducibility

For reviewers: a short [reproducibility guide](REPRODUCIBILITY.md) covers
environment setup, the end-to-end demo, re-running the integration check,
expected outputs, and troubleshooting.

## License

Apache-2.0
