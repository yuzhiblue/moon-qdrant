///|
/// End-to-end demo: create a collection, write points, search, read and
/// delete. Run against a local Qdrant server:
///
///   docker run -p 6333:6333 qdrant/qdrant
///   moon run examples/demo -- http://localhost:6333
async fn main {
  let argv = @env.args()
  let base = if argv.length() > 1 { argv[1] } else { "http://localhost:6333" }
  let client = @moon_qdrant.QdrantClient::new(base)
  let collection = "moon-qdrant-demo"

  let healthy = client.health() catch { _ => false }
  println("health: " + healthy.to_string())

  // reset any previous demo state
  if client.collection_exists(collection) {
    client.delete_collection(collection)
    println("removed leftover collection: " + collection)
  }

  client.create_collection(
    collection,
    @moon_qdrant.CollectionConfig::new(
      @moon_qdrant.VectorParams::new(4, @moon_qdrant.Distance::Cosine),
    ),
  )
  println("created collection: " + collection)

  client.upsert_points(collection, [
    @moon_qdrant.PointStruct::new(1, [0.1, 0.2, 0.3, 0.4], { "tag": "alpha" }),
    @moon_qdrant.PointStruct::new(2, [0.5, 0.6, 0.7, 0.8], { "tag": "beta" }),
    @moon_qdrant.PointStruct::new(3, [0.9, 0.8, 0.7, 0.6], { "tag": "alpha" }),
  ])
  println("upserted 3 points")

  let hits = client.search_points(collection, [0.1, 0.2, 0.3, 0.4], 2)
  println("top hits: " + hits.length().to_string())
  for hit in hits {
    println("  id=" + hit.id.to_string() + " score=" + hit.score.to_string())
  }

  let alpha_filter : Json = {
    "must": [{ "key": "tag", "match": { "value": "alpha" } }],
  }
  let filtered = client.search_points(
    collection,
    [0.1, 0.2, 0.3, 0.4],
    5,
    filter=Some(alpha_filter),
  )
  println("filtered hits (tag=alpha): " + filtered.length().to_string())

  let point = client.get_point(collection, 1)
  match point {
    Some(p) =>
      println(
        "got point id=" +
        p.id.to_string() +
        " with " +
        p.vector.length().to_string() +
        " dims",
      )
    None => println("point 1 not found")
  }

  client.delete_points(collection, [2])
  let names = client.list_collections()
  println("collections after cleanup: " + names.length().to_string())

  client.delete_collection(collection)
  println("deleted collection: " + collection)
  println("demo finished")
}
