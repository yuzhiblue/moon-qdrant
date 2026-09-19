///|
/// QdrantClient: a minimal, dependency-light MoonBit client for the
/// Qdrant vector database REST API.
///
/// Transport is provided by `@mio`; JSON is handled by `@json` from core.
/// This file intentionally keeps the API surface small and explicit so each
/// method maps 1:1 to a documented Qdrant REST endpoint.

///|
/// Configuration for a QdrantClient.
pub struct QdrantClient {
  base_url : String
  api_key : String?
  http : @mio.RequestClient
}

///|
/// Create a client for the given base URL.
///
/// Example: `QdrantClient::new("http://localhost:6333")`
///
/// `api_key` is optional and, when set, is sent as the `api-key` header
/// expected by Qdrant's API-key authentication.
pub fn QdrantClient::new(
  base_url : String,
  api_key? : String? = None,
) -> QdrantClient {
  let base = if base_url.has_suffix("/") {
    base_url[:base_url.length() - 1].to_owned()
  } else {
    base_url
  }
  let http = @mio.RequestClient::builder().timeout(10_000).build()
  { base_url: base, api_key, http, }
}

///|
/// Join a path fragment onto the base URL, keeping a single slash between them.
fn join_url(base : String, path : String) -> String {
  if path.has_prefix("/") {
    base + path
  } else {
    base + "/" + path
  }
}

///|
/// Send a request and return the HTTP status code together with the parsed
/// JSON body.
async fn QdrantClient::send(
  self : QdrantClient,
  verb : @mio.RequestMethod,
  path : String,
  body : Json?,
) -> (Int, Json) {
  let url = join_url(self.base_url, path)
  let builder = match verb {
    Get => self.http.get(url)
    Post => self.http.post(url)
    Put => self.http.put(url)
    Delete => self.http.delete(url)
    _ => raise Failure("unsupported method for Qdrant API")
  }
  let builder = match self.api_key {
    Some(key) => builder.header("api-key", key)
    None => builder
  }
  let builder = match body {
    Some(json) => builder.json(json)
    None => builder
  }
  let res = builder.send()
  (res.response.code, res.json())
}

///|
/// Send a request and return the parsed JSON body.
/// Raises on transport errors or when the server answers with a non-2xx code.
async fn QdrantClient::request_json(
  self : QdrantClient,
  verb : @mio.RequestMethod,
  path : String,
  body : Json?,
) -> Json {
  let (code, json) = self.send(verb, path, body)
  if code < 200 || code >= 300 {
    raise Failure(
      "Qdrant API error " + code.to_string() + ": " + json.stringify(),
    )
  }
  json
}

///|
/// Check the server health via `GET /healthz`.
/// Returns true when the server reports status "ok".
pub async fn QdrantClient::health(self : QdrantClient) -> Bool {
  let json = self.request_json(Get, "/healthz", None)
  match json {
    Object(members) =>
      match members.get("status") {
        Some(String(s)) => s == "ok"
        _ => false
      }
    _ => false
  }
}

///|
/// List all collection names via `GET /collections`.
pub async fn QdrantClient::list_collections(
  self : QdrantClient,
) -> Array[String] {
  let json = self.request_json(Get, "/collections", None)
  match CollectionList::from_json(json) {
    Some(list) => list.names
    None =>
      raise Failure("unexpected /collections response: " + json.stringify())
  }
}

///|
/// Create a collection via `PUT /collections/{name}`.
pub async fn QdrantClient::create_collection(
  self : QdrantClient,
  name : String,
  config : CollectionConfig,
) -> Unit {
  let path = "/collections/" + name
  let json = self.request_json(Put, path, Some(config.to_json()))
  // Qdrant answers with {"result": true} on success; treat any 2xx as success.
  ignore(json)
}

///|
/// Get detailed information about a collection via `GET /collections/{name}`.
/// Raises when the collection does not exist or the server reports an error.
pub async fn QdrantClient::collection_info(
  self : QdrantClient,
  name : String,
) -> CollectionInfo {
  let path = "/collections/" + name
  let json = self.request_json(Get, path, None)
  match CollectionInfo::from_json(json) {
    Some(info) => info
    None =>
      raise Failure("unexpected collection info response: " + json.stringify())
  }
}

///|
/// Delete a collection via `DELETE /collections/{name}`.
/// Raises when the collection does not exist or the server reports an error.
pub async fn QdrantClient::delete_collection(
  self : QdrantClient,
  name : String,
) -> Unit {
  let path = "/collections/" + name
  let json = self.request_json(Delete, path, None)
  ignore(json)
}

///|
/// Check whether a collection exists via `GET /collections/{name}`.
/// Returns false when the server answers 404; raises on other errors.
pub async fn QdrantClient::collection_exists(
  self : QdrantClient,
  name : String,
) -> Bool {
  let path = "/collections/" + name
  let (code, _) = self.send(Get, path, None)
  if code >= 200 && code < 300 {
    true
  } else if code == 404 {
    false
  } else {
    raise Failure("Qdrant API error " + code.to_string())
  }
}

