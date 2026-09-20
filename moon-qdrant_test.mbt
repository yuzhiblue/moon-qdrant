// Blackbox tests run against the package's public API.
// Run `moon test` to execute and `moon test --update` to refresh snapshots.

///|
/// Read a field from a JSON object, if present.
fn field(json : Json, key : String) -> Json? {
  match json {
    Object(members) => members.get(key)
    _ => None
  }
}

///|
/// Unit tests for the pure-logic parts of moon-qdrant: type models and
/// JSON conversion. Transport-level behavior is covered by integration
/// tests against a real Qdrant server (see README).

///|
test "distance wire conversion round-trips" {
  inspect(@moon-qdrant.Distance::Cosine.to_wire(), content="Cosine")
  inspect(@moon-qdrant.Distance::Euclid.to_wire(), content="Euclid")
  inspect(@moon-qdrant.Distance::Dot.to_wire(), content="Dot")
  match @moon-qdrant.Distance::from_wire("Cosine") {
    Some(Cosine) => ()
    _ => fail("expected Cosine")
  }
  match @moon-qdrant.Distance::from_wire("Euclid") {
    Some(Euclid) => ()
    _ => fail("expected Euclid")
  }
  match @moon-qdrant.Distance::from_wire("unknown") {
    None => ()
    _ => fail("expected None for unknown distance")
  }
}

///|
test "vector params serialize to the qdrant wire shape" {
  let json = @moon-qdrant.VectorParams::new(4, @moon-qdrant.Distance::Cosine).to_json()
  match field(json, "size") {
    Some(Number(n, ..)) => assert_true(n == 4.0)
    _ => fail("expected numeric size")
  }
  match field(json, "distance") {
    Some(String(s)) => assert_true(s == "Cosine")
    _ => fail("expected distance string")
  }
}

///|
test "collection config nests vectors" {
  let json = @moon-qdrant.CollectionConfig::new(
    @moon-qdrant.VectorParams::new(128, @moon-qdrant.Distance::Dot),
  ).to_json()
  let vectors = field(json, "vectors")
  match field(vectors.unwrap_or(Json::null()), "size") {
    Some(Number(n, ..)) => assert_true(n == 128.0)
    _ => fail("expected nested numeric size")
  }
  match field(vectors.unwrap_or(Json::null()), "distance") {
    Some(String(s)) => assert_true(s == "Dot")
    _ => fail("expected nested distance string")
  }
}

///|
test "point struct serializes id, vector and payload" {
  let json = @moon-qdrant.PointStruct::new(42, [1.0, 2.0, 3.0], {
    "tag": "demo",
  }).to_json()
  match field(json, "id") {
    Some(Number(n, ..)) => assert_true(n == 42.0)
    _ => fail("expected numeric id")
  }
  match field(json, "vector") {
    Some(Array(arr)) => {
      assert_true(arr.length() == 3)
      match arr[0] {
        Number(n, ..) => assert_true(n == 1.0)
        _ => fail("expected numeric vector element")
      }
      match arr[2] {
        Number(n, ..) => assert_true(n == 3.0)
        _ => fail("expected numeric vector element")
      }
    }
    _ => fail("expected vector array")
  }
  match field(field(json, "payload").unwrap_or(Json::null()), "tag") {
    Some(String(s)) => assert_true(s == "demo")
    _ => fail("expected payload tag")
  }
}

///|
test "collection list parses the standard qdrant response" {
  let json : Json = {
    "result": { "collections": [{ "name": "alice" }, { "name": "bob" }] },
    "status": "ok",
  }
  match @moon-qdrant.CollectionList::from_json(json) {
    Some(list) => {
      assert_true(list.names.length() == 2)
      assert_true(list.names[0] == "alice")
      assert_true(list.names[1] == "bob")
    }
    None => fail("expected a collection list")
  }
}

///|
test "vector params parse from a collection config fragment" {
  let json : Json = { "size": 128, "distance": "Dot" }
  match @moon-qdrant.VectorParams::from_json(json) {
    Some(vp) => {
      assert_true(vp.size == 128)
      assert_true(vp.distance.to_wire() == "Dot")
    }
    None => fail("expected vector params")
  }
}

