// Tests for the client-side retrieval semantics layer. None of these need a
// Qdrant server: fusion, deduplication, tenant checks and chunking are pure
// client logic, which is exactly why they live in this package.

///|
fn hit(
  id : Int64,
  score : Double,
  source : String,
  payload : Json?,
) -> @moon-qdrant.RankedHit {
  { id, score, rrf_score: 0.0, sources: [source], payload, }
}

///|
fn doc_payload(doc_id : String, tenant_id : String) -> Json {
  Json::object({
    "doc_id": Json::string(doc_id),
    "tenant_id": Json::string(tenant_id),
  })
}

///|
test "rrf_fuse sums reciprocal ranks across channels" {
  let semantic = [
    hit(1L, 0.9, "semantic", None),
    hit(2L, 0.8, "semantic", None),
  ]
  let keyword = [hit(3L, 7.0, "keyword", None), hit(1L, 6.0, "keyword", None)]
  let fused = @moon-qdrant.rrf_fuse([semantic, keyword], k=0, limit=2)
  assert_true(fused.length() == 2)
  // id 1: rank 1 in semantic, rank 2 in keyword => 1 + 1/2 = 1.5
  assert_true(fused[0].id == 1L)
  assert_true(fused[0].rrf_score > 1.49 && fused[0].rrf_score < 1.51)
  // A raw score of 7.0 in one channel cannot outrank two-channel agreement.
  assert_true(fused[1].id == 3L)
  assert_true(fused[0].sources.length() == 2)
}

///|
test "rrf_fuse breaks ties deterministically" {
  let a = [hit(9L, 0.5, "a", None), hit(2L, 0.5, "a", None)]
  // Reversed order: each id is rank 1 in one channel and rank 2 in the
  // other, so both have the same RRF score and the id tie-break decides.
  let b = [hit(2L, 0.5, "b", None), hit(9L, 0.5, "b", None)]
  let fused = @moon-qdrant.rrf_fuse([a, b])
  assert_true(fused[0].id == 2L)
  assert_true(fused[1].id == 9L)
}

///|
test "rrf_fuse contributes once per channel even with duplicate ids" {
  // A merged channel can contain the same id twice. Each channel may still
  // contribute only once, otherwise one duplicated list outranks genuine
  // agreement between two channels.
  let channel = [hit(1L, 0.9, "semantic", None), hit(1L, 0.8, "semantic", None)]
  let fused = @moon-qdrant.rrf_fuse([channel], k=0)
  assert_true(fused.length() == 1)
  assert_true(fused[0].rrf_score > 0.99 && fused[0].rrf_score < 1.01)
  assert_true(fused[0].sources.length() == 1)
  assert_true(fused[0].score > 0.89)
}

///|
test "rrf_fuse keeps the payload belonging to the highest-scoring hit" {
  let a = [hit(1L, 0.5, "a", Some(doc_payload("doc-A", "acme")))]
  let b = [hit(1L, 0.9, "b", Some(doc_payload("doc-B", "acme")))]
  let fused = @moon-qdrant.rrf_fuse([a, b])
  assert_true(fused[0].id == 1L)
  match fused[0].payload {
    Some(Object(m)) =>
      match m.get("doc_id") {
        Some(String(id)) => assert_true(id == "doc-B")
        _ => fail("expected a doc_id")
      }
    _ => fail("expected a payload")
  }
}

///|
test "dedupe_hits keeps the best copy of a business document" {
  let hits = [
    hit(1L, 0.9, "semantic", Some(doc_payload("doc-A", "acme"))),
    hit(2L, 0.95, "keyword", Some(doc_payload("doc-A", "acme"))),
    hit(3L, 0.8, "semantic", Some(doc_payload("doc-B", "acme"))),
  ]
  let fused = @moon-qdrant.rrf_fuse([[hits[0], hits[2]], [hits[1]]])
  let out = @moon-qdrant.dedupe_hits(fused)
  assert_true(out.length() == 2)
  assert_true(out[0].id == 2L)
  assert_true(out[1].id == 3L)
}

///|
test "tenant scope injects a filter and rejects foreign payloads" {
  let scope = @moon-qdrant.TenantScope::new("acme")
  let user = @moon-qdrant.Filter::new().must(
    @moon-qdrant.Condition::match_keyword("lang", "zh"),
  )
  let scoped = scope.filter(user=Some(user))
  let json = scoped.to_json().stringify()
  assert_true(json.contains("acme"))
  assert_true(json.contains("zh"))
  assert_true(scope.allows(Some(doc_payload("doc-A", "acme"))))
  assert_true(!scope.allows(Some(doc_payload("doc-A", "globex"))))
  assert_true(!scope.allows(None))
  let out = scope.filter_hits([
    hit(1L, 0.9, "semantic", Some(doc_payload("doc-A", "acme"))),
    hit(2L, 0.8, "semantic", Some(doc_payload("doc-B", "globex"))),
  ])
  assert_true(out.length() == 1)
  assert_true(out[0].id == 1L)
}

///|
test "tenant scope rejects an empty tenant id" {
  let empty = try {
    let _ = @moon-qdrant.TenantScope::new("")
    false
  } catch {
    _ => true
  }
  assert_true(empty)
}

///|
test "chunk_points splits writes into bounded batches" {
  let points : Array[@moon-qdrant.PointStruct] = []
  for id in 0..<5 {
    points.push(
      @moon-qdrant.PointStruct::new(
        id.to_int64(),
        [0.1, 0.2, 0.3, 0.4],
        Json::object({}),
      ),
    )
  }
  let chunks = @moon-qdrant.chunk_points(points, 2)
  assert_true(chunks.length() == 3)
  assert_true(chunks[0].length() == 2)
  assert_true(chunks[1].length() == 2)
  assert_true(chunks[2].length() == 1)
  assert_true(chunks[0][0].id == 0L)
  assert_true(chunks[2][0].id == 4L)
}
