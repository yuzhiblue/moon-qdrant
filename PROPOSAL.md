# moon-qdrant 项目申报书

> 本版叙述草稿按章程附录一的审核建议（价值与生态定位 / 交付范围与工程边界 /
> 实现路径与技术理解）撰写，供参考修改。**请用你自己的话调整后提交**——
> 章程明确"明显包含 AI 套话的申报书会被驳回"，事实、数字、API 名可以直接用，
> 叙述表达请改成你自己的说法。

## 基本信息

- 项目名称：moon-qdrant —— Qdrant 向量数据库的 MoonBit 客户端
- 参赛者：yuzhiblue
- 联系方式：（填写你的邮箱/微信）
- GitHub 仓库链接：https://github.com/yuzhiblue/moon-qdrant
- 项目方向：向量数据库客户端 / RAG 基础设施
- 是否为移植项目：否（原创项目，无移植来源）

## 项目简介

做 RAG 和 embedding 检索应用时，向量数据库是绕不开的一环。Qdrant 是目前最主流的开源向量数据库之一，我注意到 MoonBit 生态里已经有本地 ANN 引擎（`ywz1314/vector`）和向量库服务端（`trkbt10/vcdb`），但缺少一个能直接对接远程向量服务 REST API 的客户端库：想在 MoonBit 里读写 Qdrant，只能自己拼 HTTP 请求和 JSON 编解码，重复劳动且容易出错。这个位置正好是空的——vcdb 做服务端，我用 MoonBit 写客户端，正好与服务端、本地引擎互补：数据量小、单机场景用本地引擎；数据量大或要托管服务时，用 moon-qdrant 对接 Qdrant。mooncakes 上检索 qdrant/milvus/chroma/weaviate/pgvector/faiss 均无客户端，没有竞品，做出来就是生态里第一个通用向量服务客户端。

## 核心功能范围

- 集合管理：创建 / 列表 / 详情 / 删除 / 存在性检查
  （`create_collection` / `list_collections` / `collection_info` /
  `delete_collection` / `collection_exists`）；
- 点操作：写入（普通与批量）、读取、按 ID 删除
  （`upsert_points` / `upsert_points_batch` / `get_point` / `delete_points`）；
- 向量搜索：按相似度返回 Top-K，支持 payload 过滤条件（`search_points`）；
- 统一接口抽象：`VectorProvider` trait；
- 工程配套：CI（Linux/macOS/Windows 三平台 check+test+fmt+info）、
  12 个单元测试、端到端示例与健康检查 CLI、README 可复现说明。

## 明确不做（工程边界）

- 不做向量数据库服务端、索引构建和 ANN 算法——那是 Qdrant 与 vcdb 的职责；
- 不做本地持久化，本库只负责与远程服务通信；
- v0.1 聚焦集合管理、点写入、向量搜索三条最常用路径；Qdrant 的分片、
  快照、集群管理、scroll/推荐 API 等高级能力明确留到后续版本。

## 预期使用场景

1. RAG 应用：把文档切块做 embedding，用 `upsert_points_batch` 批量写入
   Qdrant；检索时用 `search_points` 按相似度召回，配合 payload 过滤按
   来源/标签缩小范围；
2. 相似度场景：内容推荐、近似去重、异常检测等需要向量相似检索的
   MoonBit 程序，直接用 moon-qdrant 读写 Qdrant；
3. 生态基建：统一 `VectorProvider` trait 让上层代码面向接口编程，
   为后续接入更多向量服务（milvus、chroma 等）留出扩展位。

## 实现路径与技术理解

实现上我选最直接的一条路：在 `oboard/mio` 的 async HTTP 之上做一层统一的
`send()` 传输，把返回状态码和 JSON 一并交给业务层；每个 API 对应一个 parse
函数把 JSON 映射成类型化模型，传输层与业务模型分离，以后加新接口只需补
parse。对 API 语义与 MoonBit 类型系统的贴合也做了设计：`get_point` 在 404
时返回 `None`、`collection_exists` 返回 `false`，把 HTTP 状态码翻译成
Option 而不是让调用方做字符串判断；批量写入走 `/points/batch` 一次提交
多条，RAG 建库场景吞吐差异明显。CI 在 Linux/macOS/Windows 三平台跑
native target，这是踩过坑后定的：wasm 目标下 mio 缺 TLS 符号，native 才稳。

## 预期验收产物

- `yuzhiblue/moon-qdrant` 库发布到 mooncakes.io；
- GitHub 仓库公开、提交记录清晰（≥10 个有效 commit）；
- `moon check --deny-warn` 与 `moon test`（12 个用例）通过，CI 三平台全绿；
- README 提供可复现的快速开始（Docker 启动 Qdrant + 示例运行）。

## 原创性说明

本项目为**原创项目，非移植**，无外部移植来源与许可证义务。

选题查重（提交申报前已在 mooncakes.io 核实）：

| 已有包 | 类型 | 与本品差异 |
|---|---|---|
| `ywz1314/vector` | 嵌入式 ANN 引擎 | 本地内存引擎，非远程服务客户端 |
| `trkbt10/vcdb` | 向量库服务端 | 是服务端实现，缺客户端库 |
| `colmugx/sqlite-vec` | SQLite FFI 绑定 | 绑定 SQLite 扩展，非通用服务客户端 |
| `wskwsk68/MoonEmbed` | 本地词嵌入检索 | 本地离线检索，非远程服务 |
| `codeworm96/magpiedb` | OLAP 引擎 | 分析引擎，方向不同 |

按关键词检索 `qdrant` / `milvus` / `chroma` / `weaviate` / `pgvector` /
`faiss` 在 mooncakes.io 上均**无客户端库**，本选题不构成重复。