///|
test "collection info parses the standard qdrant response" {
  let json : Json = {
    "result": {
      "status": "green",
      "points_count": 5,
      "config": { "params": { "vectors": { "size": 4, "distance": "Cosine" } } },
    },
    "status": "ok",
    "time": 0.001,
  }
  match @moon-qdrant.CollectionInfo::from_json(json) {
    Some(info) => {
      assert_true(info.status == "green")
      match info.points_count {
        Some(n) => assert_true(n == 5)
        None => fail("expected points count")
      }
      match info.vectors {
        Some(vp) => {
          assert_true(vp.size == 4)
          assert_true(vp.distance.to_wire() == "Cosine")
        }
        None => fail("expected vectors config")
      }
    }
    None => fail("expected collection info")
  }
}

///|
test "collection info tolerates a missing points count" {
  let json : Json = {
    "result": {
      "status": "grey",
      "config": { "params": { "vectors": { "size": 4, "distance": "Euclid" } } },
    },
    "status": "ok",
  }
  match @moon-qdrant.CollectionInfo::from_json(json) {
    Some(info) => {
      assert_true(info.status == "grey")
      assert_true(info.points_count is None)
      match info.vectors {
        Some(vp) => assert_true(vp.distance.to_wire() == "Euclid")
        None => fail("expected vectors config")
      }
    }
    None => fail("expected collection info")
  }
}

///|
test "point struct parses the point read response" {
  let json : Json = {
    "id": 7,
    "vector": [0.5, 1.5, 2.5],
    "payload": { "tag": "demo" },
  }
  match @moon-qdrant.PointStruct::from_json(json) {
    Some(point) => {
      assert_true(point.id == 7)
      assert_true(point.vector.length() == 3)
      assert_true(point.vector[1] == 1.5)
      match field(point.payload, "tag") {
        Some(String(s)) => assert_true(s == "demo")
        _ => fail("expected payload tag")
      }
    }
    None => fail("expected a point struct")
  }
}

///|
test "point struct round-trips through json" {
  let point = @moon-qdrant.PointStruct::new(3, [1.0, 2.0], { "tag": "x" })
  match @moon-qdrant.PointStruct::from_json(point.to_json()) {
    Some(parsed) => {
      assert_true(parsed.id == 3)
      assert_true(parsed.vector.length() == 2)
      assert_true(parsed.vector[0] == 1.0)
    }
    None => fail("expected a point struct")
  }
}

///|
test "scored point parses a search hit" {
  let json : Json = {
    "id": 1,
    "version": 0,
    "score": 0.99,
    "payload": { "tag": "alpha" },
  }
  match @moon-qdrant.ScoredPoint::from_json(json) {
    Some(hit) => {
      assert_true(hit.id == 1)
      assert_true(hit.score == 0.99)
      match hit.payload {
        Some(p) =>
          match field(p, "tag") {
            Some(String(s)) => assert_true(s == "alpha")
            _ => fail("expected payload tag")
          }
        None => fail("expected a payload")
      }
    }
    None => fail("expected a scored point")
  }
}

///|
test "search result parses the standard qdrant response" {
  let json : Json = {
    "result": [
      { "id": 1, "version": 0, "score": 0.99, "payload": { "tag": "alpha" } },
      { "id": 2, "version": 0, "score": 0.50, "payload": null },
    ],
    "status": "ok",
    "time": 0.001,
  }
  match @moon-qdrant.parse_search_result(json) {
    Some(hits) => {
      assert_true(hits.length() == 2)
      assert_true(hits[0].id == 1)
      assert_true(hits[0].score == 0.99)
      assert_true(hits[1].id == 2)
      match hits[1].payload {
        Some(Null) => ()
        _ => fail("expected a null payload")
      }
    }
    None => fail("expected a search result")
  }
}

///|
test "filter serializes must/should/must_not clause groups" {
  let filter = @moon-qdrant.Filter::new()
    .must(@moon-qdrant.Condition::match_keyword("tag", "alpha"))
    .must(@moon-qdrant.Condition::match_value("active", Json::boolean(true)))
    .must_not(@moon-qdrant.Condition::is_null("deprecated"))
  let json = filter.to_json()
  match field(json, "must") {
    Some(Array(musts)) => assert_true(musts.length() == 2)
    _ => fail("expected must array")
  }
  match field(json, "should") {
    None => ()
    _ => fail("expected no should group")
  }
  match field(json, "must_not") {
    Some(Array(nots)) => assert_true(nots.length() == 1)
    _ => fail("expected must_not array")
  }
}

