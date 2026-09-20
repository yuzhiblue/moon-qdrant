///|
/// Data models for the Qdrant REST API subset implemented by moon-qdrant.
///
/// Types in this file are plain data: they know how to convert themselves
/// to/from JSON so the transport layer stays thin and testable.

///|
/// Distance metric used by a Qdrant vector collection.
/// Wire values follow the Qdrant REST API enum names.
pub(all) enum Distance {
  Cosine
  Euclid
  Dot
}

///|
/// Convert a Distance to its Qdrant wire string.
pub fn Distance::to_wire(self : Distance) -> String {
  match self {
    Cosine => "Cosine"
    Euclid => "Euclid"
    Dot => "Dot"
  }
}

///|
/// Parse a Distance from its Qdrant wire string.
/// Returns None for unknown values.
pub fn Distance::from_wire(s : String) -> Distance? {
  match s {
    "Cosine" => Some(Cosine)
    "Euclid" => Some(Euclid)
    "Dot" => Some(Dot)
    _ => None
  }
}

///|
/// Vector configuration for a collection, as accepted by
/// PUT /collections/{name}.
pub struct VectorParams {
  size : Int
  distance : Distance
}

///|
pub fn VectorParams::new(size : Int, distance : Distance) -> VectorParams {
  { size, distance, }
}

///|
/// Convert to the JSON body fragment used by the Qdrant API:
/// `{ "size": 4, "distance": "Cosine" }`.
pub fn VectorParams::to_json(self : VectorParams) -> Json {
  {
    "size": Json::number(self.size.to_double()),
    "distance": Json::string(self.distance.to_wire()),
  }
}

///|
/// Parse VectorParams from the config fragment returned by
/// GET /collections/{name}.
pub fn VectorParams::from_json(json : Json) -> VectorParams? {
  guard json is Object(members) else { return None }
  let size = match members.get("size") {
    Some(Number(n, ..)) => n.to_int()
    _ => return None
  }
  let distance = match members.get("distance") {
    Some(String(s)) =>
      match Distance::from_wire(s) {
        Some(d) => d
        None => return None
      }
    _ => return None
  }
  Some({ size, distance, })
}

///|
/// Collection configuration accepted by PUT /collections/{name}.
pub struct CollectionConfig {
  vectors : VectorParams
}

///|
pub fn CollectionConfig::new(vectors : VectorParams) -> CollectionConfig {
  { vectors, }
}

///|
pub fn CollectionConfig::to_json(self : CollectionConfig) -> Json {
  { "vectors": self.vectors.to_json() }
}

///|
/// Convert a dense vector to its JSON array representation.
/// Shared by point serialization, batch upsert and search.
pub fn vector_to_json(vector : Array[Double]) -> Json {
  let vec : Array[Json] = []
  for x in vector {
    vec.push(Json::number(x))
  }
  Json::array(vec)
}

///|
/// A single point: an id, a dense vector, and an optional JSON payload.
pub struct PointStruct {
  id : Int
  vector : Array[Double]
  payload : Json
}

///|
pub fn PointStruct::new(
  id : Int,
  vector : Array[Double],
  payload : Json,
) -> PointStruct {
  { id, vector, payload, }
}

///|
/// Convert to the point object used by PUT /collections/{name}/points:
/// `{ "id": 1, "vector": [...], "payload": {...} }`.
pub fn PointStruct::to_json(self : PointStruct) -> Json {
  {
    "id": Json::number(self.id.to_double()),
    "vector": vector_to_json(self.vector),
    "payload": self.payload,
  }
}

///|
/// Parse a point object as returned by the point read endpoint:
/// `{ "id": 1, "vector": [...], "payload": {...} }`.
pub fn PointStruct::from_json(json : Json) -> PointStruct? {
  guard json is Object(members) else { return None }
  let id = match members.get("id") {
    Some(Number(n, ..)) => n.to_int()
    _ => return None
  }
  let vector = match members.get("vector") {
    Some(Array(arr)) =>
      if arr.is_empty() {
        return None
      } else {
        let vec : Array[Double] = []
        for item in arr {
          match item {
            Number(n, ..) => vec.push(n)
            _ => return None
          }
        }
        vec
      }
    _ => return None
  }
  let payload = members.get("payload").unwrap_or(Json::object({}))
  Some({ id, vector, payload, })
}

