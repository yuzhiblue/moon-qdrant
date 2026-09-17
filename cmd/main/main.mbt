///|
/// Demo CLI: check the health of a Qdrant server and list collections.
///
/// Usage:
///   moon run cmd/main -- http://localhost:6333
async fn main {
  let argv = @env.args()
  let base_url = if argv.length() > 1 {
    argv[1]
  } else {
    "http://localhost:6333"
  }
  let client = @moon_qdrant.QdrantClient::new(base_url)
  let healthy = client.health() catch {
    err => {
      println("health check failed: " + err.to_string())
      false
    }
  }
  if healthy {
    println("Qdrant is healthy at " + base_url)
  } else {
    println("Qdrant is not healthy at " + base_url)
  }
}