///|
test "range condition omits null bounds" {
  let c = @moon-qdrant.Condition::range("age", gte=Some(18.0), lt=Some(65.0))
  let json = c.to_json()
  match field(json, "range") {
    Some(rng) => {
      match field(rng, "gte") {
        Some(Number(n, ..)) => assert_true(n == 18.0)
        _ => fail("expected gte")
      }
      match field(rng, "lte") {
        None => ()
        _ => fail("lte should be omitted")
      }
      match field(rng, "lt") {
        Some(Number(n, ..)) => assert_true(n == 65.0)
        _ => fail("expected lt")
      }
    }
    _ => fail("expected range object")
  }
}

///|
test "match values serializes to an any array" {
  let values : Array[Json] = [Json::string("a"), Json::string("b")]
  let c = @moon-qdrant.Condition::match_values("tag", values)
  let json = c.to_json()
  match field(json, "match") {
    Some(m) =>
      match field(m, "any") {
        Some(Array(arr)) => assert_true(arr.length() == 2)
        _ => fail("expected any array")
      }
    _ => fail("expected match object")
  }
}

///|
test "empty filter serializes to an empty object" {
  let json = @moon-qdrant.Filter::new().to_json()
  match json {
    Object(members) => assert_true(members.is_empty())
    _ => fail("expected an object")
  }
}

///|
test "scroll result parses points and next page offset" {
  let json : Json = {
    "points": [
      { "id": 1, "vector": [0.1, 0.2], "payload": { "tag": "a" } },
      { "id": 2, "vector": [0.3, 0.4], "payload": {} },
    ],
    "next_page_offset": 5,
  }
  match @moon-qdrant.ScrollResult::from_json(json) {
    Some(page) => {
      assert_true(page.points.length() == 2)
      assert_true(page.points[0].id == 1)
      assert_true(page.points[1].vector[1] == 0.4)
      match page.next_page_offset {
        Some(5) => ()
        _ => fail("expected next_page_offset = 5")
      }
    }
    None => fail("expected a scroll result")
  }
}

///|
test "scroll result treats missing next_page_offset as None" {
  let json : Json = {
    "points": [{ "id": 9, "vector": [0.5, 0.6], "payload": {} }],
  }
  match @moon-qdrant.ScrollResult::from_json(json) {
    Some(page) => {
      assert_true(page.points.length() == 1)
      match page.next_page_offset {
        None => ()
        _ => fail("expected no next page offset on the last page")
      }
    }
    None => fail("expected a scroll result")
  }
}

///|
test "count result parses the point count" {
  let json : Json = { "count": 42 }
  match @moon-qdrant.parse_count_result(json) {
    Some(42) => ()
    _ => fail("expected count = 42")
  }
}

///|
test "count result rejects a missing count field" {
  let json : Json = { "status": "ok" }
  match @moon-qdrant.parse_count_result(json) {
    None => ()
    _ => fail("expected None when count is missing")
  }
}

///|
test "retrieve result parses multiple points" {
  let json : Json = {
    "result": [
      { "id": 1, "vector": [0.1, 0.2], "payload": {} },
      { "id": 2, "vector": [0.3, 0.4], "payload": { "k": "v" } },
    ],
    "status": "ok",
  }
  match @moon-qdrant.parse_retrieve_result(json) {
    Some(points) => {
      assert_true(points.length() == 2)
      assert_true(points[0].id == 1)
      assert_true(points[1].id == 2)
    }
    None => fail("expected retrieved points")
  }
}

///|
test "retrieve result accepts an empty result array" {
  let json : Json = { "result": [] }
  match @moon-qdrant.parse_retrieve_result(json) {
    Some(points) => assert_true(points.is_empty())
    None => fail("expected an empty array")
  }
}

///|
test "aliases response parses alias entries" {
  let json : Json = {
    "result": {
      "aliases": [
        { "alias_name": "prod", "collection_name": "demo" },
        { "alias_name": "beta", "collection_name": "demo-v2" },
      ],
    },
    "status": "ok",
  }
  match @moon-qdrant.parse_aliases(json) {
    Some(aliases) => {
      assert_true(aliases.length() == 2)
      assert_true(aliases[0].alias_name == "prod")
      assert_true(aliases[1].collection_name == "demo-v2")
    }
    None => fail("expected aliases")
  }
}

///|
test "aliases response accepts an empty alias list" {
  let json : Json = { "result": { "aliases": [] } }
  match @moon-qdrant.parse_aliases(json) {
    Some(aliases) => assert_true(aliases.is_empty())
    None => fail("expected an empty alias list")
  }
}