///|
/// Minimal parsed view of one collection, from GET /collections.
pub struct CollectionSummary {
  name : String
}

///|
pub fn CollectionSummary::from_json(json : Json) -> CollectionSummary? {
  guard json is Object(members) else { return None }
  match members.get("name") {
    Some(String(s)) => Some({ name: s, })
    _ => None
  }
}

///|
/// Parsed result of GET /collections: the list of collection names.
pub struct CollectionList {
  names : Array[String]
}

///|
pub fn CollectionList::from_json(json : Json) -> CollectionList? {
  guard json is Object(members) else { return None }
  let result = match members.get("result") {
    Some(Object(r)) => r
    _ => return None
  }
  let collections = match result.get("collections") {
    Some(Array(arr)) => arr
    _ => return None
  }
  let names : Array[String] = []
  for item in collections {
    match CollectionSummary::from_json(item) {
      Some(summary) => names.push(summary.name)
      None => continue
    }
  }
  Some({ names, })
}

///|
/// Detailed information about a collection, from GET /collections/{name}.
pub struct CollectionInfo {
  status : String
  points_count : Int?
  vectors : VectorParams?
}

///|
/// Parse the result object of GET /collections/{name} into a CollectionInfo.
/// `points_count` and `vectors` are optional because Qdrant may omit them
/// while a collection is still building.
pub fn CollectionInfo::from_json(json : Json) -> CollectionInfo? {
  guard json is Object(members) else { return None }
  let result = match members.get("result") {
    Some(Object(r)) => r
    _ => return None
  }
  let status = match result.get("status") {
    Some(String(s)) => s
    _ => return None
  }
  let points_count = match result.get("points_count") {
    Some(Number(n, ..)) => Some(n.to_int())
    _ => None
  }
  let vectors = match result.get("config") {
    Some(Object(config)) =>
      match config.get("params") {
        Some(Object(params)) =>
          match params.get("vectors") {
            Some(vectors_json) => VectorParams::from_json(vectors_json)
            None => None
          }
        _ => None
      }
    _ => None
  }
  Some({ status, points_count, vectors, })
}

///|
/// One hit returned by the search endpoint: a point id, its similarity score,
/// and the payload attached to the point (when requested).
pub struct ScoredPoint {
  id : Int
  score : Double
  payload : Json?
}

///|
/// Parse a search hit object:
/// `{ "id": 1, "score": 0.99, "payload": {...} }`.
pub fn ScoredPoint::from_json(json : Json) -> ScoredPoint? {
  guard json is Object(members) else { return None }
  let id = match members.get("id") {
    Some(Number(n, ..)) => n.to_int()
    _ => return None
  }
  let score = match members.get("score") {
    Some(Number(n, ..)) => n
    _ => return None
  }
  let payload = members.get("payload")
  Some({ id, score, payload, })
}

///|
/// Parse the `result` array of a search response into scored points.
/// Returns None when the response does not match the expected shape.
pub fn parse_search_result(json : Json) -> Array[ScoredPoint]? {
  match json {
    Object(members) =>
      match members.get("result") {
        Some(Array(arr)) => {
          let out : Array[ScoredPoint] = []
          for item in arr {
            match ScoredPoint::from_json(item) {
              Some(hit) => out.push(hit)
              None => return None
            }
          }
          Some(out)
        }
        _ => None
      }
    _ => None
  }
}

///|
/// A single payload filter condition, in the subset of Qdrant's filter DSL
/// that covers the common exact-match, set-membership, range and existence
/// cases. Construct one with the `Condition::match_*` / `Condition::range_*`
/// helpers and combine them inside a `Filter`.
pub(all) enum Condition {
  MatchValue(String, Json)
  MatchKeyword(String, String)
  MatchValues(String, Array[Json])
  Range(String, Double?, Double?, Double?, Double?)
  IsEmpty(String)
  IsNull(String)
}

///|
/// Convenience constructor: payload field equals a single JSON value.
pub fn Condition::match_value(field : String, value : Json) -> Condition {
  MatchValue(field, value)
}

