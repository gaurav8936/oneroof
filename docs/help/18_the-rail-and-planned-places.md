# The rail: 13 places and the planned ones

Since 2.0.8 (LAB-2332) the rail has 13 places in six groups, a thin line between groups:

| Group | Place | Key | What it holds |
|---|---|---|---|
| Work | Home | ⌃⌘1 | The front page: what needs you, what runs, tonight |
| | Inbox | ⌃⌘2 | Questions and asks from agents (badge: waiting) |
| | Sessions | ⌃⌘3 | Every agent session, by window |
| | Projects | ⌃⌘4 | Linear projects and tickets |
| Agents | Agents · Planned | ⌃⌘A | The roster: every agent and account, signed in, limits, cost |
| | Factory · Planned | ⌃⌘P | The playbook: teams of agents (recipes) for a kind of task |
| Run | Loops | ⌃⌘6 | Work that runs by itself |
| | Trace | ⌃⌘9 | Every agent action: History (its first tab), X-ray and Cost (planned) |
| | Resources | ⌃⌘5 | Memory, CPU, sessions and processes on this Mac |
| Models | Evals | ⌃⌘8 | Test models and agents on benchmarks |
| | Train · Planned | ⌃⌘R | Fine-tune and RL jobs on GPUs, fed by Evals |
| Ship | Ship · Planned | ⌃⌘S | live → lift → develop → main, releases, deploy status |
| Learn | Learn | ⌃⌘7 | The Agentic Engineering course, papers, influences |

Settings stays at the foot of the rail (⌘,). The old places keep their keys; History's ⌃⌘9 opens Trace on History, and
a window saved on History opens on Trace. Factory is ⌃⌘P (for playbook) because macOS keeps ⌃⌘F for full screen.

**Spacing.** The places spread out to fill a tall window and tighten in a short one: first the space between places,
then the gaps between groups, then the buttons. Only below that does the list scroll; Settings always shows.

**Planned places** carry a grey PLANNED tag on the rail. Their page says what the place is for, what is coming, where
the nearest thing lives today (buttons), and the Linear tickets that build it.

**The step-1 icon row** in the toolbar shows Home, Inbox, Sessions, Projects, Loops and Trace; the ⋯ button lists the
rest.

## Factory: recipes

A recipe is a team of agents for a kind of task: the **roles** and which agent and model plays each, the **pattern**
they work in, the **finish line** (a command that exits 0 when the task is done, and where the result goes: QA, a pull
request or a report) and the **budget** (minutes, dollars, rounds, parallel parts up to 3). Five are built in, one per
pattern:

| Recipe | Pattern | Team |
|---|---|---|
| Build it, another agent checks it | Maker → checker | Claude builds, Codex reviews |
| Ticket from plan to write-up | Pipeline | Claude plans, builds and writes up; Codex tests |
| Sweep a list of small bugs | Fan-out → merge | Claude splits and merges; Kimi fixes, 3 at a time |
| Two answers and a judge | Two answers → judge | Claude and Codex answer; Gemini judges |
| Fix until the tests pass | Loop until the check passes | Claude fixes, Codex confirms; 5 rounds |

Your own recipes are JSON files in `~/Library/Application Support/OneRoof/recipes/` (Factory › Recipes folder). Copy a
built-in with **Copy as JSON**, change it, save it there and press **Reload**. A recipe that cannot run says why (for
example, a checker on the same agent and model as the maker). **Run on a task** comes with the orchestrator (LAB-198).
