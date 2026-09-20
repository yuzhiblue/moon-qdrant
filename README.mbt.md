# yuzhiblue/moon-qdrant

A MoonBit client for the [Qdrant](https://qdrant.tech/) vector database REST API.

moon-qdrant lets MoonBit programs manage Qdrant collections, upsert points,
and run vector searches without leaving the MoonBit ecosystem. It is built on
`oboard/mio` for HTTP transport and the MoonBit core JSON library.

## Why

Qdrant is one of the most widely used vector databases for RAG and embedding
search. The MoonBit ecosystem already has vector engines and servers
(e.g. `trkbt10/vcdb`), but no client library to talk to a running Qdrant
service. moon-qdrant fills that gap with a small, explicit API surface that
maps 1:1 to Qdrant REST endpoints.

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
- [x] `PUT|GET|DELETE /collections/{name}/indexes/{field}` payload indexes
- [x] `POST /collections/{name}/points/query` query API
  (`query_nearest` / `query_recommend` / raw `query_points`)
- [x] `POST /collections/{name}/points/facet` facet counts
- [x] `POST /collections/aliases` / `GET /collections/aliases` collection aliases
- [x] `GET|POST|DELETE /collections/{name}/snapshots` snapshot management
- [x] unified `VectorProvider` trait (extensible to other vector services)

Planned:

- [ ] collection locks and cluster endpoints

## Development

```bash
moon check --deny-warn
moon test
moon fmt
```

## License

Apache-2.0