///|
/// Convenience constructor: payload field equals a keyword string.
pub fn Condition::match_keyword(field : String, keyword : String) -> Condition {
  MatchKeyword(field, keyword)
}

///|
/// Convenience constructor: payload field equals one of the given values.
pub fn Condition::match_values(
  field : String,
  values : Array[Json],
) -> Condition {
  MatchValues(field, values)
}

///|
/// Convenience constructor: numeric range on a payload field.
/// All four bounds are optional; omitted bounds are dropped from the
/// serialized filter.
pub fn Condition::range(
  field : String,
  gte? : Double? = None,
  lte? : Double? = None,
  gt? : Double? = None,
  lt? : Double? = None,
) -> Condition {
  Range(field, gte, lte, gt, lt)
}

///|
/// Convenience constructor: payload field has no value.
pub fn Condition::is_empty(field : String) -> Condition {
  IsEmpty(field)
}

///|
/// Convenience constructor: payload field is explicitly null.
pub fn Condition::is_null(field : String) -> Condition {
  IsNull(field)
}

///|
/// Serialize a range condition, omitting bounds that are None.
fn range_bounds_json(
  gte : Double?,
  lte : Double?,
  gt : Double?,
  lt : Double?,
) -> Json {
  let members : Map[String, Json] = Map([])
  match gte {
    Some(v) => members["gte"] = Json::number(v)
    None => ()
  }
  match lte {
    Some(v) => members["lte"] = Json::number(v)
    None => ()
  }
  match gt {
    Some(v) => members["gt"] = Json::number(v)
    None => ()
  }
  match lt {
    Some(v) => members["lt"] = Json::number(v)
    None => ()
  }
  Json::object(members)
}

///|
/// Serialize a Condition to its Qdrant filter JSON fragment.
pub fn Condition::to_json(self : Condition) -> Json {
  match self {
    MatchValue(field, value) =>
      { "key": Json::string(field), "match": { "value": value } }
    MatchKeyword(field, keyword) =>
      {
        "key": Json::string(field),
        "match": { "keyword": Json::string(keyword) },
      }
    MatchValues(field, values) =>
      { "key": Json::string(field), "match": { "any": Json::array(values) } }
    Range(field, gte, lte, gt, lt) =>
      {
        "key": Json::string(field),
        "range": range_bounds_json(gte, lte, gt, lt),
      }
    IsEmpty(field) => { "is_empty": { "key": Json::string(field) } }
    IsNull(field) => { "is_null": { "key": Json::string(field) } }
  }
}

///|
/// A Qdrant filter, composed of three conjunctive clause groups.
///
/// Empty clause groups are omitted from the serialized JSON. Use
/// `Filter::new()` to start, then chain `must` / `should` / `must_not`
/// to add conditions.
pub struct Filter {
  must : Array[Condition]
  should : Array[Condition]
  must_not : Array[Condition]
}

///|
/// Create an empty filter.
pub fn Filter::new() -> Filter {
  { must: [], should: [], must_not: [], }
}

///|
/// Append a condition to the `must` clause group (all must hold).
pub fn Filter::must(self : Filter, c : Condition) -> Filter {
  let arr = self.must.copy()
  arr.push(c)
  { ..self, must: arr, }
}

///|
/// Append a condition to the `should` clause group (any may hold).
pub fn Filter::should(self : Filter, c : Condition) -> Filter {
  let arr = self.should.copy()
  arr.push(c)
  { ..self, should: arr, }
}

///|
/// Append a condition to the `must_not` clause group (none may hold).
pub fn Filter::must_not(self : Filter, c : Condition) -> Filter {
  let arr = self.must_not.copy()
  arr.push(c)
  { ..self, must_not: arr, }
}

///|
/// Serialize the filter to Qdrant's filter JSON. Empty clause groups are
/// omitted so the serialized object only contains non-empty groups.
pub fn Filter::to_json(self : Filter) -> Json {
  let members : Map[String, Json] = Map([])
  if !self.must.is_empty() {
    let arr : Array[Json] = []
    for c in self.must {
      arr.push(c.to_json())
    }
    members["must"] = Json::array(arr)
  }
  if !self.should.is_empty() {
    let arr : Array[Json] = []
    for c in self.should {
      arr.push(c.to_json())
    }
    members["should"] = Json::array(arr)
  }
  if !self.must_not.is_empty() {
    let arr : Array[Json] = []
    for c in self.must_not {
      arr.push(c.to_json())
    }
    members["must_not"] = Json::array(arr)
  }
  Json::object(members)
}

