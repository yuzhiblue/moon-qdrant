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
  inspect(Distance::Cosine.to_wire(), content="Cosine")
  inspect(Distance::Euclid.to_wire(), content="Euclid")
  inspect(Distance::Dot.to_wire(), content="Dot")
  match Distance::from_wire("Cosine") {
    Some(Cosine) => ()
    _ => fail("expected Cosine")
  }
  match Distance::from_wire("Euclid") {
    Some(Euclid) => ()
    _ => fail("expected Euclid")
  }
  match Distance::from_wire("unknown") {
    None => ()
    _ => fail("expected None for unknown distance")
  }
}

///|
test "vector params serialize to the qdrant wire shape" {
  let json = VectorParams::new(4, Distance::Cosine).to_json()
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
  let json = CollectionConfig::new(VectorParams::new(128, Distance::Dot)).to_json()
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
  let json = PointStruct::new(42, [1.0, 2.0, 3.0], { "tag": "demo" }).to_json()
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
  match CollectionList::from_json(json) {
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
  match VectorParams::from_json(json) {
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
  match CollectionInfo::from_json(json) {
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
  match CollectionInfo::from_json(json) {
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
  match PointStruct::from_json(json) {
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
  let point = PointStruct::new(3, [1.0, 2.0], { "tag": "x" })
  match PointStruct::from_json(point.to_json()) {
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
  match ScoredPoint::from_json(json) {
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
  match parse_search_result(json) {
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
  let filter = Filter::new()
    .must(Condition::match_keyword("tag", "alpha"))
    .must(Condition::match_value("active", Json::boolean(true)))
    .must_not(Condition::is_null("deprecated"))
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
  let c = Condition::range("age", gte=Some(18.0), lt=Some(65.0))
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
  let c = Condition::match_values("tag", values)
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
  let json = Filter::new().to_json()
  match json {
    Object(members) => assert_true(members.is_empty())
    _ => fail("expected an object")
  }
}
