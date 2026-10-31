# OpenCode and Goose with hosted models

OpenCode and Goose run the coding session on your Mac. Together AI, OpenRouter or Fireworks runs the model remotely. You do not need a local model or GPU.

## Set up a connection

1. Open Settings → Seats & accounts → Hosted coding.
2. Enter a connection name, provider and exact model ID. Choose the path to an external credential file; never paste a key into a model, argument or name field.
3. Open Runtime installation. Select Python 3.11+ with PyYAML, a kit containing `ae/hostedsession.py`, OpenCode 1.19.5 and Goose 1.57.0, and a private storage folder. These installations and your credential must be outside the repository the session edits.
4. Refresh catalogue prices for Together or OpenRouter. For Fireworks, enter verified rates from its official model page. Rates are USD per million input/output tokens; verify the date today.
5. Choose the session and shared connection reservation ceilings. The shared ceiling covers all sessions on this connection. Reservations are conservative estimates and remain reserved after failed requests; they do not show your provider account balance.
6. Save connection and runtime. Optional MCP settings import only reviewed server definitions, never other agent account settings.

## Start and continue

Open New session, choose OpenCode or Goose and the saved connection, and start at ~/Projects or in any repository, as with every other agent. At ~/Projects the kit, Python, the agent and the credential stay off limits to the agent's tools. Enter the opening message and launch. First launch prepares private native settings and verifies the pinned executable, guard and remaining budget. Provider authentication is checked when the first request is made.

Answer native permissions in the terminal or in Needs you. Goose's approval menu shows all four of its options there (Allow once, Always Allow, Deny, Cancel), each pressing its own key. OpenCode's allow options can only be picked in its terminal because its selection is shown by color; its Reject works from Needs you (it sends Escape). When either agent finishes a turn, it waits in Needs you with what it said last and a reply box. Unknown menus stay manual. The normal composer sends follow-up messages into the same live conversation.

The session popover identifies provider/model and shows request/reservation metadata. Reopening a running session reattaches; it does not send the opening twice. Closing or relaunching ends the live native conversation; relaunch starts a new one with retained budget counters. Save a handoff before ending important work.

Hosted objective steps require `agent`, exact `model` and `hosted_connection_id`. Hosted loops support one bounded round with native approvals. Timed/recurring paid starts remain disabled.

## Verified models

One connection per provider is enough. In New session, the connection's menu lists every model below for its provider; pick one per session. The connection's key, session and shared ceilings, and shared ledger stay the same; the session uses that model's listed prices. Settings › Hosted coding still accepts any exact model ID by hand.

Only open-weight, code-focused models are listed; no commercial ones. Each row passed the same check with **both** OpenCode and Goose through the supervised hosted session: a reply, one real tool call (reading a file), and a follow-up answered from memory. Prices are USD per million input / output tokens on the verified date: Together and OpenRouter from their live catalogues, Fireworks from its model pages. Check today's price on the provider before relying on it.

<!-- MODEL-TABLE-BEGIN -->
| Model | Provider | Model ID | Input $/M | Output $/M | Verified |
|---|---|---|---|---|---|
| GLM-5.3-Flash | Together AI | `zai-org/GLM-5.3-Flash` | $0.15 | $0.5 | 2026-10-31 |
| DeepSeek V4.1 Flash | Together AI | `deepseek-ai/DeepSeek-V4.1-Flash` | $0.3 | $1.2 | 2026-10-31 |
| gpt-oss-120b | Together AI | `openai/gpt-oss-120b` | $0.15 | $0.6 | 2026-10-31 |
| MiniMax M3 | Together AI | `MiniMaxAI/MiniMax-M3` | $0.3 | $1.2 | 2026-10-31 |
| GLM-5.3-Flash | Fireworks | `accounts/fireworks/models/glm-5p3-flash` | $0.15 | $0.5 | 2026-10-31 |
| gpt-oss-120b | Fireworks | `accounts/fireworks/models/gpt-oss-120b` | $0.15 | $0.6 | 2026-10-31 |
| MiniMax M3 | Fireworks | `accounts/fireworks/models/minimax-m3` | $0.3 | $1.2 | 2026-10-31 |
| GLM-5.3-Flash | OpenRouter | `z-ai/glm-5.3-flash` | $0.0163 | $0.1479 | 2026-10-31 |
| Qwen3-Coder-Next | OpenRouter | `qwen/qwen3-coder-next` | $0.12 | $0.8 | 2026-10-31 |
| Kimi K2.7 Code | OpenRouter | `moonshotai/kimi-k2.7-code` | $0.6 | $3.5 | 2026-10-31 |
| DeepSeek V4.1 Flash | OpenRouter | `deepseek/deepseek-v4.1-flash` | $0.045 | $0.5 | 2026-10-31 |
| gpt-oss-120b | OpenRouter | `openai/gpt-oss-120b` | $0.15 | $0.6 | 2026-10-31 |
| Devstral 2 (2512) | OpenRouter | `mistralai/devstral-2512` | $0.4 | $2 | 2026-10-31 |
| MiniMax M3 | OpenRouter | `minimax/minimax-m3` | $0.3 | $1.2 | 2026-10-31 |
<!-- MODEL-TABLE-END -->

Checked the same day and left out:

<!-- NOT-OFFERED-BEGIN -->
- Together AI `Qwen/Qwen3-Coder-Next-FP8`: the provider rejected the model for both agents (HTTP 400; not served on demand)
- Together AI `moonshotai/Kimi-K2.7-Code`: the provider rejected the model for both agents (HTTP 400; not served on demand)
<!-- NOT-OFFERED-END -->

## If launch is blocked

Check the error first. Confirm the key file is readable, the model ID matches the provider, today's rates are verified, runtime paths are executable, the kit is outside the editable repo and the budget has remaining capacity. Never delete a ledger to bypass a cap. A changed guard requires repairing the managed installation. A provider error can still consume a reservation; consult the provider for final billing.
