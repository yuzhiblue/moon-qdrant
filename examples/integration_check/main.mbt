///|
/// End-to-end integration check against a real Qdrant server.
///
/// Every client method used here performs a real HTTP round trip and the
/// response is parsed and asserted. Any failed assertion raises and the
/// program exits non-zero, so running this is a full acceptance test.
///
/// Usage:
///   moon run examples/integration_check -- http://localhost:6333
///
/// The GitHub Actions workflow `integration.yml` starts a Qdrant container
/// and runs this check automatically.

///|
/// Assert a condition and report PASS / FAIL; a failure raises so the
/// program exits with a non-zero code.
fn check(name : String, cond : Bool) -> Unit {
  if cond {
    println("[PASS] " + name)
  } else {
    println("[FAIL] " + name)
    abort("integration check failed: " + name)
  }
}

///|
async fn main {
  let argv = @env.args()
  let base = if argv.length() > 1 { argv[1] } else { "http://localhost:6333" }
  let client = @moon_qdrant.QdrantClient::new(base)

  // health
  check("health returns ok", client.health())

  let collection = "moon-qdrant-integration-check"

  // reset any previous run
  if client.collection_exists(collection) {
    client.delete_collection(collection)
  }

  // create collection
  client.create_collection(
    collection,
    @moon_qdrant.CollectionConfig::new(
      @moon_qdrant.VectorParams::new(4, @moon_qdrant.Distance::Cosine),
    ),
  )
  check("collection exists after create", client.collection_exists(collection))
  let info = client.collection_info(collection)
  check(
    "collection info status",
    info.status == "green" || info.status == "yellow",
  )
  check("collection info vector size", info.vectors is Some(_))

  // upsert points (wait = true by default)
  client.upsert_points(collection, [
    @moon_qdrant.PointStruct::new(1, [0.1, 0.2, 0.3, 0.4], { "tag": "alpha" }),
    @moon_qdrant.PointStruct::new(2, [0.5, 0.6, 0.7, 0.8], { "tag": "beta" }),
    @moon_qdrant.PointStruct::new(3, [0.9, 0.8, 0.7, 0.6], { "tag": "alpha" }),
  ])

  // point read + payload
  let p1 = client.get_point(collection, 1)
  check("get_point returns the point", p1 is Some(_))
  match p1 {
    Some(p) =>
      match p.payload {
        Object(members) =>
          match members.get("tag") {
            Some(String(s)) => check("point payload tag", s == "alpha")
            _ => raise Failure("point payload missing tag")
          }
        _ => raise Failure("point payload missing")
      }
    None => ()
  }

  // retrieve / scroll / count
  let retrieved = client.retrieve_points(collection, [1, 2])
  check("retrieve_points returns 2 points", retrieved.length() == 2)
  let scroll = client.scroll_points(collection, 10)
  check("scroll_points returns points", scroll.points.length() >= 3)
  let count = client.count_points(collection)
  check("count_points returns 3", count == 3)

  // search: plain, filtered, with score threshold
  let hits = client.search_points(collection, [0.1, 0.2, 0.3, 0.4], 3)
  check("search returns hits", hits.length() > 0)
  let alpha_filter = @moon_qdrant.Filter::new().must(
    @moon_qdrant.Condition::match_keyword("tag", "alpha"),
  )
  let filtered = client.search_points_with_filter(
    collection,
    [0.1, 0.2, 0.3, 0.4],
    10,
    alpha_filter,
  )
  check("filtered search returns only alpha", filtered.length() == 2)
  for hit in filtered {
    match hit.payload {
      Some(Object(members)) =>
        match members.get("tag") {
          Some(String(s)) => check("hit is alpha", s == "alpha")
          _ => ()
        }
      _ => ()
    }
  }
  let top = client.search_points(
    collection,
    [0.1, 0.2, 0.3, 0.4],
    3,
    score_threshold=Some(0.99),
  )
  check("score_threshold keeps the best hit", top.length() == 1)

  // batch search
  let batch = client.search_points_batch(collection, [
    { "vector": [0.1, 0.2, 0.3, 0.4], "limit": 2 },
    { "vector": [0.9, 0.8, 0.7, 0.6], "limit": 2 },
  ])
  check("batch search returns 2 result sets", batch.length() == 2)

  // query API
  let nearest = client.query_nearest(collection, [0.1, 0.2, 0.3, 0.4], 2)
  check("query_nearest returns hits", nearest.length() > 0)
  let recs = client.query_recommend(
    collection,
    [Json::array([0.1, 0.2, 0.3, 0.4])],
    2,
  )
  check("query_recommend returns hits", recs.length() > 0)

  // facet (requires a keyword payload index on the facet key)
  client.create_payload_index(collection, "tag", "keyword")
  let facet = client.facet_points(collection, "tag", 10)
  check("facet returns 2 distinct tags", facet.hits.length() == 2)

  // grouped search (group_by also needs a keyword index on the key)
  let groups = client.search_points_groups(
    collection,
    [0.1, 0.2, 0.3, 0.4],
    2,
    "tag",
    10,
  )
  check("grouped search returns 2 groups", groups.length() == 2)

  // grouped search on a named-vector collection: the vector name must be
  // embedded in the vector object (no top-level "using" in search APIs)
  let named_collection = "moon-qdrant-integration-check-named"
  let named_vecs : Map[String, @moon_qdrant.VectorParams] = Map([])
  named_vecs["text"] = @moon_qdrant.VectorParams::new(
    4,
    @moon_qdrant.Distance::Cosine,
  )
  named_vecs["image"] = @moon_qdrant.VectorParams::new(
    8,
    @moon_qdrant.Distance::Dot,
  )
  client.create_collection(
    named_collection,
    @moon_qdrant.CollectionConfig::new_named(named_vecs),
  )
  let nv_points : Map[String, Array[Double]] = Map([])
  nv_points["text"] = [0.1, 0.2, 0.3, 0.4]
  nv_points["image"] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]
  client.upsert_points(named_collection, [
    @moon_qdrant.PointStruct::new_named(1, nv_points, { "tag": "alpha" }),
  ])
  client.create_payload_index(named_collection, "tag", "keyword")
  let nv_groups = client.search_points_groups(
    named_collection,
    [0.1, 0.2, 0.3, 0.4],
    1,
    "tag",
    5,
    using_vector=Some("text"),
  )
  check(
    "grouped search with named vector returns groups",
    nv_groups.length() >= 1,
  )
  client.delete_collection(named_collection)
  check("named collection deleted", !client.collection_exists(named_collection))

  // payload operations
  client.set_payload(
    collection,
    { "active": Json::boolean(true) },
    ids=Some([1]),
  )
  match client.get_point(collection, 1) {
    Some(p) =>
      match p.payload {
        Object(members) =>
          match members.get("active") {
            Some(True) => check("set_payload merged", true)
            _ => raise Failure("set_payload did not merge")
          }
        _ => raise Failure("payload missing after set_payload")
      }
    None => raise Failure("point 1 missing")
  }
  client.delete_payload_by_keys(collection, ["active"], ids=Some([1]))
  match client.get_point(collection, 1) {
    Some(p) =>
      match p.payload {
        Object(members) =>
          check(
            "delete_payload_by_keys removed key",
            members.get("active") is None,
          )
        _ => raise Failure("payload missing after delete")
      }
    None => raise Failure("point 1 missing")
  }

  // payload index (created earlier for facet/group; verify and clean up)
  let indexes = client.list_payload_indexes(collection)
  check("payload index listed", indexes.length() >= 1)
  client.delete_payload_index(collection, "tag")

  // snapshots
  let snapshots = client.list_snapshots(collection)
  let before = snapshots.length()
  let _ = client.create_snapshot(collection)
  let after = client.list_snapshots(collection).length()
  check("snapshot created", after > before)

  // aliases
  client.create_alias("integration-alias", collection)
  let aliases = client.list_aliases()
  check("alias listed", aliases.length() >= 1)
  client.delete_alias("integration-alias")

  // service write lock (Qdrant locks are service-wide)
  client.set_locks(true, error_message=Some("maintenance"))
  let lock = client.get_locks()
  check("collection locked", lock.write)
  client.set_locks(false)
  let unlocked = client.get_locks()
  check("collection unlocked", !unlocked.write)

  // service + cluster (single node answers these too)
  let service = client.service_info()
  check("service_info reports a version", service.version is Some(_))
  let cluster = client.cluster_info()
  check(
    "cluster_info reports status",
    cluster.status == "disabled" || cluster.peers.length() >= 1,
  )
  let layout = client.collection_cluster_info(collection)
  check(
    "collection cluster has local shards",
    layout.local_shards.length() >= 1,
  )

  // cleanup
  client.delete_collection(collection)
  check("collection deleted", !client.collection_exists(collection))

  println("ALL INTEGRATION CHECKS PASSED")
}
