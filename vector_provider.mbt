///|
/// A common interface implemented by vector-service clients.
///
/// `QdrantClient` implements this trait. The trait exists so that higher-level
/// code (RAG pipelines, embedding indexes) can be written against one shape and
/// later switch to another vector service without changing call sites.
pub trait VectorProvider {
  async fn create_collection(
    self : Self,
    name : String,
    config : CollectionConfig,
  ) -> Unit
  async fn delete_collection(self : Self, name : String) -> Unit
  async fn collection_exists(self : Self, name : String) -> Bool
  async fn upsert_points(
    self : Self,
    name : String,
    points : Array[PointStruct],
  ) -> Unit
  async fn upsert_points_batch(
    self : Self,
    name : String,
    points : Array[PointStruct],
  ) -> Unit
  async fn search_points(
    self : Self,
    name : String,
    vector : Array[Double],
    limit : Int,
    filter? : Json?,
  ) -> Array[ScoredPoint]
  async fn search_with_filter(
    self : Self,
    name : String,
    vector : Array[Double],
    limit : Int,
    filter : Filter,
  ) -> Array[ScoredPoint]
}

///|
/// Trait-facing alias of `search_points_with_filter`: the trait method is
/// named `search_with_filter`, so this method exists under that name and
/// forwards to the full-featured search entry point. Defining it as a regular
/// method (rather than inside the impl block) keeps the trait implementation
/// free of deprecated implicit method promotion.
pub async fn QdrantClient::search_with_filter(
  self : QdrantClient,
  name : String,
  vector : Array[Double],
  limit : Int,
  filter : Filter,
  with_payload? : Bool = true,
  with_vector? : Bool = false,
) -> Array[ScoredPoint] {
  self.search_points_with_filter(
    name,
    vector,
    limit,
    filter,
    with_payload~,
    with_vector~,
  )
}

///|
pub impl VectorProvider for QdrantClient with fn create_collection(
  self,
  name,
  config,
) {
  QdrantClient::create_collection(self, name, config)
}

///|
pub impl VectorProvider for QdrantClient with fn delete_collection(self, name) {
  QdrantClient::delete_collection(self, name)
}

///|
pub impl VectorProvider for QdrantClient with fn collection_exists(self, name) {
  QdrantClient::collection_exists(self, name)
}

///|
pub impl VectorProvider for QdrantClient with fn upsert_points(
  self,
  name,
  points,
) {
  QdrantClient::upsert_points(self, name, points)
}

///|
pub impl VectorProvider for QdrantClient with fn upsert_points_batch(
  self,
  name,
  points,
) {
  QdrantClient::upsert_points_batch(self, name, points)
}

///|
pub impl VectorProvider for QdrantClient with fn search_points(
  self,
  name,
  vector,
  limit,
  filter?,
) {
  QdrantClient::search_points(
    self,
    name,
    vector,
    limit,
    // trait optional param arrives as Json??; unwrap the outer layer so the
    // inner Json? matches search_points' own optional parameter.
    filter=filter.unwrap_or(None),
  )
}

///|
pub impl VectorProvider for QdrantClient with fn search_with_filter(
  self,
  name,
  vector,
  limit,
  filter,
) {
  QdrantClient::search_with_filter(self, name, vector, limit, filter)
}
