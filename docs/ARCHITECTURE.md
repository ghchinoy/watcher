# Watcher Architecture

This document outlines the core architectural decisions and trade-offs for the Watcher application.

## Auto-Reloading Data: File Watching vs. Reading Dolt

**Decision:** Use OS-level File Watching (via Dart's `Directory.watch`) with a debounce timer, rather than directly polling or querying the underlying Dolt database.

**Context:**
The Watcher application needs to reflect changes to the `beads` issues in near real-time when the underlying data is updated by the `bd` CLI (or by other agents/developers).

**Options Considered:**

1. **File Watching (Selected):** Listen to changes in the project's `.beads` directory.
   * *Pros:* Extremely fast, uses OS-native event triggers (e.g., `fsevents` on macOS), and requires zero idle CPU overhead.
   * *Cons:* OS file events can be noisy (emitting multiple events for a single save) and lack context about *what* changed.
   * *Mitigation:* We implement a "debounce" timer (e.g., 500ms) to coalesce rapid file system events, followed by a re-export of the current state using `BeadsService`.

2. **Reading Dolt Directly:** Query the Dolt SQL server or execute `dolt` CLI commands on a polling interval.
   * *Pros:* Dolt is the ultimate source of truth, handles concurrency perfectly, and supports delta queries (finding exactly what changed).
   * *Cons:* Relies on polling which consumes constant CPU and disk I/O. Integrating a SQL driver or managing a background `dolt sql-server` process adds significant complexity and overhead to a lightweight desktop viewer.

**Implementation Strategy:**
The `AppState` or `BeadsService` will instantiate a file watcher on the `.beads` folder when a project is selected. When file modifications are detected, a debounce timer is reset. Once the timer fires, the app calls `bd export` and `bd graph` to refresh the in-memory models. 

Additionally, a **30-second background heartbeat** timer ensures the UI stays synchronized even if OS-level file events are missed or coalesced.

## macOS Native UI Paradigms

**Decision:** Strictly adhere to Apple Human Interface Guidelines (HIG) by using the `macos_ui` package for navigation and data display, specifically separating "Context" from "View".

**Context:**
Early iterations placed Dashboard, Tree, and Kanban view switches in the left-hand Sidebar alongside the list of Projects. This created a confusing navigation model.

**Implementation Strategy:**
1. **Context via Sidebar:** The left `Sidebar` is exclusively dedicated to selecting the "Context" (which `bd` project is active). 
2. **View Mode via ToolBar:** Changing *how* you view that context is handled by a custom `ViewModeSegmentedControl` embedded in the `actions` array of the `ToolBar`. This aligns with Finder and Xcode. The control uses native icons, sizing (22px height), and subtle glassmorphic drop shadows to match the OS perfectly.
3. **Inspector Panel:** Issue details are displayed using the `endSidebar` property. Because `macos_ui` has complex internal constraints around animating sidebars, we manage its visibility programmatically using a custom `_InspectorController` wrapper that calls `MacosWindowScope.of(context).toggleEndSidebar()`, ensuring smooth, crash-free slide animations.
4. **App Settings Persistence:** User preferences (like the list of loaded projects) are saved via `shared_preferences`. On macOS, this writes to `NSUserDefaults` keyed to the application's `PRODUCT_BUNDLE_IDENTIFIER` (`wtf.ghc.watcher`).

## Agent Interaction & UI Feedback Loops

**Decision:** Treat Watcher as an active "Controller" that mutates state exclusively via the `bd` CLI, relying on the `Directory.watch` loop to eventually hydrate the UI.

**Context:**
Watcher needs to allow users to update task statuses and priorities, as well as move tasks across the Kanban board, without getting out of sync with AI agents operating in the same repository.

**Implementation Strategy:**
1. **Interactive Controls:** `IssueInspector` uses `MacosPopupButton`s and the `KanbanScreen` implements `Draggable`/`DragTarget` logic to initiate state changes. 
2. **Safe Mutation:** These controls call `appState.updateIssue()`, which shells out to `bd update <id> ...`. We *do not* manually construct new `Issue` objects in Dart to update the local state. Instead, we let the file watcher detect the CLI's save operation and trigger a full `getIssues()` refresh 500ms later. This guarantees the UI never drifts from the actual Dolt database state.
3. **Agent Locks:** To prevent a user from accidentally dragging a task away from an active agent, `KanbanCard`s conditionally disable their `Draggable` wrapper and display a Lock icon if `status == 'in_progress'` or if the `owner` field is populated.
4. **Activity Monitoring:** `BeadsService` parses the `.beads/interactions.jsonl` log file to construct a live `ActivityTicker` on the Dashboard, giving users a real-time, scrolling heartbeat of exactly what agents (or other developers) are doing in the repository.

## AI Integration (Hybrid Strategy)

**Decision:** Employ a hybrid AI strategy: leverage `tmux` and native terminal emulators for interactive agent workloads, while using the direct **Firebase AI Logic** SDK (Vertex AI backend) for automated background tasks and real-time voice mode.

**Context:**
Watcher aims to be an "AI-Augmented Controller." It needs to balance transparency (seeing the agent think) with efficiency (silent background summarization).

**Implementation Strategy:**

### 1. Interactive Agents (Terminal Orchestration)
For complex planning or health assessments where user interaction/approval is required, Watcher orchestrates `tmux` sessions.
1. **The tmux Anchor:** When an AI action is triggered, Watcher's `TmuxService` checks if a specific `tmux` session exists for the current project. If not, it spawns one in detached mode. This session acts as the persistent context anchor for `geminicli`.
2. **Asynchronous Handoff:** Watcher writes the complex LLM prompt to a temporary file (`.beads/ai_prompt.txt`) to bypass shell-escaping nightmares. It then sends a command pipeline to the tmux pane: `gemini -p "$(cat .beads/ai_prompt.txt)" | tee .beads/ai_out.md; touch .beads/ai_done`.
3. **Foreground Visibility:** Watcher immediately shells out to macOS (`open -a`) to bring the user's preferred native terminal (e.g., Ghostty, iTerm2, or Terminal.app) to the foreground, automatically attaching it to the running tmux session. The user can watch the AI stream text, approve tool executions natively, and intervene if necessary.
4. **File Polling & Resolution:** Meanwhile, Watcher UI enters a non-blocking "Check your terminal" loading state. It spins up an async loop polling for the existence of the `.beads/ai_done` lockfile. Once the lockfile is created by the terminal process, Watcher cleans up the temporary files, parses `.beads/ai_out.md`, and renders the generated action plan in a native `MacosSheet` for final user execution.

### 2. Background Agents (Direct API)
For automated, non-interactive tasks, Watcher calls the Gemini API directly via the `firebase_ai` package.
1. **The Summarization Pipeline:** When a task is closed, `AppState` triggers an asynchronous call to `GenerativeAiService`. It uses `gemini-3-flash-preview` (via Vertex AI) to summarize the resolution based on comment history and description context.
2. **System Comments:** The resulting summary is posted back to the issue as a system comment (e.g., `🤖 Resolution Summary: ...`), ensuring the resolution intent is captured in the `interactions.jsonl` audit trail and dashboard ticker.

### 3. Future: Watcher Live (Voice Mode)
We plan to implement a real-time, multimodal "Live" mode using `liveGenerativeModel`. This will allow bidirectional audio streaming to query the status of all local projects simultaneously using natural language (e.g., *"Which of my projects has the most P0 tasks?"*).

## macOS HIG Compliance: Outline Views

**Decision:** The hierarchical "Tree View" must strictly map to Apple's Human Interface Guidelines (HIG) for Outline Views.

**Context:**
Originally, Watcher's tree view attempted to mimic the command-line styling of `bd list --tree` by rendering continuous graphical lines (`├──`) and non-standard text prefixes (`↳`) for child nodes.

**Implementation Strategy:**
1. **Hierarchy via Indentation:** Do not draw branch lines or text prefixes to connect children to parents. Hierarchy is communicated entirely through negative space (indentation) and the presence of a disclosure triangle (chevron) on parent nodes.
2. **Consistent Leading Icons:** Outline views expect visual context for each item. We render the `issue.issueType` icon (e.g., epic, bug, feature) as the leading element immediately following the disclosure triangle for *all* nodes, regardless of their depth in the tree.
3. **Trailing Badges for Status:** The right side of the Outline View is reserved for secondary metadata. We map semantic statuses like `blocked` (Red/Minus Symbol) and `deferred` (Grey/Snow Symbol) to specific colors to allow quick scanning without interrupting the primary hierarchical layout on the left.

## Standalone Architecture: The Go RPC Daemon

**Decision:** Embed a Go daemon (`watcher-daemon`) within the macOS application bundle to interact with the Dolt database via the `steveyegge/beads` library, rather than compiling via CGO/FFI or using local TCP network sockets (like gRPC).

**Context:**
Originally, Watcher shelled out to the `bd` CLI for every query and mutation. This introduced roughly ~100ms of latency per action (spawning the process, loading config, connecting to MySQL/Dolt) which made drag-and-drop operations on the Kanban board feel slightly sluggish. To achieve true standalone performance, we needed to hold the database connection open in memory.

**Implementation Strategy:**
1. **The Sidecar Pattern:** We compile a small Go binary that imports the `beads` core library. When Watcher launches, it starts this daemon as a child process.
2. **JSON-RPC over Stdin/Stdout:** Watcher and the daemon communicate by piping JSON-RPC 2.0 messages over standard input and output streams. 
3. **Why not gRPC?** While Dolt uses gRPC internally for syncing (`remotesapi`), running a local gRPC server for the UI-to-daemon bridge would require binding to a local TCP port (e.g., `localhost:9090`). Local ports are prone to conflicts, aggressive firewalls, and orphaned zombie processes if the UI crashes. Stdin/stdout anonymous pipes are inherently tied to the parent UI process's lifecycle—if Watcher dies, the pipe breaks, and the Go daemon gracefully self-terminates immediately.
4. **Why not CGO / Dart FFI?** Building C-bindings to pass complex nested structs (like a graph of issues and dependencies) across the memory boundary between Go and Dart is notoriously brittle and requires manual memory management. Using standard JSON over IPC provides a clean, type-safe contract that Dart's `json_serializable` handles perfectly with zero CGO boilerplate.

## Database Connections: Server Mode vs. Embedded Mode

**Decision:** The `watcher-daemon` strongly recommends and defaults to **Dolt Server Mode**. It proactively cleans up stale database server connections before initialization to prevent cross-process lock contention and circuit-breaker timeouts.

**Context:**
Dolt operates in two modes: 
1. **Server Mode (Recommended):** A background TCP daemon (`dolt sql-server`) manages the database. This allows multiple concurrent readers and writers (e.g., the Watcher UI, multiple AI agents, and a developer in the terminal) to operate on the same repository without hitting 'database is locked' errors.
2. **Embedded Mode:** Direct file I/O with a single writer lock. While simpler for single-user CLI tools, it is **not recommended** for use with Watcher because the UI and background agents will frequently collide, leading to `noms LOCK` errors and application crashes.

**Implementation Strategy:**
1. **Enforced Server Mode:** The `beads` library is configured to prefer Server mode. If a server is not already running, `beads` will attempt to start one automatically.
2. **Pre-boot Cleanup:** Before the Go daemon attempts to connect to the Dolt database, it shells out to `bd dolt killall`. This mimics the behavior of `bd doctor`, proactively scanning the OS process tree and SIGKILLing any orphaned Dolt SQL servers that might be holding a dead lock on the `.beads/dolt/` directory.
3. **Graceful IPC Errors:** If a database is fundamentally corrupted (e.g. `noms LOCK` from an embedded crash), the daemon catches the initialization error and prints a serialized JSON-RPC error payload to `stdout` before exiting. This ensures the Dart UI can gracefully render the error state on the dashboard instead of succumbing to an unhandled asynchronous `SocketException`.
3. **Stream Accumulation:** To prevent large JSON-RPC payloads (like graphs containing massive architectural `.md` files) from being truncated or fragmented by Dart's internal buffer limits, the UI decodes the `stdout` stream using the raw `json.decoder` rather than the naive `LineSplitter()`.

