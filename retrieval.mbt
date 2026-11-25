///|
/// Client-side retrieval semantics for RAG pipelines.
///
/// Qdrant supplies vector search, payload filtering and scrolling, but it
/// does not decide how several result channels are merged, how duplicates
/// across channels are resolved, how tenant isolation is enforced on data
/// returned by a provider, or how a large write is split into safe batches.
/// Those responsibilities belong to the client, and this module implements
/// them independently of any HTTP transport or server version.

///|
/// A hit that can be fused across retrieval channels: the original point id
/// and score, the channel it came from and its payload.
pub(all) struct RankedHit {
  id : Int64
  score : Double
  rrf_score : Double
  sources : Array[String]
  payload : Json?
}

///|
/// Wrap a search hit from one provider/channel for fusion.
pub fn RankedHit::from_scored_point(
  point : ScoredPoint,
  source : String,
) -> RankedHit {
  {
    id: point.id,
    score: point.score,
    rrf_score: 0.0,
    sources: [source],
    payload: point.payload,
  }
}

///|
/// Compare by fused score, then by the number of agreeing channels, then by
/// id (a total order, so results are deterministic even on ties).
fn better(a : RankedHit, b : RankedHit) -> Bool {
  if a.rrf_score > b.rrf_score {
    true
  } else if a.rrf_score < b.rrf_score {
    false
  } else if a.sources.length() > b.sources.length() {
    true
  } else if a.sources.length() < b.sources.length() {
    false
    // Prefer the higher original score, then the smaller id.
  } else if a.score > b.score {
    true
  } else if a.score < b.score {
    false
  } else {
    a.id < b.id
  }
}

///|
/// Fuse ranked lists with Reciprocal Rank Fusion:
///
///   RRF(d) = sum over channels 1 / (k + rank(d))
///
/// ranks start at 1. This is computed by the client over the ordered hits
/// returned by each channel; it is deliberately not the server's own fusion
/// API, because these channels may be different collections, filters, or
/// even different VectorProvider implementations.
pub fn rrf_fuse(
  channels : Array[Array[RankedHit]],
  k~ : Int32 = 60,
  limit~ : Int32 = 20,
) -> Array[RankedHit] raise {
  if k < 0 || limit < 0 {
    raise Failure("rrf_fuse: k and limit must be non-negative")
  }
  let acc : Map[Int64, RankedHit] = Map([])
  for channel in channels {
    let mut rank = 0
    for hit in channel {
      rank = rank + 1
      let contribution = 1.0 / (k.to_double() + rank.to_double())
      match acc.get(hit.id) {
        Some(prev) => {
          let sources = prev.sources
          let source = hit.source_name()
          let first_from_source = !sources.contains(source)
          if first_from_source {
            sources.push(source)
          }
          let higher_score = hit.score > prev.score
          // One contribution per channel even when a channel returns the
          // same id twice (a merged list can contain duplicates).
          let next_rrf = if first_from_source {
            prev.rrf_score + contribution
          } else {
            prev.rrf_score
          }
          let next_score = if higher_score { hit.score } else { prev.score }
          // Keep the payload that belongs to the highest-scoring hit:
          // business keys and tenant fields must not come from a different
          // copy than the score used to rank it.
          let next_payload = if higher_score {
            hit.payload
          } else {
            prev.payload
          }
          acc[hit.id] = {
            id: prev.id,
            score: next_score,
            rrf_score: next_rrf,
            sources,
            payload: next_payload,
          }
        }
        None =>
          acc[hit.id] = {
            id: hit.id,
            score: hit.score,
            rrf_score: contribution,
            sources: hit.sources,
            payload: hit.payload,
          }
      }
    }
  }
  let hits : Array[RankedHit] = []
  for id in acc.keys() {
    hits.push(acc[id])
  }
  hits.sort_by((a, b) => {
    if better(a, b) {
      -1
    } else if better(b, a) {
      1
    } else {
      0
    }
  })
  if hits.length() > limit {
    hits[:limit].to_owned()
  } else {
    hits
  }
}

///|
/// The first channel name of a fused hit.
fn RankedHit::source_name(self : RankedHit) -> String {
  if self.sources.is_empty() {
    ""
  } else {
    self.sources[0]
  }
}