///|
/// Result of `POST /collections/{name}/points/scroll`: the points on the
/// current page, and the next page offset when more pages remain.
pub struct ScrollResult {
  points : Array[PointStruct]
  next_page_offset : Int?
}

///|
/// Parse the `result` object of a scroll response.
pub fn ScrollResult::from_json(json : Json) -> ScrollResult? {
  guard json is Object(members) else { return None }
  let points_arr = match members.get("points") {
    Some(Array(arr)) => arr
    _ => return None
  }
  let points : Array[PointStruct] = []
  for item in points_arr {
    match PointStruct::from_json(item) {
      Some(p) => points.push(p)
      None => return None
    }
  }
  let next_page_offset = match members.get("next_page_offset") {
    Some(Number(n, ..)) => Some(n.to_int())
    None => None
    _ => None
  }
  Some({ points, next_page_offset, })
}

///|
/// Parse the `result` object of a count response: `{ "count": 42 }`.
/// Returns None when the shape does not match.
pub fn parse_count_result(json : Json) -> Int? {
  match json {
    Object(members) =>
      match members.get("count") {
        Some(Number(n, ..)) => Some(n.to_int())
        _ => None
      }
    _ => None
  }
}

///|
/// Parse the `result` array of a retrieve response into points.
/// Returns None when the response does not match the expected shape.
pub fn parse_retrieve_result(json : Json) -> Array[PointStruct]? {
  match json {
    Object(members) =>
      match members.get("result") {
        Some(Array(arr)) => {
          let out : Array[PointStruct] = []
          for item in arr {
            match PointStruct::from_json(item) {
              Some(p) => out.push(p)
              None => return None
            }
          }
          Some(out)
        }
        _ => None
      }
    _ => None
  }
}

///|
/// One collection alias entry, as returned by
/// GET /collections/aliases.
pub struct AliasInfo {
  alias_name : String
  collection_name : String
}

///|
/// Parse one alias entry: `{ "alias_name": "prod", "collection_name": "demo" }`.
pub fn AliasInfo::from_json(json : Json) -> AliasInfo? {
  guard json is Object(members) else { return None }
  let alias_name = match members.get("alias_name") {
    Some(String(s)) => s
    _ => return None
  }
  let collection_name = match members.get("collection_name") {
    Some(String(s)) => s
    _ => return None
  }
  Some({ alias_name, collection_name, })
}

///|
/// Parse the `result.aliases` array of GET /collections/aliases.
pub fn parse_aliases(json : Json) -> Array[AliasInfo]? {
  match json {
    Object(members) =>
      match members.get("result") {
        Some(Object(result)) =>
          match result.get("aliases") {
            Some(Array(arr)) => {
              let out : Array[AliasInfo] = []
              for item in arr {
                match AliasInfo::from_json(item) {
                  Some(a) => out.push(a)
                  None => return None
                }
              }
              Some(out)
            }
            _ => None
          }
        _ => None
      }
    _ => None
  }
}

///|
/// Build the request body for POST /collections/{name}/points/scroll.
pub fn scroll_request_body(
  limit : Int,
  filter : Filter?,
  offset : Int?,
  with_payload : Bool,
  with_vector : Bool,
) -> Json {
  let members : Map[String, Json] = Map([])
  members["limit"] = Json::number(limit.to_double())
  members["with_payload"] = Json::boolean(with_payload)
  members["with_vector"] = Json::boolean(with_vector)
  match filter {
    Some(f) => members["filter"] = f.to_json()
    None => ()
  }
  match offset {
    Some(o) => members["offset"] = Json::number(o.to_double())
    None => ()
  }
  Json::object(members)
}

///|
/// Build the request body for POST /collections/{name}/points/count.
pub fn count_request_body(filter : Filter?, exact : Bool) -> Json {
  let members : Map[String, Json] = Map([])
  members["exact"] = Json::boolean(exact)
  match filter {
    Some(f) => members["filter"] = f.to_json()
    None => ()
  }
  Json::object(members)
}