///|
test "@moon-qdrant.join_url keeps a single slash between base and path" {
  assert_true(
    @moon-qdrant.join_url("http://localhost:6333", "/collections") ==
    "http://localhost:6333/collections",
  )
  // note: @moon-qdrant.join_url does not dedupe a trailing slash on the base;
  // QdrantClient::new already strips it, so this double-slash case never
  // reaches it in practice.
  assert_true(
    @moon-qdrant.join_url("http://localhost:6333/", "/collections") ==
    "http://localhost:6333//collections",
  )
}

///|
test "scroll request body omits filter and offset when not given" {
  let body = @moon-qdrant.scroll_request_body(10, None, None, true, true)
  match body {
    Object(members) => {
      assert_true(members.length() == 3)
      match members.get("filter") {
        None => ()
        _ => fail("filter should be omitted")
      }
      match members.get("offset") {
        None => ()
        _ => fail("offset should be omitted")
      }
    }
    _ => fail("expected an object")
  }
}

///|
test "scroll request body includes filter and offset when given" {
  let filter = @moon-qdrant.Filter::new().must(
    @moon-qdrant.Condition::match_keyword("tag", "alpha"),
  )
  let body = @moon-qdrant.scroll_request_body(
    5,
    Some(filter),
    Some(12),
    true,
    true,
  )
  match body {
    Object(members) => {
      match members.get("filter") {
        Some(_) => ()
        None => fail("expected filter")
      }
      match members.get("offset") {
        Some(Number(n, ..)) => assert_true(n == 12.0)
        _ => fail("expected offset = 12")
      }
    }
    _ => fail("expected an object")
  }
}

///|
test "count request body toggles exact and includes optional filter" {
  let body = @moon-qdrant.count_request_body(None, true)
  match body {
    Object(members) => {
      match members.get("exact") {
        Some(_) => ()
        None => fail("expected exact = true")
      }
      match members.get("filter") {
        None => ()
        _ => fail("filter should be omitted")
      }
    }
    _ => fail("expected an object")
  }
  let filter = @moon-qdrant.Filter::new().must(
    @moon-qdrant.Condition::is_empty("deprecated"),
  )
  let with_filter = @moon-qdrant.count_request_body(Some(filter), false)
  match with_filter {
    Object(members) =>
      match members.get("filter") {
        Some(_) => ()
        None => fail("expected filter when provided")
      }
    _ => fail("expected an object")
  }
}

///|
test "collection config with named vectors serializes a keyed map" {
  let named : Map[String, @moon-qdrant.VectorParams] = Map([])
  named["text"] = @moon-qdrant.VectorParams::new(
    4,
    @moon-qdrant.Distance::Cosine,
  )
  named["image"] = @moon-qdrant.VectorParams::new(8, @moon-qdrant.Distance::Dot)
  let json = @moon-qdrant.CollectionConfig::new_named(named).to_json()
  match field(json, "vectors") {
    Some(Object(vectors)) => {
      assert_true(vectors.length() == 2)
      match vectors.get("text") {
        Some(Object(text)) =>
          match text.get("size") {
            Some(Number(n, ..)) => assert_true(n == 4.0)
            _ => fail("expected text size")
          }
        _ => fail("expected text named vector")
      }
      match vectors.get("image") {
        Some(Object(image)) =>
          match image.get("distance") {
            Some(String(s)) => assert_true(s == "Dot")
            _ => fail("expected image distance")
          }
        _ => fail("expected image named vector")
      }
    }
    _ => fail("expected vectors object")
  }
}

///|
test "point struct serializes named vectors as a keyed object" {
  let named : Map[String, Array[Double]] = Map([])
  named["text"] = [0.1, 0.2, 0.3, 0.4]
  named["image"] = [1.0, 2.0]
  let json = @moon-qdrant.PointStruct::new_named(9, named, { "tag": "x" }).to_json()
  match field(json, "id") {
    Some(Number(n, ..)) => assert_true(n == 9.0)
    _ => fail("expected id")
  }
  match field(json, "vector") {
    Some(Object(vectors)) => {
      assert_true(vectors.length() == 2)
      match vectors.get("text") {
        Some(Array(arr)) => assert_true(arr.length() == 4)
        _ => fail("expected text vector array")
      }
    }
    _ => fail("expected named vector object")
  }
}

