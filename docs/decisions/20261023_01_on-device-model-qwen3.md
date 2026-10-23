# ADR · The on-device model is Qwen3-1.7B (Apache-2.0), not Arch-Router

**Status:** ACCEPTED (One Roof 0.5.2) · **Date:** 2026-10-23 · **Issues:** LAB-83 (LAB-673 test set, LAB-674 swap, LAB-675 download button)

> **One line:** the optional on-device model that sorts a task into a kind is now Qwen3-1.7B (Q4_K_M GGUF, Apache-2.0), asked with a plain prompt and a JSON schema; it scored 37 of 38 on a fixed test set against Arch-Router's 32 of 38, answers in about 0.13 s, and its licence lets anyone use One Roof for any purpose.

## Context

Since 0.3 the classifier was Arch-Router-1.5B (Katanemo, now DigitalOcean), a fine-tune of Qwen2.5-1.5B-Instruct. Its licence (DigitalOcean Community License) allows redistribution but needs a separate licence for commercial use (§4, "commercial purposes" not defined). One Roof could therefore not offer a one-click download of it, and people using One Roof at work were on unclear ground.

## The test

- **Set:** 38 task sentences written the way people name plan steps and sessions, 5 or 6 per kind (research, design, code, review, test, docs, chore), 9 of them ambiguous with a second fair answer ([app/scripts/route-eval/tasks.json](../../app/scripts/route-eval/tasks.json)). Kinds and their descriptions come from the bundled `routing.json`.
- **Harness:** [app/scripts/route-eval.py](../../app/scripts/route-eval.py) starts its own `llama-server` (same flags as the app, spare port), sends each sentence with the app's request body, parses the answer with the app's `parseRoute` rule, and reports strict accuracy, lenient accuracy (second fair answer counts), latency and the server's memory. One model at a time.
- **Machine:** Apple silicon Mac, 16 GB, Homebrew llama.cpp build 11669, temperature 0, `max_tokens` 20, one warm-up request not timed.
- **Prompts:** `arch` is Arch-Router's own route prompt (what the app sent up to 0.5.1). `kinds` is the new prompt: a system message listing the kinds and their descriptions, three one-line rules (features and bug fixes are code; test only for tests or reproducing a failure; chore only for maintenance that changes no behaviour), eight examples not taken from the test set, the user message `Task: <sentence>`, and `response_format` `json_schema` with the kinds as an `enum`, so the answer is always one of the seven. Four prompt variants were tried on the same set before settling; the numbers below are for the final one, so treat small differences as noise.

## Results

| Model (GGUF) | Size | Prompt | Strict | Lenient | Median latency | Server memory | Licence |
|---|---|---|---|---|---|---|---|
| Arch-Router-1.5B Q4_K_M (baseline) | 0.99 GB | arch | 32/38 · 84.2% | 33/38 · 86.8% | 209 ms | 1.17 GB | DigitalOcean Community (non-commercial) |
| Arch-Router-1.5B Q4_K_M | 0.99 GB | kinds | 33/38 · 86.8% | 33/38 · 86.8% | 230 ms | 1.21 GB | DigitalOcean Community (non-commercial) |
| Qwen2.5-1.5B-Instruct Q4_K_M | 1.12 GB | kinds | 34/38 · 89.5% | 35/38 · 92.1% | 111 ms | 1.25 GB | Apache-2.0 |
| Qwen3-0.6B Q8_0 | 0.64 GB | kinds | 33/38 · 86.8% | 33/38 · 86.8% | 74 ms | 1.07 GB | Apache-2.0 |
| **Qwen3-1.7B Q4_K_M** | **1.11 GB** | **kinds** | **37/38 · 97.4%** | **37/38 · 97.4%** | **132 ms** | **1.62 GB** | **Apache-2.0** |
| Qwen3-1.7B Q8_0 | 1.83 GB | kinds | 37/38 · 97.4% | 37/38 · 97.4% | 138 ms | 2.26 GB | Apache-2.0 |

Qwen2.5-1.5B with the first, plain prompt (kinds and descriptions only, no rules or examples) scored 23/38; Qwen3 with Arch-Router's prompt and no schema scored 0/38 (it thinks first and runs out of tokens). The prompt matters as much as the model.

Sources (pinned revisions; SHA-256 of the file as published):

| File | Repository @ revision | SHA-256 | Bytes |
|---|---|---|---|
| Arch-Router-1.5B-Q4_K_M.gguf | katanemo/Arch-Router-1.5B.gguf @ bd9b1caf68e4 | b55666691f14089cf4422b443431e2b783033d99dce6c7df147565192b4deb76 | 986,047,936 |
| qwen2.5-1.5b-instruct-q4_k_m.gguf | Qwen/Qwen2.5-1.5B-Instruct-GGUF @ 91cad51170dc | 6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e | 1,117,320,736 |
| Qwen3-0.6B-Q8_0.gguf | Qwen/Qwen3-0.6B-GGUF @ 23749fefcc72 | 9465e63a22add5354d9bb4b99e90117043c7124007664907259bd16d043bb031 | 639,446,688 |
| Qwen3-1.7B-Q4_K_M.gguf | unsloth/Qwen3-1.7B-GGUF @ d7f544eead69 | b139949c5bd74937ad8ed8c8cf3d9ffb1e99c866c823204dc42c0d91fa181897 | 1,107,409,472 |
| Qwen3-1.7B-Q8_0.gguf | Qwen/Qwen3-1.7B-GGUF @ 90862c4b9d27 | 061b54daade076b5d3362dac252678d17da8c68f07560be70818cace6590cb1a | 1,834,426,016 |

## Decision

**Use Qwen3-1.7B, Q4_K_M quantisation, with the `kinds` prompt.** It is the most accurate (8 points above Qwen2.5-1.5B, 13 above the Arch-Router baseline), fast enough (0.13 s), and Apache-2.0. Between its two quantisations the accuracy is the same, so the smaller one wins: 0.7 GB less to download and 0.6 GB less memory, which matters on 8 GB Macs.

- **Where it comes from:** Qwen publishes Qwen3-1.7B as GGUF only in Q8_0. The Q4_K_M file comes from Unsloth's GGUF repository (a quantisation of Qwen's weights under the same Apache-2.0 licence). One Roof pins the revision, the byte size and the SHA-256, so the file a user gets is exactly the one tested. Switching to Qwen's own Q8_0 is a three-constant change in `LocalModel.swift` (URL, SHA-256, size) if provenance ever matters more than size.
- **Thinking off:** Qwen3 thinks before answering by default. Every request sends `chat_template_kwargs: {"enable_thinking": false}`; without it the answer is empty. Other models ignore the field.
- **Captions** use the same model. They now send a JSON schema of the caption reply instead of `json_object`: with plain `json_object` Qwen3 sometimes returned `steps` as a list and Arch-Router an empty object, both rejected by the validator; with the schema both models returned valid replies on the samples tried.
- **Arch-Router still works** for anyone who points Settings at it: the classifier prompt is generic, and on that prompt Arch-Router scores about what it did before. Settings shows a note when the model path still names Arch-Router, because of its licence.

## Consequences

- One Roof can offer a one-click **Get the model** (Settings and the Foundations check), downloading the pinned file and verifying it.
- `THIRD-PARTY-NOTICES.md` (bundled in the app) lists Qwen3 (Apache-2.0) and llama.cpp (MIT, installed separately by Homebrew).
- The test set and harness stay in the repo: run them again before changing the model, the prompt or the kind descriptions.
