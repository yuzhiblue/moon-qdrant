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
