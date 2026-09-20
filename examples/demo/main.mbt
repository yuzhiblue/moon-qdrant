///|
/// End-to-end demo: create a collection, write points, search with a typed
/// filter, count, scroll, retrieve, use aliases and finally delete.
/// Run against a local Qdrant server:
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

  // typed filter DSL instead of hand-written JSON
  let alpha_filter = @moon_qdrant.Filter::new().must(
    @moon_qdrant.Condition::match_keyword("tag", "alpha"),
  )
  let filtered = client.search_points_with_filter(
    collection,
    [0.1, 0.2, 0.3, 0.4],
    5,
    alpha_filter,
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

  // count: fast estimate by default
  let total = client.count_points(collection)
  println("point count: " + total.to_string())

  // scroll one page of points
  let page = client.scroll_points(collection, 10)
  println("scrolled points: " + page.points.length().to_string())

  // batch retrieve by ids
  let fetched = client.retrieve_points(collection, [1, 3])
  println("retrieved points: " + fetched.length().to_string())

  // aliases
  client.create_alias("moon-demo-alias", collection)
  let aliases = client.list_aliases()
  println("aliases: " + aliases.length().to_string())
  client.delete_alias("moon-demo-alias")

  // advanced search: score threshold keeps only hits above the score
  let top = client.search_points(
    collection,
    [0.1, 0.2, 0.3, 0.4],
    5,
    score_threshold=Some(0.9),
  )
  println("hits above 0.9: " + top.length().to_string())

  // payload management: set an extra field, then delete one key
  client.set_payload(collection, { "active": true }, ids=Some([1]))
  client.delete_payload_by_keys(collection, ["active"], ids=Some([1]))
  println("payload set and key deleted on point 1")

  // batch search: two queries in one round trip
  let batch = client.search_points_batch(collection, [
    { "vector": [0.1, 0.2, 0.3, 0.4], "limit": 2 },
    { "vector": [0.9, 0.8, 0.7, 0.6], "limit": 2 },
  ])
  println("batch search groups: " + batch.length().to_string())

  // query API: nearest neighbor and recommendation
  let nearest = client.query_nearest(collection, [0.1, 0.2, 0.3, 0.4], 2)
  println("query nearest hits: " + nearest.length().to_string())
  let positive : Array[Json] = [Json::array([0.1, 0.2, 0.3, 0.4])]
  let recommended = client.query_recommend(collection, positive, 2)
  println("query recommend hits: " + recommended.length().to_string())

  // facet: distinct payload values with counts
  let facet = client.facet_points(collection, "tag", 10)
  println("facet values: " + facet.hits.length().to_string())
  for hit in facet.hits {
    println("  tag -> count " + hit.count.to_string())
  }

  // grouped search: top hits per payload value
  let groups = client.search_points_groups(
    collection,
    [0.1, 0.2, 0.3, 0.4],
    2,
    "tag",
    10,
  )
  println("search groups: " + groups.length().to_string())
  for group in groups {
    println(
      "  group id=" +
      group.id.stringify() +
      " hits=" +
      group.hits.length().to_string(),
    )
  }

  // payload indexes speed up filtered access
  client.create_payload_index(collection, "tag", "keyword")
  let indexes = client.list_payload_indexes(collection)
  println("payload indexes: " + indexes.length().to_string())
  client.delete_payload_index(collection, "tag")

  // snapshots for backup / restore
  let snap = client.create_snapshot(collection)
  println("created snapshot: " + snap.name)
  let snaps = client.list_snapshots(collection)
  println("snapshots listed: " + snaps.length().to_string())
  client.delete_snapshot(collection, snap.name)

  // bulk delete points matching a filter
  client.delete_points_by_filter(
    collection,
    @moon_qdrant.Filter::new().must(
      @moon_qdrant.Condition::match_keyword("tag", "beta"),
    ),
  )
  let remaining = client.count_points(collection)
  println("points after filter delete: " + remaining.to_string())

  let names = client.list_collections()
  println("collections: " + names.length().to_string())

  client.delete_collection(collection)
  println("deleted collection: " + collection)

  // ---- named vectors ----
  let named_collection = "moon-qdrant-demo-named"
  if client.collection_exists(named_collection) {
    client.delete_collection(named_collection)
  }
  let named_vectors : Map[String, @moon_qdrant.VectorParams] = Map([])
  named_vectors["text"] = @moon_qdrant.VectorParams::new(
    4,
    @moon_qdrant.Distance::Cosine,
  )
  named_vectors["image"] = @moon_qdrant.VectorParams::new(
    8,
    @moon_qdrant.Distance::Dot,
  )
  client.create_collection(
    named_collection,
    @moon_qdrant.CollectionConfig::new_named(named_vectors),
  )
  println("created named-vector collection: " + named_collection)

  let nv_points : Map[String, Array[Double]] = Map([])
  nv_points["text"] = [0.1, 0.2, 0.3, 0.4]
  nv_points["image"] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]
  client.upsert_points(named_collection, [
    @moon_qdrant.PointStruct::new_named(1, nv_points, { "tag": "alpha" }),
  ])
  let text_hits = client.search_points(
    named_collection,
    [0.1, 0.2, 0.3, 0.4],
    1,
    using_vector=Some("text"),
  )
  println("named-vector search (text): " + text_hits.length().to_string())
  let image_hits = client.search_points_named(
    named_collection,
    @moon_qdrant.NamedVector::new("image", [
      1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0,
    ]),
    1,
  )
  println("named-vector search (image): " + image_hits.length().to_string())

  client.delete_collection(named_collection)
  println("deleted named-vector collection: " + named_collection)

  // cluster: single-node deployments still answer these endpoints
  let cluster = client.cluster_info()
  println(
    "cluster status=" +
    cluster.status +
    " peers=" +
    cluster.peers.length().to_string(),
  )
  let lock = client.collection_lock(collection)
  println("collection lock write=" + lock.write.to_string())
  let info = client.service_info()
  match info.version {
    Some(v) => println("qdrant version: " + v)
    None => println("qdrant version: unknown")
  }

  println("demo finished")
}