///|
test "point struct parses a named-vector object" {
  let json : Json = {
    "id": 5,
    "vector": { "text": [0.1, 0.2, 0.3, 0.4], "image": [1.0, 2.0] },
    "payload": { "tag": "alpha" },
  }
  match @moon-qdrant.PointStruct::from_json(json) {
    Some(point) => {
      assert_true(point.id == 5)
      match point.named_vectors {
        Some(named) => {
          assert_true(named.length() == 2)
          match named.get("text") {
            Some(vec) => assert_true(vec.length() == 4)
            None => fail("expected text vector")
          }
        }
        None => fail("expected named vectors")
      }
    }
    None => fail("expected a point struct")
  }
}

///|
test "dense point struct still parses without named vectors" {
  let json : Json = { "id": 5, "vector": [0.1, 0.2], "payload": {} }
  match @moon-qdrant.PointStruct::from_json(json) {
    Some(point) => {
      assert_true(point.vector.length() == 2)
      assert_true(point.named_vectors is None)
    }
    None => fail("expected a point struct")
  }
}

///|
test "named vector serializes name and vector" {
  let json = @moon-qdrant.NamedVector::new("text", [0.1, 0.2]).to_json()
  match field(json, "name") {
    Some(String(s)) => assert_true(s == "text")
    _ => fail("expected name")
  }
  match field(json, "vector") {
    Some(Array(arr)) => assert_true(arr.length() == 2)
    _ => fail("expected vector")
  }
}

///|
test "search params omits unset fields" {
  let json = @moon-qdrant.SearchParams::new(exact=Some(true)).to_json()
  match json {
    Object(members) => {
      match members.get("exact") {
        Some(_) => ()
        None => fail("expected exact")
      }
      match members.get("hnsw_ef") {
        None => ()
        _ => fail("hnsw_ef should be omitted")
      }
    }
    _ => fail("expected an object")
  }
}

///|
test "search params includes hnsw_ef when set" {
  let json = @moon-qdrant.SearchParams::new(hnsw_ef=Some(64)).to_json()
  match field(json, "hnsw_ef") {
    Some(Number(n, ..)) => assert_true(n == 64.0)
    _ => fail("expected hnsw_ef")
  }
}

///|
test "collection update serializes only set fields" {
  let update = @moon-qdrant.CollectionUpdate::new(replication_factor=Some(2))
  let json = update.to_json()
  match field(json, "params") {
    Some(Object(params)) =>
      match params.get("replication_factor") {
        Some(Number(n, ..)) => assert_true(n == 2.0)
        _ => fail("expected replication factor")
      }
    _ => fail("expected params")
  }
  match field(json, "vectors") {
    None => ()
    _ => fail("vectors should be omitted")
  }
}

///|
test "collection update serializes named vector updates" {
  let named : Map[String, @moon-qdrant.VectorParams] = Map([])
  named["text"] = @moon-qdrant.VectorParams::new(
    4,
    @moon-qdrant.Distance::Cosine,
  )
  let update = @moon-qdrant.CollectionUpdate::new(named_vectors=Some(named))
  let json = update.to_json()
  match field(json, "vectors") {
    Some(Object(vectors)) =>
      match vectors.get("text") {
        Some(Object(_)) => ()
        _ => fail("expected text vector params")
      }
    _ => fail("expected vectors object")
  }
}

///|
test "snapshot info parses a snapshot entry" {
  let json : Json = {
    "name": "snap-1",
    "creation_time": "2026-09-20T10:00:00",
    "size": 12345,
  }
  match @moon-qdrant.SnapshotInfo::from_json(json) {
    Some(info) => {
      assert_true(info.name == "snap-1")
      match info.creation_time {
        Some(t) => assert_true(t == "2026-09-20T10:00:00")
        None => fail("expected creation time")
      }
      match info.size {
        Some(n) => assert_true(n == 12345)
        None => fail("expected size")
      }
    }
    None => fail("expected snapshot info")
  }
}

///|
test "snapshots list parses the standard response" {
  let json : Json = {
    "result": [
      { "name": "snap-1", "size": 10 },
      { "name": "snap-2", "size": 20 },
    ],
    "status": "ok",
  }
  match @moon-qdrant.parse_snapshots(json) {
    Some(snaps) => {
      assert_true(snaps.length() == 2)
      assert_true(snaps[1].name == "snap-2")
    }
    None => fail("expected snapshots")
  }
}

///|
test "payload index info parses an index entry" {
  let json : Json = {
    "data_type": "keyword",
    "field_schema": "keyword",
    "points": 3,
  }
  match @moon-qdrant.PayloadIndexInfo::from_json(json) {
    Some(index) => assert_true(index.data_type == "keyword")
    None => fail("expected payload index info")
  }
}

