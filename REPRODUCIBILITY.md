# Reproducibility Guide

> MoonBit November Hackathon submission — `yuzhiblue/moon-qdrant`
>
> This guide lets a reviewer reproduce the whole project in a few minutes:
> install, start a real Qdrant, run the end-to-end demo, and re-run the
> integration check that CI executes on every push.

## TL;DR

```bash
# 1. Get the MoonBit toolchain (see below) and install dependencies
moon install

# 2. Start a real Qdrant server (Docker)
docker run -p 6333:6333 qdrant/qdrant

# 3. Run the end-to-end demo against it
moon run examples/demo -- http://localhost:6333

# 4. (Optional) Re-run the full integration check
moon run examples/integration_check -- http://localhost:6333

# 5. (Optional) Run the multi-tenant hybrid retrieval case
moon run examples/rag_case -- http://localhost:6333
```

Both required commands should finish in seconds against a freshly started
Qdrant. The pure channel logic used by `rag_case` is also covered by
`moon test` and needs no server.

## Environment requirements

| Requirement | Version / note |
|---|---|
| MoonBit toolchain | MoonBit 1.0 Release Candidate (`moonc v1.0.0-rc1`, verified with `moon 0.1.20261126`) or newer (`curl -fsSL https://cli.moonbitlang.com/install/unix.sh \| bash`) |
| Docker | any recent version (or run Qdrant directly, see below) |
| Qdrant image | `qdrant/qdrant:v1.15.5` locally; CI covers both `v1.15.5` and `v1.20.2` |

No API key or account is needed — the project talks to a plain local Qdrant
over its REST API.

MoonBit 1.0 status: the compiler entered its release candidate on
2026-11-26 and is stable except for bug fixes; the final 1.0 release is
targeted for 2027-02-18. `moon fix` reports no changes for this project, and
`moon check --deny-warn` is clean on the 1.0 RC toolchain.

## Step-by-step reproduction

### 1. Install the project

```bash
git clone https://github.com/yuzhiblue/moon-qdrant.git
cd moon-qdrant
moon install
```

`moon check --deny-warn` and `moon test` should pass immediately, without any
server:

```bash
moon check --deny-warn   # clean
moon test                # Total tests: 91, passed: 91
```

### 2. Start Qdrant

```bash
docker run -p 6333:6333 qdrant/qdrant:v1.15.5
```

No Docker? Run the official binary directly (Linux/macOS):

```bash
# download qdrant-x86_64-unknown-linux-gnu.tar.gz from
# https://github.com/qdrant/qdrant/releases, then:
./qdrant
```

The server is ready when `curl http://localhost:6333/healthz` prints
`healthz check passed`.

To check modern-server compatibility locally, use
`docker run -p 6333:6333 qdrant/qdrant:v1.20.2` instead. The lock assertions
are skipped automatically on 1.16+; everything else is asserted on both
versions.

### 3. Run the end-to-end demo

```bash
moon run examples/demo -- http://localhost:6333
```

The demo exercises, in order: health check → create a collection → upsert
points (including a named-vector collection with `text` + `image` vectors) →
read / scroll / count → search (plain, filtered, score-threshold, batch) →
query API (nearest, recommend) → facet counts → grouped search → payload
set/delete → payload indexes → snapshots → aliases → service write lock →
cluster state → service info → cleanup.

Expected output (last lines from a real run):

```
facet values: 2
created snapshot: moon-qdrant-demo-8395176413058734-2026-09-21-06-45-17.snapshot
deleted collection: moon-qdrant-demo
created named-vector collection: moon-qdrant-demo-named
named-vector search (text): 1
named-vector search (image): 1
deleted named-vector collection: moon-qdrant-demo-named
demo finished
```

### 4. Run the multi-tenant hybrid case (optional)

```bash
moon run examples/rag_case -- http://localhost:6333
```

The run prints each channel's input and ranked output before fusion. The
semantic channel is led by `kb-001` (closest vector); the lexical channel is
led by `kb-004` (both query terms present) and does not contain `kb-001` at
all. The final list is tenant-verified and deduplicated: `foreign-001` never
appears and `kb-004` appears once.

### 5. Re-run the integration check (optional)

The same check that CI runs against a live server:

```bash
moon run examples/integration_check -- http://localhost:6333
```

Every line prints `[PASS]` and the run ends with:

```
ALL INTEGRATION CHECKS PASSED
```

## Evidence of verification on a real server

The repository ships two GitHub Actions workflows that run on every push:

| Workflow | What it does | Status |
|---|---|---|
| `Check and Test` | `moon check --deny-warn` + 91 unit tests on ubuntu / macOS / Windows | [![Check and Test](https://github.com/yuzhiblue/moon-qdrant/actions/workflows/check.yml/badge.svg)](https://github.com/yuzhiblue/moon-qdrant/actions/workflows/check.yml) |
| `Integration (real Qdrant)` | matrix over `qdrant/qdrant:v1.15.5` and `v1.20.2`; on each runs the `integration_check`, the demo and the multi-tenant hybrid case end to end | [![Integration (real Qdrant)](https://github.com/yuzhiblue/moon-qdrant/actions/workflows/integration.yml/badge.svg)](https://github.com/yuzhiblue/moon-qdrant/actions/workflows/integration.yml) |

Both are green on `main`. The integration workflow is what caught and fixed
16 real bugs (wrong endpoint paths such as `/points/facet` → `/facet`,
`/indexes` → `/index`, `/service` → `/`; missing `keys` field; named-vector
search shape; single-node cluster responses; etc.) — every client method is
verified against a live server, not just mocked.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Connection refused` on `localhost:6333` | Qdrant is not running; start it (step 2) and wait for `healthz check passed` |
| Port 6333 already in use | Use another port: `docker run -p 6334:6333 qdrant/qdrant` and pass `http://localhost:6334` to the demo |
| `moon: command not found` | Install the MoonBit toolchain (see requirements); add `~/.moon/bin` to `PATH` |
| `GET/POST /locks` returns 404 | Qdrant deprecated the service lock API in 1.15 and removed it in 1.16. `integration_check` and `demo` read `service_info().version` and skip the lock assertions on 1.16+; use `v1.15.5` if you want to exercise them locally |
| `Collection ... already exists!` on a second demo run | The demo expects a fresh server; delete the leftover collections first (`curl -X DELETE http://localhost:6333/collections/moon-qdrant-demo`) |
| Facet / group check fails with `No appropriate index for faceting` | The keyword payload index on the facet key must exist first — the demo and integration check create it up front, so this only happens with hand-written snippets that skip it |

## Package

`yuzhiblue/moon-qdrant` is published on mooncakes.io (latest: `0.8.2`):

```bash
moon add yuzhiblue/moon-qdrant
```