///|
/// Upsert points into a collection via `PUT /collections/{name}/points`.
/// The call waits for the operation to be applied before returning.
pub async fn QdrantClient::upsert_points(
  self : QdrantClient,
  name : String,
  points : Array[PointStruct],
) -> Unit {
  let path = "/collections/" + name + "/points?wait=true"
  let point_json : Array[Json] = []
  for p in points {
    point_json.push(p.to_json())
  }
  let body : Json = { "points": Json::array(point_json) }
  let json = self.request_json(Put, path, Some(body))
  ignore(json)
}

///|
/// Upsert points through the batch endpoint via
/// `PUT /collections/{name}/points/batch`.
/// The batch format packs ids, vectors and payloads into parallel arrays,
/// which Qdrant applies as a single request.
pub async fn QdrantClient::upsert_points_batch(
  self : QdrantClient,
  name : String,
  points : Array[PointStruct],
) -> Unit {
  let path = "/collections/" + name + "/points/batch?wait=true"
  let ids : Array[Json] = []
  let vectors : Array[Json] = []
  let payloads : Array[Json] = []
  for p in points {
    ids.push(Json::number(p.id.to_double()))
    vectors.push(vector_to_json(p.vector))
    payloads.push(p.payload)
  }
  let body : Json = {
    "batch": {
      "ids": Json::array(ids),
      "vectors": Json::array(vectors),
      "payloads": Json::array(payloads),
    },
  }
  let json = self.request_json(Put, path, Some(body))
  ignore(json)
}

///|
/// Fetch a single point via `GET /collections/{name}/points/{id}`.
/// Returns None when the point does not exist (404).
pub async fn QdrantClient::get_point(
  self : QdrantClient,
  name : String,
  id : Int,
) -> PointStruct? {
  let path = "/collections/" +
    name +
    "/points/" +
    id.to_string() +
    "?with_payload=true&with_vector=true"
  let (code, json) = self.send(Get, path, None)
  if code >= 200 && code < 300 {
    match json {
      Object(members) =>
        match members.get("result") {
          Some(result) => PointStruct::from_json(result)
          None => None
        }
      _ => None
    }
  } else if code == 404 {
    None
  } else {
    raise Failure(
      "Qdrant API error " + code.to_string() + ": " + json.stringify(),
    )
  }
}

///|
/// Delete points by id via `POST /collections/{name}/points/delete`.
/// The call waits for the operation to be applied before returning.
pub async fn QdrantClient::delete_points(
  self : QdrantClient,
  name : String,
  ids : Array[Int],
) -> Unit {
  let path = "/collections/" + name + "/points/delete?wait=true"
  let id_json : Array[Json] = []
  for id in ids {
    id_json.push(Json::number(id.to_double()))
  }
  let body : Json = { "points": Json::array(id_json) }
  let json = self.request_json(Post, path, Some(body))
  ignore(json)
}

///|
/// Search the most similar points via `POST /collections/{name}/points/search`.
///
/// `limit` bounds how many hits are returned. `filter` is an optional
/// Qdrant filter JSON object, for example
/// `{ "must": [{ "key": "tag", "match": { "value": "alpha" } }] }`.
pub async fn QdrantClient::search_points(
  self : QdrantClient,
  name : String,
  vector : Array[Double],
  limit : Int,
  filter? : Json? = None,
) -> Array[ScoredPoint] {
  let path = "/collections/" +
    name +
    "/points/search?limit=" +
    limit.to_string()
  let body : Json = match filter {
    Some(f) =>
      {
        "vector": vector_to_json(vector),
        "with_payload": Json::boolean(true),
        "filter": f,
      }
    None =>
      { "vector": vector_to_json(vector), "with_payload": Json::boolean(true) }
  }
  let json = self.request_json(Post, path, Some(body))
  match parse_search_result(json) {
    Some(hits) => hits
    None => raise Failure("unexpected search response: " + json.stringify())
  }
}

///|
/// Search with a type-safe `Filter` built from `Condition` helpers.
/// This is the preferred way to build payload filters; the raw-`Json`
/// `search_points` variant remains for advanced cases.
pub async fn QdrantClient::search_points_with_filter(
  self : QdrantClient,
  name : String,
  vector : Array[Double],
  limit : Int,
  filter : Filter,
) -> Array[ScoredPoint] {
  self.search_points(name, vector, limit, filter=Some(filter.to_json()))
}