///|
/// Drop duplicate documents by a business key in the payload (default
/// `doc_id`), keeping the best-ranked occurrence. Without a usable key the
/// point id is used. The input must already be ordered by rank.
pub fn dedupe_hits(
  hits : Array[RankedHit],
  key~ : String = "doc_id",
) -> Array[RankedHit] {
  let best : Map[String, RankedHit] = Map([])
  for hit in hits {
    let biz_key = match hit.payload {
      Some(Object(m)) =>
        match m.get(key) {
          Some(v) => "payload:" + v.stringify()
          None => "id:" + hit.id.to_string()
        }
      _ => "id:" + hit.id.to_string()
    }
    match best.get(biz_key) {
      Some(prev) => if better(hit, prev) { best[biz_key] = hit }
      None => best[biz_key] = hit
    }
  }
  let out : Array[RankedHit] = []
  for hit in hits {
    let biz_key = match hit.payload {
      Some(Object(m)) =>
        match m.get(key) {
          Some(v) => "payload:" + v.stringify()
          None => "id:" + hit.id.to_string()
        }
      _ => "id:" + hit.id.to_string()
    }
    match best.get(biz_key) {
      Some(kept) =>
        if kept.id == hit.id {
          out.push(kept)
          best.remove(biz_key)
        }
      None => ()
    }
  }
  out
}

///|
/// A tenant scope that every retrieval must be built through. It both adds
/// the tenant condition to a user filter and verifies returned payloads, so
/// a provider that silently ignores the filter cannot leak another tenant's
/// document into the fused result.
pub struct TenantScope {
  tenant_id : String
}

///|
/// Create a scope. An empty tenant id is rejected: it would make the
/// mandatory condition vacuous.
pub fn TenantScope::new(tenant_id : String) -> TenantScope raise {
  if tenant_id.is_empty() {
    raise Failure("TenantScope: tenant id must not be empty")
  }
  { tenant_id, }
}

///|
/// Combine a user-supplied filter with the mandatory tenant condition.
pub fn TenantScope::filter(
  self : TenantScope,
  user~ : Filter? = None,
) -> Filter {
  let tenant_only = Condition::match_keyword("tenant_id", self.tenant_id)
  match user {
    Some(f) => f.must(tenant_only)
    None => Filter::new().must(tenant_only)
  }
}

///|
/// Whether a returned payload actually belongs to this tenant. Absent
/// payloads are rejected: the caller asked for scoped retrieval.
pub fn TenantScope::allows(self : TenantScope, payload : Json?) -> Bool {
  match payload {
    Some(Object(m)) =>
      match m.get("tenant_id") {
        Some(String(id)) => id == self.tenant_id
        _ => false
      }
    _ => false
  }
}

///|
/// Remove hits whose payload does not belong to the scope.
pub fn TenantScope::filter_hits(
  self : TenantScope,
  hits : Array[RankedHit],
) -> Array[RankedHit] {
  let out : Array[RankedHit] = []
  for hit in hits {
    if self.allows(hit.payload) {
      out.push(hit)
    }
  }
  out
}

///|
/// Split points into chunks of at most `size` for bounded batch writes.
pub fn chunk_points(
  points : Array[PointStruct],
  size : Int32,
) -> Array[Array[PointStruct]] raise {
  if size <= 0 {
    raise Failure("chunk_points: size must be positive")
  }
  let out : Array[Array[PointStruct]] = []
  let mut i = 0
  while i < points.length() {
    let end = if i + size < points.length() {
      i + size
    } else {
      points.length()
    }
    out.push(points[i:end].to_owned())
    i = end
  }
  out
}

///|
/// Fetch every page of a scroll query, with an explicit upper bound so a
/// broken `next_page_offset` cannot turn into an infinite loop. The server
/// returns one page at a time; accumulating the pages is the client's job.
pub async fn scroll_all(
  client : QdrantClient,
  collection : String,
  page_size~ : Int32 = 100,
  max_pages~ : Int32 = 1000,
  filter~ : Filter? = None,
) -> Array[PointStruct] {
  if page_size <= 0 || max_pages <= 0 {
    raise Failure("scroll_all: page_size and max_pages must be positive")
  }
  let out : Array[PointStruct] = []
  let mut offset : Int64? = None
  let mut pages = 0
  let mut exhausted = false
  while pages < max_pages {
    let page = client.scroll_points(collection, page_size, filter~, offset~)
    for point in page.points {
      out.push(point)
    }
    pages = pages + 1
    match page.next_page_offset {
      Some(next) =>
        match offset {
          Some(prev) if prev == next =>
            raise Failure(
              "scroll_all: server repeated offset " + next.to_string(),
            )
          _ => offset = Some(next)
        }
      None => {
        exhausted = true
        break
      }
    }
  }
  if pages == max_pages && !exhausted {
    raise Failure("scroll_all: exceeded max_pages=" + max_pages.to_string())
  }
  out
}
