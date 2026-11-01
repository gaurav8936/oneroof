# Third-party notices

One Roof is MIT-licensed (see `LICENSE`). It includes, or works with, the following third-party software and model.
This file is bundled in the app (`Contents/Resources/THIRD-PARTY-NOTICES.md`).

## Included in the app

### libghostty (Ghostty v1.3.1) · MIT

Linked into One Roof for its terminals; roofd's headless terminal (RoofVT) is built from the same source. The
keyboard, IME and mouse handling in `TerminalSurfaceView` is ported from Ghostty's macOS app.

```
MIT License

Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Downloaded only when you ask

### Qwen3-1.7B (on-device model) · Apache-2.0

The optional on-device model that sorts tasks into kinds and writes captions. Not inside the app: **Get the model**
(Settings › Foundations, or the Foundations check) downloads `Qwen3-1.7B-Q4_K_M.gguf`, a Q4_K_M quantisation by
Unsloth (huggingface.co/unsloth/Qwen3-1.7B-GGUF) of Qwen3-1.7B by the Qwen team, Alibaba Cloud
(huggingface.co/Qwen/Qwen3-1.7B), and puts the Apache License 2.0 text next to it as `Qwen3-1.7B-LICENSE.txt`
(also bundled as `Contents/Resources/licenses/Qwen3-LICENSE.txt`). Copyright 2025 Alibaba Cloud. Licensed under the
Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0). The file is used unmodified.

## Used if installed, not included

### llama.cpp (`llama-server`) · MIT

Runs the on-device model. One Roof does not ship it: it starts the `llama-server` that Homebrew installs
(`brew install llama.cpp`), as a separate process on 127.0.0.1. Copyright (c) 2023-2024 The ggml authors; MIT License
(github.com/ggml-org/llama.cpp).

### Arch-Router-1.5B (earlier on-device model) · DigitalOcean Community License

One Roof used Arch-Router-1.5B up to 0.5.1 and never shipped or downloaded it. It still works if you point Settings at
your own copy, under its own licence, which requires a separate licence for commercial use.

## Narration

### OpenAI text-to-speech (generated audio, no code)

Narration: AI-generated voice (OpenAI text-to-speech). The narrated audio in Learn (cards, Radio, papers) and Evals ›
How to was generated with OpenAI's text-to-speech API; it is an AI voice, not a human voice. Only the audio files ship;
no OpenAI key, account or library is included. OpenAI's usage policies ask that listeners are told the voice is
AI-generated (https://openai.com/policies/usage-policies; text-to-speech guide checked 2026-11-01).
