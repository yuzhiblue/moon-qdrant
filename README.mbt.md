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

// delete it
client.delete_collection("demo")
```

## CLI demo

```bash
moon run cmd/main -- http://localhost:6333
```

## Status / roadmap

Implemented:

- [x] `GET /healthz` health check
- [x] `GET /collections` list collections
- [x] `PUT /collections/{name}` create collection
- [x] `GET /collections/{name}` collection info
- [x] `DELETE /collections/{name}` delete collection
- [x] `GET /collections/{name}/exists` collection existence check
- [ ] point upsert / delete / get
- [ ] vector search with payload filters
- [ ] batch operations
- [ ] unified `VectorProvider` trait (extensible to other vector services)

## Development

```bash
moon check --deny-warn
moon test
moon fmt
```

## License

Apache-2.0
