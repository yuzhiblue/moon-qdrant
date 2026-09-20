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
  timeout_ms? : Int = 10_000,
) -> QdrantClient {
  let base = if base_url.has_suffix("/") {
    base_url[:base_url.length() - 1].to_owned()
  } else {
    base_url
  }
  let http = @mio.RequestClient::builder().timeout(timeout_ms).build()
  { base_url: base, api_key, http, }
}

///|
/// Join a path fragment onto the base URL, keeping a single slash between them.
pub fn join_url(base : String, path : String) -> String {
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
    Patch => self.http.patch(url)
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
      "Qdrant API error " +
      code.to_string() +
      " on " +
      path +
      ": " +
      json.stringify(),
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
/// Pass `wait=false` to return immediately; the operation may still be
/// propagating on the server.
pub async fn QdrantClient::upsert_points(
  self : QdrantClient,
  name : String,
  points : Array[PointStruct],
  wait? : Bool = true,
) -> Unit {
  let path = "/collections/" + name + "/points?wait=" + wait.to_string()
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
  wait? : Bool = true,
) -> Unit {
  let path = "/collections/" + name + "/points/batch?wait=" + wait.to_string()
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
  with_payload? : Bool = true,
  with_vector? : Bool = true,
) -> PointStruct? {
  let path = "/collections/" +
    name +
    "/points/" +
    id.to_string() +
    "?with_payload=" +
    with_payload.to_string() +
    "&with_vector=" +
    with_vector.to_string()
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
/// Pass `wait=false` to return immediately.
pub async fn QdrantClient::delete_points(
  self : QdrantClient,
  name : String,
  ids : Array[Int],
  wait? : Bool = true,
) -> Unit {
  let path = "/collections/" + name + "/points/delete?wait=" + wait.to_string()
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
///
/// Advanced options: `score_threshold` keeps only hits above the score,
/// `offset` paginates search results, `using_vector` selects which named
/// vector to query against, and `search_params` carries search-time tuning
/// (`hnsw_ef`, `exact`).
pub async fn QdrantClient::search_points(
  self : QdrantClient,
  name : String,
  vector : Array[Double],
  limit : Int,
  filter? : Json? = None,
  with_payload? : Bool = true,
  with_vector? : Bool = false,
  score_threshold? : Double? = None,
  offset? : Int? = None,
  using_vector? : String? = None,
  search_params? : SearchParams? = None,
) -> Array[ScoredPoint] {
  self.search_points_raw(
    name,
    vector_to_json(vector),
    limit,
    filter,
    with_payload,
    with_vector,
    score_threshold,
    offset,
    using_vector,
    search_params,
  )
}

///|
/// Search with a named vector as input: the query vector is matched against
/// the named vector with the given name (Qdrant supports several vectors per
/// point). `using` is implied by the name carried in `named_vector`.
pub async fn QdrantClient::search_points_named(
  self : QdrantClient,
  name : String,
  named_vector : NamedVector,
  limit : Int,
  filter? : Json? = None,
  with_payload? : Bool = true,
  with_vector? : Bool = false,
  score_threshold? : Double? = None,
  offset? : Int? = None,
  search_params? : SearchParams? = None,
) -> Array[ScoredPoint] {
  self.search_points_raw(
    name,
    named_vector.to_json(),
    limit,
    filter,
    with_payload,
    with_vector,
    score_threshold,
    offset,
    None,
    search_params,
  )
}

///|
/// Core search implementation shared by the dense and named variants.
/// `vector` is the already-serialized vector field of the request body.
async fn QdrantClient::search_points_raw(
  self : QdrantClient,
  name : String,
  vector : Json,
  limit : Int,
  filter : Json?,
  with_payload : Bool,
  with_vector : Bool,
  score_threshold : Double?,
  offset : Int?,
  using_vector : String?,
  search_params : SearchParams?,
) -> Array[ScoredPoint] {
  let path = "/collections/" +
    name +
    "/points/search?limit=" +
    limit.to_string()
  let base : Map[String, Json] = Map([])
  base["vector"] = vector
  base["with_payload"] = Json::boolean(with_payload)
  base["with_vector"] = Json::boolean(with_vector)
  match filter {
    Some(f) => base["filter"] = f
    None => ()
  }
  match score_threshold {
    Some(t) => base["score_threshold"] = Json::number(t)
    None => ()
  }
  match offset {
    Some(o) => base["offset"] = Json::number(o.to_double())
    None => ()
  }
  match using_vector {
    Some(u) => base["using"] = Json::string(u)
    None => ()
  }
  match search_params {
    Some(p) => base["params"] = p.to_json()
    None => ()
  }
  let body = Json::object(base)
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
  with_payload? : Bool = true,
  with_vector? : Bool = false,
  score_threshold? : Double? = None,
  offset? : Int? = None,
  using_vector? : String? = None,
  search_params? : SearchParams? = None,
) -> Array[ScoredPoint] {
  self.search_points(
    name,
    vector,
    limit,
    filter=Some(filter.to_json()),
    with_payload~,
    with_vector~,
    score_threshold~,
    offset~,
    using_vector~,
    search_params~,
  )
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
  with_payload? : Bool = true,
  with_vector? : Bool = true,
) -> ScrollResult {
  let path = "/collections/" + name + "/points/scroll"
  let body = scroll_request_body(
    limit, filter, offset, with_payload, with_vector,
  )
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
  let body = count_request_body(filter, exact)
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
  with_payload? : Bool = true,
  with_vector? : Bool = true,
) -> Array[PointStruct] {
  let path = "/collections/" + name + "/points"
  let id_json : Array[Json] = []
  for id in ids {
    id_json.push(Json::number(id.to_double()))
  }
  let body : Json = {
    "ids": Json::array(id_json),
    "with_payload": Json::boolean(with_payload),
    "with_vector": Json::boolean(with_vector),
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
  wait? : Bool = true,
) -> Unit {
  let path = "/collections/" + name + "/points/delete?wait=" + wait.to_string()
  let body : Json = { "filter": filter.to_json() }
  let json = self.request_json(Post, path, Some(body))
  ignore(json)
}

///|
/// Run several searches in one round trip via
/// `POST /collections/{name}/points/search/batch`.
///
/// Each element is a search request JSON object, for example
/// `{ "vector": [...], "limit": 5, "with_payload": true }`; the returned
/// array has one entry (itself an array of hits) per request.
pub async fn QdrantClient::search_points_batch(
  self : QdrantClient,
  name : String,
  searches : Array[Json],
) -> Array[Array[ScoredPoint]] {
  let path = "/collections/" + name + "/points/search/batch"
  let body : Json = { "searches": Json::array(searches) }
  let json = self.request_json(Post, path, Some(body))
  let result : Array[Array[ScoredPoint]]? = match json {
    Object(members) =>
      match members.get("result") {
        Some(Array(groups)) => {
          let out : Array[Array[ScoredPoint]] = []
          for group in groups {
            match group {
              Array(hits_json) => {
                let hits : Array[ScoredPoint] = []
                for item in hits_json {
                  match ScoredPoint::from_json(item) {
                    Some(hit) => hits.push(hit)
                    None =>
                      raise Failure(
                        "unexpected batch search hit: " + json.stringify(),
                      )
                  }
                }
                out.push(hits)
              }
              _ =>
                raise Failure(
                  "unexpected batch search response: " + json.stringify(),
                )
            }
          }
          Some(out)
        }
        _ => None
      }
    _ => None
  }
  match result {
    Some(out) => out
    None =>
      raise Failure("unexpected batch search response: " + json.stringify())
  }
}

///|
/// Set (merge) a payload on the given points via
/// `PUT /collections/{name}/points/payload`.
///
/// Pass either `ids` or `filter` to select the target points. The payload
/// fields are merged into each point's existing payload.
pub async fn QdrantClient::set_payload(
  self : QdrantClient,
  name : String,
  payload : Json,
  ids? : Array[Int]? = None,
  filter? : Filter? = None,
  wait? : Bool = true,
) -> Unit {
  let path = "/collections/" + name + "/points/payload?wait=" + wait.to_string()
  let body = payload_operation_body(payload, ids, filter)
  let json = self.request_json(Put, path, Some(body))
  ignore(json)
}

///|
/// Overwrite the payload of the given points via
/// `POST /collections/{name}/points/payload`.
///
/// Unlike `set_payload`, the whole payload is replaced by the given object.
pub async fn QdrantClient::overwrite_payload(
  self : QdrantClient,
  name : String,
  payload : Json,
  ids? : Array[Int]? = None,
  filter? : Filter? = None,
  wait? : Bool = true,
) -> Unit {
  let path = "/collections/" + name + "/points/payload?wait=" + wait.to_string()
  let body = payload_operation_body(payload, ids, filter)
  let json = self.request_json(Post, path, Some(body))
  ignore(json)
}

///|
/// Delete the whole payload of the selected points via
/// `POST /collections/{name}/points/payload/delete`.
///
/// Pass either `ids` or `filter` to select the target points. To remove only
/// some keys, use `delete_payload_by_keys`.
pub async fn QdrantClient::delete_payload(
  self : QdrantClient,
  name : String,
  ids? : Array[Int]? = None,
  filter? : Filter? = None,
  wait? : Bool = true,
) -> Unit {
  let path = "/collections/" +
    name +
    "/points/payload/delete?wait=" +
    wait.to_string()
  let body = payload_operation_body(Json::object({}), ids, filter)
  let json = self.request_json(Post, path, Some(body))
  ignore(json)
}

///|
/// Delete only the listed payload keys from the selected points via
/// `POST /collections/{name}/points/payload/delete`.
///
/// Pass either `ids` or `filter` to select the target points.
pub async fn QdrantClient::delete_payload_by_keys(
  self : QdrantClient,
  name : String,
  keys : Array[String],
  ids? : Array[Int]? = None,
  filter? : Filter? = None,
  wait? : Bool = true,
) -> Unit {
  let path = "/collections/" +
    name +
    "/points/payload/delete?wait=" +
    wait.to_string()
  let key_json : Array[Json] = []
  for key in keys {
    key_json.push(Json::string(key))
  }
  let body = payload_operation_body(Json::object({}), ids, filter)
  let members = match body {
    Object(m) => m
    _ => Map([])
  }
  members["payload"] = Json::array(key_json)
  let json = self.request_json(Post, path, Some(Json::object(members)))
  ignore(json)
}

///|
/// Build the shared body for payload write operations: `{ "payload": ... }`
/// plus either `"points": [ids]` or `"filter": ...`.
fn payload_operation_body(
  payload : Json,
  ids : Array[Int]?,
  filter : Filter?,
) -> Json {
  let members : Map[String, Json] = Map([])
  members["payload"] = payload
  match ids {
    Some(ids_arr) => {
      let id_json : Array[Json] = []
      for id in ids_arr {
        id_json.push(Json::number(id.to_double()))
      }
      members["points"] = Json::array(id_json)
    }
    None => ()
  }
  match filter {
    Some(f) => members["filter"] = f.to_json()
    None => ()
  }
  Json::object(members)
}

///|
/// Update collection settings via `PATCH /collections/{name}`.
///
/// See `CollectionUpdate` for which settings can be changed.
pub async fn QdrantClient::update_collection(
  self : QdrantClient,
  name : String,
  update : CollectionUpdate,
) -> Unit {
  let path = "/collections/" + name
  let json = self.request_json(Patch, path, Some(update.to_json()))
  ignore(json)
}

///|
/// Create a payload index on a field via
/// `PUT /collections/{name}/indexes/{field}`.
///
/// `schema` is the field schema, for example `"keyword"`, `"integer"`,
/// `"float"`, `"geo"`, `"bool"`, `"text"` or `"uuid"`. Creating an index
/// speeds up filtered access to that payload field.
pub async fn QdrantClient::create_payload_index(
  self : QdrantClient,
  name : String,
  field : String,
  schema : String,
  wait? : Bool = true,
) -> Unit {
  let path = "/collections/" +
    name +
    "/indexes/" +
    field +
    "?wait=" +
    wait.to_string()
  let body : Json = { "field_schema": Json::string(schema) }
  let json = self.request_json(Put, path, Some(body))
  ignore(json)
}

///|
/// Delete a payload index via `DELETE /collections/{name}/indexes/{field}`.
pub async fn QdrantClient::delete_payload_index(
  self : QdrantClient,
  name : String,
  field : String,
  wait? : Bool = true,
) -> Unit {
  let path = "/collections/" +
    name +
    "/indexes/" +
    field +
    "?wait=" +
    wait.to_string()
  let json = self.request_json(Delete, path, None)
  ignore(json)
}

///|
/// List the payload indexes of a collection via
/// `GET /collections/{name}/indexes`.
pub async fn QdrantClient::list_payload_indexes(
  self : QdrantClient,
  name : String,
) -> Array[PayloadIndexInfo] {
  let path = "/collections/" + name + "/indexes"
  let json = self.request_json(Get, path, None)
  match parse_payload_indexes(json) {
    Some(indexes) => indexes
    None =>
      raise Failure("unexpected payload indexes response: " + json.stringify())
  }
}

///|
/// List the snapshots of a collection via
/// `GET /collections/{name}/snapshots`.
pub async fn QdrantClient::list_snapshots(
  self : QdrantClient,
  name : String,
) -> Array[SnapshotInfo] {
  let path = "/collections/" + name + "/snapshots"
  let json = self.request_json(Get, path, None)
  match parse_snapshots(json) {
    Some(snapshots) => snapshots
    None => raise Failure("unexpected snapshots response: " + json.stringify())
  }
}

///|
/// Create a snapshot of a collection via `POST /collections/{name}/snapshots`.
/// Snapshots can be downloaded from the storage and used to restore or
/// migrate a collection.
pub async fn QdrantClient::create_snapshot(
  self : QdrantClient,
  name : String,
  wait? : Bool = true,
) -> SnapshotInfo {
  let path = "/collections/" + name + "/snapshots?wait=" + wait.to_string()
  let json = self.request_json(Post, path, None)
  match json {
    Object(members) =>
      match members.get("result") {
        Some(result) =>
          match SnapshotInfo::from_json(result) {
            Some(info) => info
            None =>
              raise Failure("unexpected snapshot response: " + json.stringify())
          }
        None =>
          raise Failure("unexpected snapshot response: " + json.stringify())
      }
    _ => raise Failure("unexpected snapshot response: " + json.stringify())
  }
}

///|
/// Delete a snapshot via `DELETE /collections/{name}/snapshots/{snapshot}`.
pub async fn QdrantClient::delete_snapshot(
  self : QdrantClient,
  name : String,
  snapshot : String,
  wait? : Bool = true,
) -> Unit {
  let path = "/collections/" +
    name +
    "/snapshots/" +
    snapshot +
    "?wait=" +
    wait.to_string()
  let json = self.request_json(Delete, path, None)
  ignore(json)
}

///|
/// Run a query against the Qdrant query API via
/// `POST /collections/{name}/points/query`.
///
/// `query` is the raw query JSON, for example
/// `{ "nearest": [0.1, 0.2, 0.3, 0.4] }` or
/// `{ "recommend": { "positive": [[...]], "negative": [[...]] } }`.
/// Prefer the `query_nearest` / `query_recommend` helpers for common cases.
pub async fn QdrantClient::query_points(
  self : QdrantClient,
  name : String,
  query : Json,
  limit : Int,
  filter? : Filter? = None,
  using_vector? : String? = None,
  score_threshold? : Double? = None,
  with_payload? : Bool = true,
  with_vector? : Bool = false,
) -> Array[ScoredPoint] {
  let path = "/collections/" + name + "/points/query"
  let members : Map[String, Json] = Map([])
  members["query"] = query
  members["limit"] = Json::number(limit.to_double())
  members["with_payload"] = Json::boolean(with_payload)
  members["with_vector"] = Json::boolean(with_vector)
  match filter {
    Some(f) => members["filter"] = f.to_json()
    None => ()
  }
  match using_vector {
    Some(u) => members["using"] = Json::string(u)
    None => ()
  }
  match score_threshold {
    Some(t) => members["score_threshold"] = Json::number(t)
    None => ()
  }
  let body = Json::object(members)
  let json = self.request_json(Post, path, Some(body))
  match parse_query_result(json) {
    Some(hits) => hits
    None => raise Failure("unexpected query response: " + json.stringify())
  }
}

///|
/// Nearest-neighbor query via the query API: find points closest to `vector`.
/// Equivalent to `search_points` but routed through `/points/query`.
pub async fn QdrantClient::query_nearest(
  self : QdrantClient,
  name : String,
  vector : Array[Double],
  limit : Int,
  filter? : Filter? = None,
  using_vector? : String? = None,
  score_threshold? : Double? = None,
  with_payload? : Bool = true,
  with_vector? : Bool = false,
) -> Array[ScoredPoint] {
  self.query_points(
    name,
    { "nearest": vector_to_json(vector) },
    limit,
    filter~,
    using_vector~,
    score_threshold~,
    with_payload~,
    with_vector~,
  )
}

///|
/// Recommendation query via the query API: find points similar to the
/// `positive` inputs and dissimilar to the `negative` ones.
///
/// Each element of `positive` / `negative` is either a dense vector
/// (`Json::array([...])`) or a point id (`Json::number(id)`).
pub async fn QdrantClient::query_recommend(
  self : QdrantClient,
  name : String,
  positive : Array[Json],
  negative? : Array[Json]? = None,
  limit : Int,
  filter? : Filter? = None,
  using_vector? : String? = None,
  score_threshold? : Double? = None,
  with_payload? : Bool = true,
  with_vector? : Bool = false,
) -> Array[ScoredPoint] {
  let rec : Map[String, Json] = Map([])
  rec["positive"] = Json::array(positive)
  match negative {
    Some(neg) => rec["negative"] = Json::array(neg)
    None => ()
  }
  self.query_points(
    name,
    { "recommend": Json::object(rec) },
    limit,
    filter~,
    using_vector~,
    score_threshold~,
    with_payload~,
    with_vector~,
  )
}

///|
/// Count the distinct values of a payload field via
/// `POST /collections/{name}/points/facet`.
///
/// `key` is the payload field to facet on; `limit` bounds how many distinct
/// values are returned (by descending count). Pass `exact=true` for exact
/// counts instead of the faster approximate estimation.
pub async fn QdrantClient::facet_points(
  self : QdrantClient,
  name : String,
  key : String,
  limit : Int,
  filter? : Filter? = None,
  exact? : Bool = false,
) -> FacetResult {
  let path = "/collections/" + name + "/points/facet"
  let members : Map[String, Json] = Map([])
  members["key"] = Json::string(key)
  members["limit"] = Json::number(limit.to_double())
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
          match FacetResult::from_json(result) {
            Some(fr) => fr
            None =>
              raise Failure("unexpected facet response: " + json.stringify())
          }
        None => raise Failure("unexpected facet response: " + json.stringify())
      }
    _ => raise Failure("unexpected facet response: " + json.stringify())
  }
}
