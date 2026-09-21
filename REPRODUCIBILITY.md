# Reproducibility Guide

> MoonBit September Hackathon submission — `yuzhiblue/moon-qdrant`
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

# 4. (Optional) Re-run the full integration check — 30 assertions
moon run examples/integration_check -- http://localhost:6333
```

Both commands should finish in seconds against a freshly started Qdrant.

## Environment requirements

| Requirement | Version / note |
|---|---|
| MoonBit toolchain | `0.1.20260920` or newer (`curl -fsSL https://cli.moonbitlang.com/install/unix.sh \| bash`) |
| Docker | any recent version (or run Qdrant directly, see below) |
| Qdrant image | `qdrant/qdrant:v1.15.5` (pinned in CI) |

No API key or account is needed — the project talks to a plain local Qdrant
over its REST API.

## Step-by-step reproduction

### 1. Install the project

```bash
git clone https://github.com/yuzhiblue/moon-qdrant.git
cd moon-qdrant
moon install
```

`moon check --deny-warn` and `moon test` (63 unit tests) should pass
immediately, without any server:

```bash
moon check --deny-warn   # clean
moon test                # Total tests: 63, passed: 63
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

### 4. Re-run the integration check (optional)

The same 30-assertion check that CI runs against a live server:

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
| `Check and Test` | `moon check --deny-warn` + 63 unit tests on ubuntu / macOS / Windows | [![Check and Test](https://github.com/yuzhiblue/moon-qdrant/actions/workflows/check.yml/badge.svg)](https://github.com/yuzhiblue/moon-qdrant/actions/workflows/check.yml) |
| `Integration (real Qdrant)` | starts `qdrant/qdrant:v1.15.5`, runs the 30-assertion `integration_check`, then the demo end to end | [![Integration (real Qdrant)](https://github.com/yuzhiblue/moon-qdrant/actions/workflows/integration.yml/badge.svg)](https://github.com/yuzhiblue/moon-qdrant/actions/workflows/integration.yml) |

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
| Facet / group check fails with `No appropriate index for faceting` | The keyword payload index on the facet key must exist first — the demo and integration check create it up front, so this only happens with hand-written snippets that skip it |

## Package

`yuzhiblue/moon-qdrant` is published on mooncakes.io (latest: `0.4.1`):

```bash
moon add yuzhiblue/moon-qdrant
```
