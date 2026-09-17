# moon-qdrant 项目申报书

> ⚠️ **本文件是事实素材骨架，正式申报请务必用你自己的话重写叙述部分**
> （章程明确：明显包含 AI 套话的申报书会在审核阶段被驳回）。
> 下方的要点全部是项目真实情况，你可以直接引用其中的事实与数字，
> 但**"项目简介/为什么做/场景描述"等叙述文字请自己组织语言**。

## 基本信息

- 项目名称：moon-qdrant —— Qdrant 向量数据库的 MoonBit 客户端
- 参赛者：yuzhiblue
- 联系方式：（填写你的邮箱/微信）
- GitHub 仓库链接：https://github.com/yuzhiblue/moon-qdrant
- 项目方向：向量数据库客户端 / RAG 基础设施
- 是否为移植项目：否（原创项目，无移植来源）

## 项目简介

【请用你自己的话改写，以下为技术事实供引用】

- Qdrant 是广泛使用的开源向量数据库，是 RAG（检索增强生成）和
  embedding 检索场景的常见基础设施；
- MoonBit 生态中已有向量检索的**嵌入式引擎**（`ywz1314/vector`）和
  **向量数据库服务端**（`trkbt10/vcdb`），但没有能直接对接**远程向量
  服务 REST API** 的客户端库；
- moon-qdrant 填补这个空缺：让 MoonBit 程序直接创建集合、写入向量点、
  按相似度搜索，打通 MoonBit → RAG 应用链路；
- 通过统一的 `VectorProvider` trait，上层代码可以面向接口编程，
  未来可扩展对接其他向量服务。

## 核心功能范围

- 集合管理：创建 / 列表 / 详情 / 删除 / 存在性检查
  （`create_collection` / `list_collections` / `collection_info` /
  `delete_collection` / `collection_exists`）；
- 点操作：写入（普通与批量）、读取、按 ID 删除
  （`upsert_points` / `upsert_points_batch` / `get_point` / `delete_points`）；
- 向量搜索：按相似度返回 Top-K，支持 payload 过滤条件
  （`search_points`）；
- 统一接口抽象：`VectorProvider` trait；
- 工程配套：CI（Linux/macOS/Windows 三平台 check+test+fmt+info）、
  12 个单元测试、端到端示例与健康检查 CLI、README 可复现说明。

## 预期使用场景

1. 【请你补全叙述】RAG 应用：MoonBit 程序将文本 embedding 后写入
   Qdrant，检索时按语义相似度召回，并用 payload 过滤（如按标签/来源筛选）；
2. 【请你补全叙述】相似度应用：内容推荐、近似去重、异常检测等需要
   向量相似检索的场景；
3. 【请你补全叙述】MoonBit 生态基建：作为面向向量服务的统一客户端
   入口，为后续更多向量服务接入提供接口范式。

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
