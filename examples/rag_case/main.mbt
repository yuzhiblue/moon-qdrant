///|
/// Multi-tenant hybrid retrieval case. The two recall channels are genuinely
/// different: Qdrant does dense vector search for one, and the client does
/// literal term matching over tenant-scoped documents for the other.
///
/// Division of labour:
///   Qdrant      - vector search, payload filtering, candidate enumeration
///   this client - term scoring, cross-channel fusion, tenant verification,
///                 business-key dedupe, bounded writes, full pagination
///
/// The lexical scorer is deliberately small. BM25 and tokenisation are
/// already implemented by niuniu513-ask/MoonRetrieve; a production pipeline
/// can feed those scores into the same RankedHit channel contract unchanged.

///|
fn json_terms(terms : Array[String]) -> Json {
  let out : Array[Json] = []
  for term in terms {
    out.push(Json::string(term))
  }
  Json::array(out)
}

///|
fn doc_point(
  id : Int64,
  doc_id : String,
  tenant : String,
  text : String,
  terms : Array[String],
  vector : Array[Double],
) -> @moon_qdrant.PointStruct {
  @moon_qdrant.PointStruct::new(id, vector, {
    "doc_id": Json::string(doc_id),
    "tenant_id": Json::string(tenant),
    "text": Json::string(text),
    "lang": Json::string("zh"),
    "terms": json_terms(terms),
  })
}

///|
fn channel_hits(
  hits : Array[@moon_qdrant.ScoredPoint],
  source : String,
) -> Array[@moon_qdrant.RankedHit] {
  let out : Array[@moon_qdrant.RankedHit] = []
  for hit in hits {
    out.push(@moon_qdrant.RankedHit::from_scored_point(hit, source))
  }
  out
}

///|
fn payload_string(payload : Json?, key : String) -> String {
  match payload {
    Some(Object(m)) =>
      match m.get(key) {
        Some(String(s)) => s
        _ => ""
      }
    _ => ""
  }
}

///|
fn payload_terms(payload : Json?) -> Array[String] {
  match payload {
    Some(Object(m)) =>
      match m.get("terms") {
        Some(Array(items)) => {
          let out : Array[String] = []
          for item in items {
            match item {
              String(s) => out.push(s)
              _ => ()
            }
          }
          out
        }
        _ => []
      }
    _ => []
  }
}

///|
/// Fraction of query terms present in the document's pre-tokenised terms.
/// Normalised to [0,1] so it is comparable with a cosine score when RRF
/// breaks a tie. A document with no matching term is not a lexical hit.
fn lexical_score(payload : Json?, query_terms : Array[String]) -> Double {
  if query_terms.is_empty() {
    0.0
  } else {
    let doc_terms = payload_terms(payload)
    let mut matched = 0
    for query_term in query_terms {
      let mut found = false
      for doc_term in doc_terms {
        if query_term == doc_term {
          found = true
        }
      }
      if found {
        matched = matched + 1
      }
    }
    matched.to_double() / query_terms.length().to_double()
  }
}

///|
/// The lexical channel: candidate documents come from a tenant-scoped
/// scroll; ranking is by literal term overlap, not by a vector.
fn lexical_channel(
  points : Array[@moon_qdrant.PointStruct],
  query_terms : Array[String],
) -> Array[@moon_qdrant.RankedHit] {
  let out : Array[@moon_qdrant.RankedHit] = []
  for point in points {
    let score = lexical_score(Some(point.payload), query_terms)
    if score > 0.0 {
      out.push({
        id: point.id,
        score,
        rrf_score: 0.0,
        sources: ["lexical"],
        payload: Some(point.payload),
      })
    }
  }
  out.sort_by((a, b) => {
    if a.score > b.score {
      -1
    } else if a.score < b.score {
      1
    } else if a.id < b.id {
      -1
    } else if a.id > b.id {
      1
    } else {
      0
    }
  })
  out
}

///|
fn print_channel(name : String, hits : Array[@moon_qdrant.RankedHit]) -> Unit {
  println("CHANNEL \{name}: \{hits.length()} hits")
  for hit in hits {
    let doc = payload_string(hit.payload, "doc_id")
    println(
      "  doc=\{doc} id=\{hit.id} score=\{hit.score} rrf=\{hit.rrf_score} sources=\{hit.sources.length()}",
    )
  }
}

