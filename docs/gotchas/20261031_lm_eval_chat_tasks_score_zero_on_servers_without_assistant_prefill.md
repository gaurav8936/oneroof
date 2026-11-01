# lm-eval's `*_chat` tasks score 0 % on servers without assistant prefill (llama-server)

**Found:** 2026-10-31 (LAB-1997, lm-eval 0.4.13, llama-server b11669).

**Symptom.** `arc_challenge_chat` on a local model through `local-chat-completions` scores exactly 0 %, while the
same model gets ~70 % in Inspect. Every response reads "The best answer is C" and the target is "C".

**Cause.** The task sets `gen_prefix: 'The best answer is'` and expects the server to continue that pre-filled
assistant turn, so the model should return only " C". llama-server's chat endpoint does not continue a pre-filled
reply; the model writes the whole sentence and `remove_whitespace` + exact match never equals "C".
lm-eval's default multiple-choice scoring (log-likelihood) is no way out either: it needs prompt log-probabilities
(`echo`), which llama-server's `/v1/completions` does not return.

**Do.** Use `arc_challenge_chat_letter` (`app/Resources/evals/lmeval_tasks/`): same prompt and data, the letter read
with a regex. Keep the raw 0 % run as the lesson: Learn › Two frameworks, one benchmark.