///|
/// Scroll through all points of a collection via
/// `POST /collections/{name}/points/scroll`.
///
/// Returns one page of points together with `next_page_offset`, which is
/// Some(offset) when more pages remain and None on the last page. Pass it
/// back as `offset` to fetch the following page.
pub async fn QdrantClient::scroll_points(
  self : QdrantClient,
  name : String,
  limit : Int,
  filter? : Filter? = None,
  offset? : Int? = None,
) -> ScrollResult {
  let path = "/collections/" + name + "/points/scroll"
  let members : Map[String, Json] = Map([])
  members["limit"] = Json::number(limit.to_double())
  members["with_payload"] = Json::boolean(true)
  members["with_vector"] = Json::boolean(true)
  match filter {
    Some(f) => members["filter"] = f.to_json()
    None => ()
  }
  match offset {
    Some(o) => members["offset"] = Json::number(o.to_double())
    None => ()
  }
  let body = Json::object(members)
  let json = self.request_json(Post, path, Some(body))
  match json {
    Object(o) =>
      match o.get("result") {
        Some(result) =>
          match ScrollResult::from_json(result) {
            Some(page) => page
            None =>
              raise Failure("unexpected scroll response: " + json.stringify())
          }
        None => raise Failure("unexpected scroll response: " + json.stringify())
      }
    _ => raise Failure("unexpected scroll response: " + json.stringify())
  }
}

///|
/// Count points in a collection via
/// `POST /collections/{name}/points/count`.
///
/// When `exact` is false (default) Qdrant answers with an estimate from
/// the index; pass `exact=true` for an exact count, which is slower on
/// large collections. An optional filter narrows the counted subset.
pub async fn QdrantClient::count_points(
  self : QdrantClient,
  name : String,
  filter? : Filter? = None,
  exact? : Bool = false,
) -> Int {
  let path = "/collections/" + name + "/points/count"
  let members : Map[String, Json] = Map([])
  members["exact"] = Json::boolean(exact)
  match filter {
    Some(f) => members["filter"] = f.to_json()
    None => ()
  }
  let body = Json::object(members)
  let json = self.request_json(Post, path, Some(body))
  match json {
    Object(o) =>
      match o.get("result") {
        Some(result) =>
          match parse_count_result(result) {
            Some(n) => n
            None =>
              raise Failure("unexpected count response: " + json.stringify())
          }
        None => raise Failure("unexpected count response: " + json.stringify())
      }
    _ => raise Failure("unexpected count response: " + json.stringify())
  }
}

///|
/// Fetch several points at once by id via
/// `POST /collections/{name}/points`.
///
/// Points that do not exist are simply omitted from the returned list;
/// check the length against the requested ids to detect missing ones.
pub async fn QdrantClient::retrieve_points(
  self : QdrantClient,
  name : String,
  ids : Array[Int],
) -> Array[PointStruct] {
  let path = "/collections/" + name + "/points"
  let id_json : Array[Json] = []
  for id in ids {
    id_json.push(Json::number(id.to_double()))
  }
  let body : Json = {
    "ids": Json::array(id_json),
    "with_payload": Json::boolean(true),
    "with_vector": Json::boolean(true),
  }
  let json = self.request_json(Post, path, Some(body))
  match parse_retrieve_result(json) {
    Some(points) => points
    None => raise Failure("unexpected retrieve response: " + json.stringify())
  }
}

///|
/// Apply alias change actions via `POST /collections/aliases`.
async fn QdrantClient::apply_alias_actions(
  self : QdrantClient,
  actions : Array[Json],
) -> Unit {
  let body : Json = { "actions": Json::array(actions) }
  let json = self.request_json(Post, "/collections/aliases", Some(body))
  ignore(json)
}

///|
/// Create an alias for a collection: `POST /collections/aliases` with a
/// `create_alias` action.
pub async fn QdrantClient::create_alias(
  self : QdrantClient,
  alias_name : String,
  collection : String,
) -> Unit {
  let action : Json = {
    "action": Json::string("create_alias"),
    "create_alias": {
      "collection_name": Json::string(collection),
      "alias_name": Json::string(alias_name),
    },
  }
  self.apply_alias_actions([action])
}

///|
/// Delete an alias: `POST /collections/aliases` with a `delete_alias` action.
pub async fn QdrantClient::delete_alias(
  self : QdrantClient,
  alias_name : String,
) -> Unit {
  let action : Json = {
    "action": Json::string("delete_alias"),
    "delete_alias": { "alias_name": Json::string(alias_name) },
  }
  self.apply_alias_actions([action])
}

///|
/// List all collection aliases via `GET /collections/aliases`.
pub async fn QdrantClient::list_aliases(
  self : QdrantClient,
) -> Array[AliasInfo] {
  let json = self.request_json(Get, "/collections/aliases", None)
  match parse_aliases(json) {
    Some(aliases) => aliases
    None => raise Failure("unexpected aliases response: " + json.stringify())
  }
}

///|
/// Delete points selected by a filter via
/// `POST /collections/{name}/points/delete`.
///
/// This is the bulk-delete variant: every point matching `filter` is
/// removed in one operation, without listing ids first.
pub async fn QdrantClient::delete_points_by_filter(
  self : QdrantClient,
  name : String,
  filter : Filter,
) -> Unit {
  let path = "/collections/" + name + "/points/delete?wait=true"
  let body : Json = { "filter": filter.to_json() }
  let json = self.request_json(Post, path, Some(body))
  ignore(json)
}
