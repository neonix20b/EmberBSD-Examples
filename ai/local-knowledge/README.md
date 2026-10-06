# Local document answers with SQLite and llama.cpp

Index short local text documents with SQLite FTS5, retrieve matching evidence,
and ask the existing CPU llama.cpp server for a quotation that answers a
question. The C program checks the returned source ID and verifies the quote
against the retrieved document before displaying it. Inference uses local
assets and loopback HTTP; no external API is required.

This is an **extractive question-answering example**. It displays a verified
quotation, not an unchecked generated summary. It does not prove that the
quote fully answers an arbitrary question or that a document is true. A
small model can refuse, quote irrelevant text or fail validation. Documents
are supplied explicitly; the example never searches private directories.

## Dependencies and ownership

- C99/POSIX compiler, SQLite development headers/library with FTS5 and JSON,
  `pkg-config`, POSIX shell and curl.
- The existing [llama.cpp CPU package](https://github.com/neonix20b/EmberBSD-Ports/tree/main/profiles/ai-cpu).
  No separate engine installation is introduced.
- The existing [SmolLM2-135M-Instruct Q4_K_M asset](../local-inference/README.md),
  SHA256 `2e8040ceae7815abe0dcb3540b9995eaa1fa0d2ca9e797d0a635ae4433c68c2d`,
  105,454,432 bytes, Apache-2.0. Its immutable download and attribution remain
  in [the shared asset manifest](../local-inference/assets.tsv). The prompt
  uses this model's ChatML format; other models need separate validation.

Ports owns the SQLite and llama.cpp dependencies. This directory owns the
retrieval CLI, document fixtures and lifecycle wrapper. Fixtures describe
fictional devices, not operational maintenance instructions. Project-owned
files are [MIT licensed](LICENSE) and were developed with AI assistance.
They use no Python; inference does not execute document instructions or tools.

## Build and run

Install one supported SQLite through your package environment. The current
target is SQLite **3.53.4**; [the Ports consumer probe](https://github.com/neonix20b/EmberBSD-Ports/tree/main/probes/sqlite)
records exact source identity, native tests and the earlier installed 3.53.2
comparison. If using a temporary source prefix, select its pkg-config metadata
and runtime search path explicitly, as described by the probe.

From this directory:

```sh
work=$(mktemp -d /var/tmp/local-knowledge.XXXXXXXX)
sh build.sh "$work/knowledge"
sh tests/contracts.sh "$work/knowledge"

# Obtain and hash-check the pinned model separately, using local-inference's
# documented fetch step. Runtime does not download missing assets.
assets=/path/to/verified/ai-assets
AI_BIN=/path/to/ai-runtime/bin KNOWLEDGE_BIN="$work/knowledge" \
    sh ask.sh "$assets/SmolLM2-135M-Instruct-Q4_K_M.gguf" \
    pump 'What is the amber pump service interval?' "$work/pump-answer" \
    documents/pump.txt documents/sensor.txt

KNOWLEDGE_BIN="$work/knowledge" \
    sh ask.sh "$assets/SmolLM2-135M-Instruct-Q4_K_M.gguf" \
    nonexistent 'What is the nonexistent device specification?' "$work/no-evidence" \
    documents/pump.txt documents/sensor.txt
# The second command deliberately returns 3, without starting the server.
```

The tested answer is:

```text
Answer (verbatim evidence):
The amber pump service interval is seven days.
Source [1]: documents/pump.txt
```

The FTS expression and natural-language question are separate arguments.
For example, use `'pump OR sensor'` to retrieve either term. SQLite binds the
expression as a parameter; malformed FTS syntax fails instead of becoming SQL.
The CLI ranks up to three results with `bm25`, breaking ties by source ID.
It accepts at most 16 regular text files, each at most 2,048 bytes. Split
larger documents into short passages first. It rejects binary/control bytes,
named pipes, unreadable files and oversized inputs. It does not overwrite a
database or result directory. The retrieved passages must fit the configured
2,048-token model context; excessive context fails rather than proving success.

The lower-level commands are `knowledge index NEW_DB FILE...`,
`knowledge request DB FTS_QUERY QUESTION MODEL_ALIAS`, and
`knowledge answer DB FTS_QUERY RESPONSE_JSON MODEL_ALIAS`. The response parser
uses SQLite JSON functions and requires exactly `source` and `quote` fields.
It rejects invalid/truncated JSON completions, unknown/non-retrieved source IDs, invented quotations,
embedded NULs, and a completion from a different model alias. Header/runtime
SQLite source IDs must match. The raw response remains in the result directory
for inspection; only the validated quote appears as the answer.

## Exit statuses and process bounds

- `0`: a validated model quotation was displayed; `SUCCESS` is written.
- `3`: no matching documents, or an explicit model refusal. No `SUCCESS`.
- Other nonzero status: invalid input, malformed/unsupported model output,
  missing dependency, occupied port, HTTP error or server failure/timeout.

`ask.sh` runs one CPU inference thread with GPU layers disabled. It binds
`127.0.0.1` on `AI_PORT` (default 18081), rejects a responding occupied port,
and checks its unique alias in the response. Startup is limited to ten
one-second attempts; the request is limited to thirty seconds and 64 KiB.
`AI_STARTUP_ATTEMPTS` and `AI_REQUEST_TIMEOUT` can shorten these limits.
Cleanup signals only the child server that this run started, waits at most
five seconds, then kills/reaps it. Signal traps cover interruption.

## Validation boundary

On 2026-10-07 the existing EmberBSD/NetBSD 11.0 AArch64 UTM guest ran the
installed SQLite 3.53.2 consumer and actual llama.cpp model workflow. The
retained engine revision is `8345f333951c661d166b00e6f9362e553768f292`, one
commit after stable v0.6.0; that additional commit changes the disabled
Hexagon backend. It introduces no second CPU installation. The shared profile
records its exact source archive and license notices.

The model returned 25 tokens, including the expected quotation and source ID.
The complete wrapper took 3.63 seconds and its maximum RSS was 219,448 KiB.
These are a single smoke measurement under other VM load, not a benchmark.
The deterministic fixture checks separately cover empty retrieval, malformed
FTS/JSON, invalid documents, forged citations, wrong alias, explicit refusal,
dead server, startup timeout and owned-child cleanup. Fixture tests do not
count as real model inference.

The same workflow then passed with source-built, installed SQLite **3.53.4**
in a disposable EmberBSD/NetBSD 11.0 AArch64 QEMU guest (one vCPU, 3 GiB RAM,
GCC 12.5.0, EMBER64 kernel from OS revision `b4f718d`). Its exact SQLite source
ID is `bf7c7f30031888f4e796e429ab3978879485813aaca6f641c7b33e4e09459bcc`.
The C executable linked to the selected temporary SQLite prefix, and the
shared pinned model produced the same verified answer in two observed runs:
3.78 seconds/219,272 KiB maximum RSS, then 15.11 seconds/217,116 KiB during
concurrent build load. These timings are smoke evidence, not comparative
performance results. The source probe is temporary; use one system SQLite
from pkgsrc for a normal installation.

CPU execution in a VM does not establish board support, accelerators, large
corpus retrieval, arbitrary question quality, privacy against hostile local
processes, disconnected hardware operation or production service isolation.
FTS5 performs lexical retrieval; there are no embeddings or remote requests.
