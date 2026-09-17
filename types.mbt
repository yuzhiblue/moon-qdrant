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