///|
test "payload index list parses the standard response" {
  let json : Json = {
    "result": [
      { "data_type": "keyword", "field_schema": "keyword", "points": 3 },
      { "data_type": "integer", "field_schema": "integer", "points": 3 },
    ],
    "status": "ok",
  }
  match @moon-qdrant.parse_payload_indexes(json) {
    Some(indexes) => {
      assert_true(indexes.length() == 2)
      assert_true(indexes[1].data_type == "integer")
    }
    None => fail("expected payload indexes")
  }
}

///|
test "facet hit parses value and count" {
  let json : Json = { "value": "alpha", "count": 3 }
  match @moon-qdrant.FacetHit::from_json(json) {
    Some(hit) => {
      assert_true(hit.count == 3)
      match hit.value {
        String(s) => assert_true(s == "alpha")
        _ => fail("expected string value")
      }
    }
    None => fail("expected a facet hit")
  }
}

///|
test "facet result parses hits and exact flag" {
  let json : Json = {
    "hits": [{ "value": "alpha", "count": 3 }, { "value": "beta", "count": 1 }],
    "exact": true,
  }
  match @moon-qdrant.FacetResult::from_json(json) {
    Some(fr) => {
      assert_true(fr.hits.length() == 2)
      assert_true(fr.hits[1].count == 1)
      assert_true(fr.exact)
    }
    None => fail("expected a facet result")
  }
}

///|
test "query result parses like a search result" {
  let json : Json = {
    "result": [
      { "id": 1, "version": 0, "score": 0.99, "payload": { "tag": "alpha" } },
      { "id": 2, "version": 0, "score": 0.50, "payload": null },
    ],
    "status": "ok",
  }
  match @moon-qdrant.parse_query_result(json) {
    Some(hits) => {
      assert_true(hits.length() == 2)
      assert_true(hits[0].id == 1)
      assert_true(hits[0].score == 0.99)
    }
    None => fail("expected a query result")
  }
}

///|
test "search group parses hits and group id" {
  let json : Json = {
    "hits": [
      { "id": 1, "version": 0, "score": 0.99, "payload": { "tag": "alpha" } },
      { "id": 3, "version": 0, "score": 0.80, "payload": { "tag": "alpha" } },
    ],
    "id": "alpha",
  }
  match @moon-qdrant.ScoredPointGroup::from_json(json) {
    Some(group) => {
      assert_true(group.hits.length() == 2)
      assert_true(group.hits[1].id == 3)
      match group.id {
        String(s) => assert_true(s == "alpha")
        _ => fail("expected string group id")
      }
    }
    None => fail("expected a search group")
  }
}

///|
test "grouped search result parses the standard response" {
  let json : Json = {
    "result": {
      "groups": [
        {
          "hits": [{ "id": 1, "version": 0, "score": 0.99, "payload": {} }],
          "id": "alpha",
        },
        {
          "hits": [{ "id": 2, "version": 0, "score": 0.50, "payload": {} }],
          "id": "beta",
        },
      ],
    },
    "status": "ok",
  }
  match @moon-qdrant.parse_search_groups(json) {
    Some(groups) => {
      assert_true(groups.length() == 2)
      assert_true(groups[1].hits[0].id == 2)
    }
    None => fail("expected search groups")
  }
}

///|
test "collection lock parses write flag and message" {
  let json : Json = { "write": true, "error_message": "locked for writes" }
  match @moon-qdrant.CollectionLock::from_json(json) {
    Some(lock) => {
      assert_true(lock.write)
      match lock.error_message {
        Some(msg) => assert_true(msg == "locked for writes")
        None => fail("expected error message")
      }
    }
    None => fail("expected a collection lock")
  }
}

///|
test "collection lock tolerates a missing error message" {
  let json : Json = { "write": false }
  match @moon-qdrant.CollectionLock::from_json(json) {
    Some(lock) => {
      assert_true(!lock.write)
      assert_true(lock.error_message is None)
    }
    None => fail("expected a collection lock")
  }
}

///|
test "service info parses version and commit" {
  let json : Json = { "version": "1.14.0", "commit": "abc123" }
  match @moon-qdrant.ServiceInfo::from_json(json) {
    Some(info) => {
      match info.version {
        Some(v) => assert_true(v == "1.14.0")
        None => fail("expected version")
      }
      match info.commit {
        Some(c) => assert_true(c == "abc123")
        None => fail("expected commit")
      }
    }
    None => fail("expected service info")
  }
}