///|
async fn run(base : String) -> Unit {
  let client = @moon_qdrant.QdrantClient::new(base, timeout_ms=60_000)
  defer client.close()

  let scope = @moon_qdrant.TenantScope::new("acme")
  let collection = "rag_case_hybrid"
  if client.collection_exists(collection) {
    delete_and_wait(client, collection)
  }
  client.create_collection(
    collection,
    @moon_qdrant.CollectionConfig::new(
      @moon_qdrant.VectorParams::new(4, @moon_qdrant.Distance::Cosine),
    ),
  )

  // Four acme documents, one globex document that must never be returned,
  // and one extra copy of kb-004 to exercise business-key deduplication.
  let docs = [
    doc_point(
      1L,
      "kb-001",
      "acme",
      "向量数据库用于存储 embedding",
      ["vector", "database", "embedding", "storage"],
      [0.1, 0.2, 0.3, 0.4],
    ),
    doc_point(
      2L,
      "kb-002",
      "acme",
      "RAG 需要检索与生成两个阶段",
      ["rag", "retrieval", "generation"],
      [0.2, 0.3, 0.4, 0.5],
    ),
    doc_point(
      3L,
      "kb-003",
      "acme",
      "MoonBit 适合编写可靠的工具链",
      ["moonbit", "toolchain", "reliable"],
      [0.3, 0.4, 0.5, 0.6],
    ),
    doc_point(
      4L,
      "kb-004",
      "acme",
      "混合检索合并多路召回结果",
      ["hybrid", "retrieval", "recall", "fusion"],
      [0.4, 0.5, 0.6, 0.7],
    ),
    doc_point(
      5L,
      "foreign-001",
      "globex",
      "另一个租户的私密文档",
      ["retrieval", "secret"],
      [0.9, 0.9, 0.9, 0.9],
    ),
    doc_point(
      6L,
      "kb-004",
      "acme",
      "混合检索的另一份副本",
      ["hybrid", "retrieval", "recall", "fusion"],
      [0.45, 0.55, 0.65, 0.75],
    ),
  ]

  let chunks = @moon_qdrant.chunk_points(docs, 2)
  println("RAG: wrote \{chunks.length()} bounded batches")
  for chunk in chunks {
    client.upsert_points_batch(collection, chunk)
  }

  let user_filter = @moon_qdrant.Filter::new().must(
    @moon_qdrant.Condition::match_keyword("lang", "zh"),
  )
  let scoped = scope.filter(user=Some(user_filter))

  // Semantic channel input: a dense vector. Output: cosine-ranked hits.
  let query_vector = [0.1, 0.2, 0.3, 0.4]
  let semantic = channel_hits(
    client.search_points_with_filter(collection, query_vector, 10, scoped),
    "semantic",
  )

  // Lexical channel input: literal terms. Output: term-overlap-ranked hits.
  // Candidates are enumerated by the same tenant-scoped scroll used for
  // export, so no channel can bypass the tenant filter.
  let query_terms = ["retrieval", "recall"]
  let candidates = @moon_qdrant.scroll_all(
    client,
    collection,
    page_size=2,
    max_pages=100,
    filter=Some(scoped),
  )
  let lexical = lexical_channel(candidates, query_terms)

  print_channel("semantic (input: vector [0.1,0.2,0.3,0.4])", semantic)
  print_channel("lexical (input: terms [retrieval, recall])", lexical)

  // Client-side fusion of two independently ranked lists, then tenant
  // verification and business-key deduplication.
  let fused = @moon_qdrant.rrf_fuse([semantic, lexical], k=60, limit=5)
  print_channel("fused (RRF k=60)", fused)
  let guarded = scope.filter_hits(fused)
  let answers = @moon_qdrant.dedupe_hits(guarded)
  print_channel("final (tenant-safe, deduped by doc_id)", answers)

  let all = @moon_qdrant.scroll_all(
    client,
    collection,
    page_size=2,
    max_pages=100,
    filter=Some(scoped),
  )
  println("RAG: paged export returned \{all.length()} tenant documents")
  client.delete_collection(collection)
}

///|
fn main {
  let argv = @env.args()
  let base = if argv.length() > 1 { argv[1] } else { "http://localhost:6333" }
  run(base)
}

///|
/// The lexical channel is pure client logic, so it is covered without a
/// server. Note that id 3 wins on terms even though id 1 has the vector
/// closest to the semantic query: the two channels really disagree.
test "lexical channel ranks by literal terms, not by vector" {
  let points = [
    doc_point(
      1L,
      "kb-001",
      "acme",
      "向量数据库",
      ["vector", "database", "embedding"],
      [0.1, 0.2, 0.3, 0.4],
    ),
    doc_point(
      2L,
      "kb-002",
      "acme",
      "RAG 检索",
      ["rag", "retrieval", "generation"],
      [0.9, 0.9, 0.9, 0.9],
    ),
    doc_point(
      3L,
      "kb-003",
      "acme",
      "混合召回",
      ["hybrid", "retrieval", "recall"],
      [0.1, 0.1, 0.1, 0.1],
    ),
  ]
  let hits = lexical_channel(points, ["retrieval", "recall"])
  assert_true(hits.length() == 2)
  assert_true(hits[0].id == 3L)
  assert_true(hits[0].score > 0.99 && hits[0].score < 1.01)
  assert_true(hits[1].id == 2L)
  assert_true(hits[1].score > 0.49 && hits[1].score < 0.51)
}

///|
/// Qdrant removes collections asynchronously. Wait for the registry entry to
/// disappear before recreating it, otherwise the next create can answer 409.
async fn delete_and_wait(
  client : @moon_qdrant.QdrantClient,
  name : String,
) -> Unit {
  client.delete_collection(name)
  let mut tries = 0
  while tries < 20 && client.collection_exists(name) {
    tries = tries + 1
  }
  if client.collection_exists(name) {
    abort("collection still exists after delete: " + name)
  }
}
