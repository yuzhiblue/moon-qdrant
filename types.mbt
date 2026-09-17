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
  let vec : Array[Json] = []
  for x in self.vector {
    vec.push(Json::number(x))
  }
  {
    "id": Json::number(self.id.to_double()),
    "vector": Json::array(vec),
    "payload": self.payload,
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
