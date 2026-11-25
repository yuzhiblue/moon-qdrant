// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "yuzhiblue/moon-qdrant"

version = "0.8.0"

readme = "README.md"

repository = "https://github.com/yuzhiblue/moon-qdrant"

license = "Apache-2.0"

keywords = [ "qdrant", "vector-database", "client", "rag", "embedding" ]

preferred_target = "native"

supported_targets = "+native"

description = "A MoonBit client for the Qdrant vector database REST API."

import {
  "gaato/mttp@0.5.2",
}
