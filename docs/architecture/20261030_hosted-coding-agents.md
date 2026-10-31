# Hosted coding agents in One Roof

Project: LAB-AE-OPEN-AGENTS · local implementation, pending release acceptance.

OpenCode and Goose are native coding agents. Together AI, OpenRouter and Fireworks serve the model. The user selects a connection and an exact provider model ID separately from the agent. No model weights or GPU are installed locally.

## Connection and launch boundary

`AppSettings.hostedConnections` stores UUID identities, external credential file references, exact model IDs, dated input/output rates and explicit reservation ceilings. `hostedRuntime` identifies a Python/PyYAML installation, the agent-engineering kit, pinned native executable paths, private storage and an optional reviewed MCP configuration. The optional config contributes MCP definitions only.

`HostedPreparation` creates a scoped config, profile and dedicated native home for each new session off the main thread. `ae.hostedsession --prepare` installs the selected agent's skills and native guards, verifies installation hashes, exact native version and remaining reservations, and acknowledges the chosen agent/provider/model. New managed Goose homes opt out of telemetry. Provider authentication is checked on the first inference request; catalogue access is not authentication proof.

The stored Session carries a connection UUID and a prepared launch reference. LaunchPlan validates its model, repository, fixed argv shape, profile hash and current price date. Roofd starts the supervisor directly, without a login shell. Only runtime environment essentials and the selected kit path reach the supervisor. The bridge reads the external key in memory; native agents receive only a loopback bearer token. Existing subscription agents retain their launch behavior.

The kit, Python, binaries, credential and private launch files must remain outside the repository the agent can edit. This tool policy is not an operating-system sandbox against hostile programs. Native tool approval is always manual for these hosted agents.

## Lifecycle and terminal decisions

Each supervisor owns an inner PTY; roofd owns its outer PTY and preserves it across window closure or app restart. Roofd uses the explicit agent identity because the outer process is Python. Opening messages require the pinned native input markers and are submitted once. Quiet startup screens and Goose telemetry questions are not ready signals. Hosted openings are never automatically retried after 45 seconds.

Goose 1.57.0 approvals expose a selected radio marker. The adapter validates the entire four-option menu and generates relative arrow keys plus Enter. The command comes from the structured approval request, not another tool's preview. OpenCode 1.19.5 indicates selection by color: Escape reliably rejects, while approval remains in its native terminal. Unknown menus never borrow another agent's keys or get marked answered without sending anything. Native questions can always be answered in the terminal.

Reopening an alive session reattaches to its existing conversation. Relaunch starts a fresh native conversation and retains its phase/shared ledger. Native transcript resume after a terminated process is not implemented by this change; do not present a relaunch as conversation recovery.

## Plans, loops and usage

Plan steps accept `hosted_connection_id` alongside an exact `agent` and `model`. Unknown agents fail parsing instead of silently becoming Claude. A hosted objective step requires a saved, current matching connection and uses the supervised launch path.

Hosted loops retain a connection/runtime snapshot and use the same preparation path inside their own worktree. Only one bounded manual round is supported; nightly/recurring paid runs are refused in the daemon as well as constrained by the UI. No native auto-approve flags are used.

A connection's shared ledger covers all sessions using that connection; each session also has a phase ceiling. Both reserve a conservative maximum before forwarding requests, retain failed/pending reservations and fail closed on corruption or identity mismatch. These are estimates, not provider balances. The session popover reads bounded usage metadata asynchronously: request count, reserved maximum and reported token totals when available. The separate Cost section and subscription headroom project remain backlog.

## Validation

Core tests cover old-row migration, strict plan identities, credential-free launch environments, fixed supervised argv, changed-profile refusal, native readiness, native permission menus and conservative usage semantics. Real hosted native trials and packaged-app acceptance evidence are kept in the rollout report. No installed-app release is implied by passing local tests.
