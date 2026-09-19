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
- [x] `PUT /collections/{name}` create collection
- [x] `GET /collections/{name}` collection info
- [x] `DELETE /collections/{name}` delete collection
- [x] `GET /collections/{name}/exists` collection existence check
- [x] `PUT /collections/{name}/points` upsert points
- [x] `GET /collections/{name}/points/{id}` get a point
- [x] `POST /collections/{name}/points/delete` delete points by id
- [x] `POST /collections/{name}/points/search` vector search with payload filters
- [x] typed filter DSL (`Condition` / `Filter` builder over must/should/must_not)
- [x] `PUT /collections/{name}/points/batch` batch upsert
- [x] `POST /collections/{name}/points/scroll` paginated point scrolling
- [x] `POST /collections/{name}/points/count` point count (exact or estimated)
- [x] `POST /collections/{name}/points` batch retrieve by ids
- [x] `POST /collections/{name}/points/delete` delete points by filter
- [x] `POST /collections/aliases` / `GET /collections/aliases` collection aliases
- [x] unified `VectorProvider` trait (extensible to other vector services)

## Development

```bash
moon check --deny-warn
moon test
moon fmt
```

## License

Apache-2.0
