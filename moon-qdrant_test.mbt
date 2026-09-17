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
