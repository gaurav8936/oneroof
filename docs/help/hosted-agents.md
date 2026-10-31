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

Open New session, choose OpenCode or Goose, the saved connection and a specific repository. Enter the opening message and launch. First launch prepares private native settings and verifies the pinned executable, guard and remaining budget. Provider authentication is checked when the first request is made.

Answer native permissions in the terminal. Goose's verified approval menu also works in Decisions. OpenCode approvals stay in its terminal because the selected option is shown by color; Deny safely sends Escape. Unknown menus stay manual. The normal composer sends follow-up messages into the same live conversation.

The session popover identifies provider/model and shows request/reservation metadata. Reopening a running session reattaches; it does not send the opening twice. Closing or relaunching ends the live native conversation; relaunch starts a new one with retained budget counters. Save a handoff before ending important work.

Hosted objective steps require `agent`, exact `model` and `hosted_connection_id`. Hosted loops support one bounded round with native approvals. Timed/recurring paid starts remain disabled.

## If launch is blocked

Check the error first. Confirm the key file is readable, the model ID matches the provider, today's rates are verified, runtime paths are executable, the kit is outside the editable repo and the budget has remaining capacity. Never delete a ledger to bypass a cap. A changed guard requires repairing the managed installation. A provider error can still consume a reservation; consult the provider for final billing.
