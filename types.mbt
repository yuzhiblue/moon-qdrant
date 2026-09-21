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
///
/// Either a single dense-vector configuration (`vectors`) or a set of named
/// vector configurations (`named_vectors`, via `CollectionConfig::new_named`)
/// can be provided. Qdrant serializes both under the `vectors` key: a single
/// object for the former, an object keyed by vector name for the latter.
pub struct CollectionConfig {
  vectors : VectorParams
  named_vectors : Map[String, VectorParams]?
}

///|
/// Create a collection with a single dense-vector configuration.
pub fn CollectionConfig::new(vectors : VectorParams) -> CollectionConfig {
  { vectors, named_vectors: None, }
}

///|
/// Create a collection with named (multi-) vector configurations, e.g.
/// `{ "text": VectorParams::new(4, Cosine), "image": VectorParams::new(8, Dot) }`.
/// The `vectors` slot holds a placeholder that is never serialized when
/// `named_vectors` is set.
pub fn CollectionConfig::new_named(
  named_vectors : Map[String, VectorParams],
) -> CollectionConfig {
  {
    vectors: VectorParams::new(0, Distance::Cosine),
    named_vectors: Some(named_vectors),
  }
}

///|
/// Convert to the JSON body fragment used by the Qdrant API.
pub fn CollectionConfig::to_json(self : CollectionConfig) -> Json {
  match self.named_vectors {
    Some(named) => {
      let members : Map[String, Json] = Map([])
      for name in named.keys() {
        members[name] = named[name].to_json()
      }
      { "vectors": Json::object(members) }
    }
    None => { "vectors": self.vectors.to_json() }
  }
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
/// A single point: an id, either a dense vector or a set of named vectors,
/// and an optional JSON payload.
pub struct PointStruct {
  id : Int
  vector : Array[Double]
  named_vectors : Map[String, Array[Double]]?
  payload : Json
}

///|
/// Create a point with a single dense vector.
pub fn PointStruct::new(
  id : Int,
  vector : Array[Double],
  payload : Json,
) -> PointStruct {
  { id, vector, named_vectors: None, payload, }
}

///|
/// Create a point with named vectors, e.g.
/// `{ "text": [0.1, 0.2], "image": [0.5, 0.6, 0.7] }`.
pub fn PointStruct::new_named(
  id : Int,
  named_vectors : Map[String, Array[Double]],
  payload : Json,
) -> PointStruct {
  { id, vector: [], named_vectors: Some(named_vectors), payload, }
}

///|
/// Convert to the point object used by PUT /collections/{name}/points:
/// `{ "id": 1, "vector": [...] | {"name": [...]}, "payload": {...} }`.
pub fn PointStruct::to_json(self : PointStruct) -> Json {
  match self.named_vectors {
    Some(named) => {
      let members : Map[String, Json] = Map([])
      for name in named.keys() {
        members[name] = vector_to_json(named[name])
      }
      {
        "id": Json::number(self.id.to_double()),
        "vector": Json::object(members),
        "payload": self.payload,
      }
    }
    None =>
      {
        "id": Json::number(self.id.to_double()),
        "vector": vector_to_json(self.vector),
        "payload": self.payload,
      }
  }
}

///|
/// Parse a point object as returned by the point read endpoint:
/// `{ "id": 1, "vector": [...] | {"name": [...]}, "payload": {...} }`.
/// A dense vector array fills `vector`; a named-vector object fills
/// `named_vectors`.
pub fn PointStruct::from_json(json : Json) -> PointStruct? {
  guard json is Object(members) else { return None }
  let id = match members.get("id") {
    Some(Number(n, ..)) => n.to_int()
    _ => return None
  }
  let payload = members.get("payload").unwrap_or(Json::object({}))
  match members.get("vector") {
    Some(Array(arr)) => {
      if arr.is_empty() {
        return None
      }
      let vec : Array[Double] = []
      for item in arr {
        match item {
          Number(n, ..) => vec.push(n)
          _ => return None
        }
      }
      Some({ id, vector: vec, named_vectors: None, payload, })
    }
    Some(Object(obj)) => {
      let named : Map[String, Array[Double]] = Map([])
      for name in obj.keys() {
        let values : Array[Double] = []
        match obj[name] {
          Array(arr) =>
            for item in arr {
              match item {
                Number(n, ..) => values.push(n)
                _ => return None
              }
            }
          _ => return None
        }
        named[name] = values
      }
      if named.is_empty() {
        return None
      }
      Some({ id, vector: [], named_vectors: Some(named), payload, })
    }
    _ => return None
  }
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
        "match": { "value": Json::string(keyword) },
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

///|
/// A named vector used as the search input: `{ "name": "text", "vector": [...] }`.
/// Send it as the `vector` field of a search request to run the query against
/// one specific named vector of the collection.
pub struct NamedVector {
  name : String
  vector : Array[Double]
}

///|
pub fn NamedVector::new(name : String, vector : Array[Double]) -> NamedVector {
  { name, vector, }
}

///|
/// Convert to the Qdrant wire object: `{ "name": ..., "vector": [...] }`.
pub fn NamedVector::to_json(self : NamedVector) -> Json {
  { "name": Json::string(self.name), "vector": vector_to_json(self.vector) }
}

///|
/// Search-time parameters passed in the `params` field of a search request.
/// Both fields are optional; only the set ones are serialized.
pub struct SearchParams {
  hnsw_ef : Int?
  exact : Bool?
}

///|
pub fn SearchParams::new(
  hnsw_ef? : Int? = None,
  exact? : Bool? = None,
) -> SearchParams {
  { hnsw_ef, exact, }
}

///|
/// Convert to the Qdrant wire object, omitting unset fields.
pub fn SearchParams::to_json(self : SearchParams) -> Json {
  let members : Map[String, Json] = Map([])
  match self.hnsw_ef {
    Some(ef) => members["hnsw_ef"] = Json::number(ef.to_double())
    None => ()
  }
  match self.exact {
    Some(e) => members["exact"] = Json::boolean(e)
    None => ()
  }
  Json::object(members)
}

///|
/// One snapshot entry, from GET /collections/{name}/snapshots or
/// GET /snapshots.
pub struct SnapshotInfo {
  name : String
  creation_time : String?
  size : Int?
}

///|
/// Parse one snapshot entry: `{ "name": "snap-1", "creation_time": "...", "size": 123 }`.
pub fn SnapshotInfo::from_json(json : Json) -> SnapshotInfo? {
  guard json is Object(members) else { return None }
  let name = match members.get("name") {
    Some(String(s)) => s
    _ => return None
  }
  let creation_time = match members.get("creation_time") {
    Some(String(s)) => Some(s)
    _ => None
  }
  let size = match members.get("size") {
    Some(Number(n, ..)) => Some(n.to_int())
    _ => None
  }
  Some({ name, creation_time, size, })
}

///|
/// Parse the `result` array of a snapshots response.
pub fn parse_snapshots(json : Json) -> Array[SnapshotInfo]? {
  match json {
    Object(members) =>
      match members.get("result") {
        Some(Array(arr)) => {
          let out : Array[SnapshotInfo] = []
          for item in arr {
            match SnapshotInfo::from_json(item) {
              Some(s) => out.push(s)
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
/// One payload index entry, from the `payload_schema` of a collection info
/// response.
pub struct PayloadIndexInfo {
  data_type : String
  field_schema : Json?
}

///|
/// Parse one payload index entry:
/// `{ "data_type": "keyword", "field_schema": "keyword", "points": 3 }`.
pub fn PayloadIndexInfo::from_json(json : Json) -> PayloadIndexInfo? {
  guard json is Object(members) else { return None }
  let data_type = match members.get("data_type") {
    Some(String(s)) => s
    _ => return None
  }
  let field_schema = members.get("field_schema")
  Some({ data_type, field_schema, })
}

///|
/// Parse the payload indexes of a collection. Qdrant has no dedicated
/// "list indexes" endpoint; the schema is returned as `payload_schema`
/// inside `GET /collections/{name}`. Each key is a field name and each
/// value is an index descriptor like
/// `{ "data_type": "keyword", "points": 3, ... }`.
pub fn parse_payload_indexes(json : Json) -> Array[PayloadIndexInfo]? {
  match json {
    Object(members) =>
      match members.get("result") {
        Some(Object(result)) =>
          match result.get("payload_schema") {
            Some(Object(schema)) => {
              let out : Array[PayloadIndexInfo] = []
              for field in schema.keys() {
                match schema[field] {
                  Object(im) => {
                    let data_type = match im.get("data_type") {
                      Some(String(s)) => s
                      _ => "unknown"
                    }
                    out.push({
                      data_type,
                      field_schema: Some(Json::string(field)),
                    })
                  }
                  _ => ()
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
/// Update settings of an existing collection, via PATCH /collections/{name}.
///
/// All fields are optional; unset fields are omitted from the request body.
/// `vectors` / `named_vectors` update the vector configuration (changing the
/// size of an existing named vector is not supported by Qdrant), while
/// `replication_factor` and `write_consistency_factor` update the shard
/// replication settings.
pub struct CollectionUpdate {
  vectors : VectorParams?
  named_vectors : Map[String, VectorParams]?
  replication_factor : Int?
  write_consistency_factor : Int?
}

///|
pub fn CollectionUpdate::new(
  vectors? : VectorParams? = None,
  named_vectors? : Map[String, VectorParams]? = None,
  replication_factor? : Int? = None,
  write_consistency_factor? : Int? = None,
) -> CollectionUpdate {
  { vectors, named_vectors, replication_factor, write_consistency_factor, }
}

///|
/// Convert to the PATCH request body, omitting unset fields.
pub fn CollectionUpdate::to_json(self : CollectionUpdate) -> Json {
  let members : Map[String, Json] = Map([])
  match self.vectors {
    Some(v) => members["vectors"] = v.to_json()
    None => ()
  }
  match self.named_vectors {
    Some(named) => {
      let vmembers : Map[String, Json] = Map([])
      for name in named.keys() {
        vmembers[name] = named[name].to_json()
      }
      members["vectors"] = Json::object(vmembers)
    }
    None => ()
  }
  let params : Map[String, Json] = Map([])
  match self.replication_factor {
    Some(rf) => params["replication_factor"] = Json::number(rf.to_double())
    None => ()
  }
  match self.write_consistency_factor {
    Some(wcf) =>
      params["write_consistency_factor"] = Json::number(wcf.to_double())
    None => ()
  }
  if !params.is_empty() {
    members["params"] = Json::object(params)
  }
  Json::object(members)
}

///|
/// One facet hit from `POST /collections/{name}/points/facet`: a distinct
/// payload value together with the number of points carrying it.
pub struct FacetHit {
  value : Json
  count : Int
}

///|
/// Parse one facet hit: `{ "value": "alpha", "count": 3 }`.
pub fn FacetHit::from_json(json : Json) -> FacetHit? {
  guard json is Object(members) else { return None }
  let value = match members.get("value") {
    Some(v) => v
    _ => return None
  }
  let count = match members.get("count") {
    Some(Number(n, ..)) => n.to_int()
    _ => return None
  }
  Some({ value, count, })
}

///|
/// Result of a facet query: the value-count hits and whether the counts are
/// exact (false when Qdrant used an approximate estimation).
pub struct FacetResult {
  hits : Array[FacetHit]
  exact : Bool
}

///|
/// Parse the `result` object of a facet response:
/// `{ "hits": [{ "value": ..., "count": n }], "exact": true }`.
pub fn FacetResult::from_json(json : Json) -> FacetResult? {
  guard json is Object(members) else { return None }
  let hits_arr = match members.get("hits") {
    Some(Array(arr)) => arr
    _ => return None
  }
  let hits : Array[FacetHit] = []
  for item in hits_arr {
    match FacetHit::from_json(item) {
      Some(h) => hits.push(h)
      None => return None
    }
  }
  let exact = match members.get("exact") {
    Some(True) => true
    Some(False) => false
    _ => false
  }
  Some({ hits, exact, })
}

///|
/// Parse the `result` of a query response into scored points.
///
/// The query API returns `{ "result": { "points": [...], "next_page_offset": ... } }`
/// (an object), unlike the search API which returns `{ "result": [...] }`.
/// Both shapes are accepted here.
pub fn parse_query_result(json : Json) -> Array[ScoredPoint]? {
  match json {
    Object(members) =>
      match members.get("result") {
        Some(Array(arr)) => parse_scored_array(arr)
        Some(Object(inner)) =>
          match inner.get("points") {
            Some(Array(arr)) => parse_scored_array(arr)
            _ => None
          }
        _ => None
      }
    _ => None
  }
}

///|
/// Parse an array of scored point objects into `ScoredPoint` values.
/// Returns None when any element does not match the expected shape.
pub fn parse_scored_array(arr : Array[Json]) -> Array[ScoredPoint]? {
  let out : Array[ScoredPoint] = []
  for item in arr {
    match ScoredPoint::from_json(item) {
      Some(hit) => out.push(hit)
      None => return None
    }
  }
  Some(out)
}

///|
/// One group returned by the grouped search endpoint: the group id (the
/// payload value points were grouped by) and the top hits within the group.
pub struct ScoredPointGroup {
  id : Json
  hits : Array[ScoredPoint]
}

///|
/// Parse one search group: `{ "hits": [...], "id": "alpha" }`.
pub fn ScoredPointGroup::from_json(json : Json) -> ScoredPointGroup? {
  guard json is Object(members) else { return None }
  let id = match members.get("id") {
    Some(v) => v
    _ => return None
  }
  let hits_arr = match members.get("hits") {
    Some(Array(arr)) => arr
    _ => return None
  }
  let hits : Array[ScoredPoint] = []
  for item in hits_arr {
    match ScoredPoint::from_json(item) {
      Some(h) => hits.push(h)
      None => return None
    }
  }
  Some({ id, hits, })
}

///|
/// Parse the `result.groups` array of a grouped search response.
pub fn parse_search_groups(json : Json) -> Array[ScoredPointGroup]? {
  match json {
    Object(members) =>
      match members.get("result") {
        Some(Object(result)) =>
          match result.get("groups") {
            Some(Array(arr)) => {
              let out : Array[ScoredPointGroup] = []
              for item in arr {
                match ScoredPointGroup::from_json(item) {
                  Some(g) => out.push(g)
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
/// Collection lock state, from GET /collections/{name}/lock.
/// When `write` is true, the collection rejects write operations; the
/// optional `error_message` is returned to clients on rejected writes.
pub struct CollectionLock {
  write : Bool
  error_message : String?
}

///|
/// Parse the lock object: `{ "write": true, "error_message": "..." }`.
pub fn CollectionLock::from_json(json : Json) -> CollectionLock? {
  guard json is Object(members) else { return None }
  let write = match members.get("write") {
    Some(True) => true
    Some(False) => false
    _ => return None
  }
  let error_message = match members.get("error_message") {
    Some(String(s)) => Some(s)
    _ => None
  }
  Some({ write, error_message, })
}

///|
/// Server info from GET /service: the running Qdrant version and build
/// metadata when present.
pub struct ServiceInfo {
  version : String?
  commit : String?
}

///|
/// Parse the service info object.
pub fn ServiceInfo::from_json(json : Json) -> ServiceInfo? {
  guard json is Object(members) else { return None }
  // Qdrant serves instance details at GET / with version/commit at the
  // top level (no "result" wrapper).
  let version = match members.get("version") {
    Some(String(s)) => Some(s)
    _ => None
  }
  let commit = match members.get("commit") {
    Some(String(s)) => Some(s)
    _ => None
  }
  Some({ version, commit, })
}

///|
/// Parse a base-10 integer string into an Int64, tolerating a leading '-'.
/// Used to decode large JSON numbers (peer ids, shard ids) from their
/// original textual representation without precision loss.
pub fn parse_int64(s : String) -> Int64? {
  if s.is_empty() {
    return None
  }
  let mut i = 0
  let mut neg = false
  if s[0] == '-' {
    neg = true
    i = 1
  }
  if i >= s.length() {
    return None
  }
  let mut acc = 0L
  while i < s.length() {
    let c = s[i]
    if c < '0' || c > '9' {
      return None
    }
    acc = acc * 10L + Int64::from_int(c.to_int() - 48)
    i = i + 1
  }
  if neg {
    Some(-acc)
  } else {
    Some(acc)
  }
}

///|
/// Read an integer from a JSON number, using the original textual
/// representation when available so u64 values survive without loss.
pub fn int64_of_json(json : Json) -> Int64? {
  match json {
    Number(n, repr~) =>
      match repr {
        Some(s) => parse_int64(s)
        None => Some(Int64::from_int(n.to_int()))
      }
    _ => None
  }
}

///|
/// Serialize an Int64 as a JSON number. Values within the exact-double range
/// (|v| < 2^53) round-trip losslessly; peer ids from Qdrant are u64 but in
/// practice stay well below that bound.
pub fn int64_to_json(v : Int64) -> Json {
  Json::number(v.to_double())
}

///|
/// Parse an optional bool that may be absent from the wire.
fn optional_bool(json : Json) -> Bool? {
  match json {
    True => Some(true)
    False => Some(false)
    _ => None
  }
}

///|
/// A remote peer of the cluster, as reported by GET /cluster.
pub struct PeerInfo {
  uri : String?
  last_hb_secs_ago : Int64?
  last_resp_secs_ago : Int64?
  last_update_secs_ago : Int64?
}

///|
/// Parse one peer entry: `{ "uri": "...", "last_hb_secs_ago": 0, ... }`.
pub fn PeerInfo::from_json(json : Json) -> PeerInfo? {
  guard json is Object(members) else { return None }
  let uri = match members.get("uri") {
    Some(String(s)) => Some(s)
    _ => None
  }
  let last_hb_secs_ago = match members.get("last_hb_secs_ago") {
    Some(n) => int64_of_json(n)
    _ => None
  }
  let last_resp_secs_ago = match members.get("last_resp_secs_ago") {
    Some(n) => int64_of_json(n)
    _ => None
  }
  let last_update_secs_ago = match members.get("last_update_secs_ago") {
    Some(n) => int64_of_json(n)
    _ => None
  }
  Some({ uri, last_hb_secs_ago, last_resp_secs_ago, last_update_secs_ago, })
}

///|
/// Raft consensus state of the cluster.
pub struct RaftInfo {
  term : Int64?
  commit : Int64?
  pending_operations : Int64?
  leader : Int64?
  role : String?
  is_voter : Bool?
}

///|
/// Parse the `raft_info` object of a cluster response.
pub fn RaftInfo::from_json(json : Json) -> RaftInfo? {
  guard json is Object(members) else { return None }
  let term = match members.get("term") {
    Some(n) => int64_of_json(n)
    _ => None
  }
  let commit = match members.get("commit") {
    Some(n) => int64_of_json(n)
    _ => None
  }
  let pending_operations = match members.get("pending_operations") {
    Some(n) => int64_of_json(n)
    _ => None
  }
  let leader = match members.get("leader") {
    Some(n) => int64_of_json(n)
    _ => None
  }
  let role = match members.get("role") {
    Some(String(s)) => Some(s)
    _ => None
  }
  let is_voter = match members.get("is_voter") {
    Some(b) => optional_bool(b)
    _ => None
  }
  Some({ term, commit, pending_operations, leader, role, is_voter, })
}

///|
/// Overall cluster state, from `GET /cluster`.
pub struct ClusterInfo {
  status : String
  peer_id : Int64
  peers : Map[String, PeerInfo]
  raft_info : RaftInfo?
}

///|
/// Parse the cluster info result object.
pub fn ClusterInfo::from_json(json : Json) -> ClusterInfo? {
  guard json is Object(members) else { return None }
  let status = match members.get("status") {
    Some(String(s)) => s
    _ => return None
  }
  let peer_id = match members.get("peer_id") {
    Some(n) =>
      match int64_of_json(n) {
        Some(v) => v
        None => return None
      }
    _ => return None
  }
  let peers : Map[String, PeerInfo] = Map([])
  match members.get("peers") {
    Some(Object(peer_map)) =>
      for id in peer_map.keys() {
        match PeerInfo::from_json(peer_map[id]) {
          Some(info) => peers[id] = info
          None => return None
        }
      }
    _ => return None
  }
  let raft_info = match members.get("raft_info") {
    Some(raft) => RaftInfo::from_json(raft)
    None => None
  }
  Some({ status, peer_id, peers, raft_info, })
}

///|
/// A shard replica hosted on the local node.
pub struct LocalShardInfo {
  shard_id : Int64
  points_count : Int64
  state : String
}

///|
/// Parse one local shard entry: `{ "shard_id": 0, "points_count": 10, "state": "Active" }`.
pub fn LocalShardInfo::from_json(json : Json) -> LocalShardInfo? {
  guard json is Object(members) else { return None }
  let shard_id = match members.get("shard_id") {
    Some(n) =>
      match int64_of_json(n) {
        Some(v) => v
        None => return None
      }
    _ => return None
  }
  let points_count = match members.get("points_count") {
    Some(n) =>
      match int64_of_json(n) {
        Some(v) => v
        None => return None
      }
    _ => return None
  }
  let state = match members.get("state") {
    Some(String(s)) => s
    _ => return None
  }
  Some({ shard_id, points_count, state, })
}

///|
/// A shard replica hosted on a remote peer.
pub struct RemoteShardInfo {
  shard_id : Int64
  peer_id : Int64
  state : String
}

///|
/// Parse one remote shard entry: `{ "shard_id": 0, "peer_id": 1, "state": "Active" }`.
pub fn RemoteShardInfo::from_json(json : Json) -> RemoteShardInfo? {
  guard json is Object(members) else { return None }
  let shard_id = match members.get("shard_id") {
    Some(n) =>
      match int64_of_json(n) {
        Some(v) => v
        None => return None
      }
    _ => return None
  }
  let peer_id = match members.get("peer_id") {
    Some(n) =>
      match int64_of_json(n) {
        Some(v) => v
        None => return None
      }
    _ => return None
  }
  let state = match members.get("state") {
    Some(String(s)) => s
    _ => return None
  }
  Some({ shard_id, peer_id, state, })
}

///|
/// An in-flight shard transfer between two peers.
pub struct ShardTransferInfo {
  shard_id : Int64
  from : Int64
  to : Int64
  method_name : String?
}

///|
/// Parse one shard transfer entry.
pub fn ShardTransferInfo::from_json(json : Json) -> ShardTransferInfo? {
  guard json is Object(members) else { return None }
  let shard_id = match members.get("shard_id") {
    Some(n) =>
      match int64_of_json(n) {
        Some(v) => v
        None => return None
      }
    _ => return None
  }
  let from = match members.get("from") {
    Some(n) =>
      match int64_of_json(n) {
        Some(v) => v
        None => return None
      }
    _ => return None
  }
  let to = match members.get("to") {
    Some(n) =>
      match int64_of_json(n) {
        Some(v) => v
        None => return None
      }
    _ => return None
  }
  let method_name = match members.get("method") {
    Some(String(s)) => Some(s)
    _ => None
  }
  Some({ shard_id, from, to, method_name, })
}

///|
/// Per-collection cluster layout, from `GET /collections/{name}/cluster`.
pub struct CollectionClusterInfo {
  peer_id : Int64
  shard_count : Int64
  local_shards : Array[LocalShardInfo]
  remote_shards : Array[RemoteShardInfo]
  shard_transfers : Array[ShardTransferInfo]
}

///|
/// Parse the collection cluster info result object.
pub fn CollectionClusterInfo::from_json(json : Json) -> CollectionClusterInfo? {
  guard json is Object(members) else { return None }
  let peer_id = match members.get("peer_id") {
    Some(n) =>
      match int64_of_json(n) {
        Some(v) => v
        None => return None
      }
    _ => return None
  }
  let shard_count = match members.get("shard_count") {
    Some(n) =>
      match int64_of_json(n) {
        Some(v) => v
        None => return None
      }
    _ => return None
  }
  let parse_local : Array[LocalShardInfo] = []
  match members.get("local_shards") {
    Some(Array(arr)) =>
      for item in arr {
        match LocalShardInfo::from_json(item) {
          Some(info) => parse_local.push(info)
          None => return None
        }
      }
    _ => return None
  }
  let parse_remote : Array[RemoteShardInfo] = []
  match members.get("remote_shards") {
    Some(Array(arr)) =>
      for item in arr {
        match RemoteShardInfo::from_json(item) {
          Some(info) => parse_remote.push(info)
          None => return None
        }
      }
    _ => return None
  }
  let parse_transfers : Array[ShardTransferInfo] = []
  match members.get("shard_transfers") {
    Some(Array(arr)) =>
      for item in arr {
        match ShardTransferInfo::from_json(item) {
          Some(info) => parse_transfers.push(info)
          None => return None
        }
      }
    _ => return None
  }
  Some({
    peer_id,
    shard_count,
    local_shards: parse_local,
    remote_shards: parse_remote,
    shard_transfers: parse_transfers,
  })
}
