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
    filter=filter.unwrap_or(None),
  )
}
