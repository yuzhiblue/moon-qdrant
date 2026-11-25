///|
/// A business case for the client-side retrieval layer: an enterprise,
/// multi-tenant knowledge base where one question is answered from two
/// retrieval channels (semantic + lexical). Qdrant performs each individual
/// search; the client owns tenant isolation, channel fusion, deduplication,
/// batch partitioning and full-result pagination.

///|
fn doc_point(
  id : Int64,
  doc_id : String,
  tenant : String,
  text : String,
  vector : Array[Double],
) -> @moon_qdrant.PointStruct {
  @moon_qdrant.PointStruct::new(id, vector, {
    "doc_id": Json::string(doc_id),
    "tenant_id": Json::string(tenant),
    "text": Json::string(text),
    "lang": Json::string("zh"),
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
async fn run(base : String) -> Unit {
  let client = @moon_qdrant.QdrantClient::new(base, timeout_ms=60_000)
  defer client.close()

  // Tenant scope is constructed once; every retrieval below is built through
  // it. It injects a mandatory tenant condition AND checks returned payloads.
  let scope = @moon_qdrant.TenantScope::new("acme")
  let semantic = "rag_case_semantic"
  let lexical = "rag_case_lexical"
  for collection in [semantic, lexical] {
    if client.collection_exists(collection) {
      client.delete_collection(collection)
    }
    client.create_collection(
      collection,
      @moon_qdrant.CollectionConfig::new(
        @moon_qdrant.VectorParams::new(4, @moon_qdrant.Distance::Cosine),
      ),
    )
  }

  // Four documents for tenant acme plus one for another tenant. The foreign
  // document must never reach the final answer.
  let docs = [
    doc_point(1L, "kb-001", "acme", "向量数据库用于存储 embedding", [
      0.1, 0.2, 0.3, 0.4,
    ]),
    doc_point(2L, "kb-002", "acme", "RAG 需要检索与生成两个阶段", [
      0.2, 0.3, 0.4, 0.5,
    ]),
    doc_point(3L, "kb-003", "acme", "MoonBit 适合编写可靠的工具链", [
      0.3, 0.4, 0.5, 0.6,
    ]),
    doc_point(4L, "kb-004", "acme", "混合检索合并多路召回结果", [
      0.4, 0.5, 0.6, 0.7,
    ]),
    doc_point(5L, "foreign-001", "globex", "另一个租户的私密文档", [
      0.9, 0.9, 0.9, 0.9,
    ]),
  ]

  // Bounded batch writes: the client partitions the documents instead of
  // trusting the caller to pick a safe batch size.
  let chunks = @moon_qdrant.chunk_points(docs, 2)
  println("RAG: wrote \{chunks.length()} bounded batches into two channels")
  for chunk in chunks {
    client.upsert_points_batch(semantic, chunk)
    client.upsert_points_batch(lexical, chunk)
  }

  let user_filter = @moon_qdrant.Filter::new().must(
    @moon_qdrant.Condition::match_keyword("lang", "zh"),
  )
  let scoped = scope.filter(user=Some(user_filter))
  let query = [0.1, 0.2, 0.3, 0.4]
  let semantic_hits = client.search_points_with_filter(
    semantic, query, 10, scoped,
  )
  let lexical_hits = client.search_points_with_filter(
    lexical, query, 10, scoped,
  )

  // Cross-channel fusion is a client decision: reciprocal rank fusion over
  // two independently ordered result lists, then strict tenant guarding and
  // deduplication by business document id.
  let channels = [
    channel_hits(semantic_hits, "semantic"),
    channel_hits(lexical_hits, "lexical"),
  ]
  let fused = @moon_qdrant.rrf_fuse(channels, k=2, limit=5)
  let guarded = scope.filter_hits(fused)
  let answers = @moon_qdrant.dedupe_hits(guarded)
  println("RAG: \{answers.length()} fused, tenant-safe documents")
  for answer in answers {
    let text = match answer.payload {
      Some(Object(m)) =>
        match m.get("text") {
          Some(String(t)) => t
          _ => ""
        }
      _ => ""
    }
    println(
      "RAG: score=\{answer.rrf_score} id=\{answer.id} sources=\{answer.sources.length()} text=\{text}",
    )
  }

  // Full export across pages: the server returns one scroll page at a time,
  // the client accumulates all pages under an explicit safety bound.
  let all = @moon_qdrant.scroll_all(
    client,
    semantic,
    page_size=2,
    max_pages=100,
    filter=Some(scoped),
  )
  println("RAG: paged export returned \{all.length()} tenant documents")

  // Exact-boundary regression: four documents at page_size=2 are exactly
  // two pages. Reaching max_pages on the last page is not an overrun.
  let exact = @moon_qdrant.scroll_all(
    client,
    semantic,
    page_size=2,
    max_pages=2,
    filter=Some(scoped),
  )
  println(
    "RAG: exact-boundary export returned \{exact.length()} tenant documents",
  )

  client.delete_collection(semantic)
  client.delete_collection(lexical)
}

///|
fn main {
  let argv = @env.args()
  let base = if argv.length() > 1 { argv[1] } else { "http://localhost:6333" }
  run(base)
}
