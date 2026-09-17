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
/// Send a request and return the parsed JSON body.
/// Raises on transport errors or when the server answers with a non-2xx code.
async fn QdrantClient::request_json(
  self : QdrantClient,
  verb : @mio.RequestMethod,
  path : String,
  body : Json?,
) -> Json {
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
  if res.response.code < 200 || res.response.code >= 300 {
    raise Failure(
      "Qdrant API error " + res.response.code.to_string() + ": " + res.text(),
    )
  }
  res.json()
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
