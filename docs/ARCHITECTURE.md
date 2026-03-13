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

## AI Integration (Headless Planner & Assessor)

**Decision:** Leverage `gemini-cli` as a headless background process for complex codebase analysis and graph assessment, rather than rebuilding API integrations or context-gathering loops natively in Flutter.

**Context:**
Watcher aims to be an "AI-Augmented Controller." It needs the ability to generate new project plans (breaking goals into Epics and Tasks) and assess the health of the current `bd` graph (finding priority inversions or blocked paths).

**Implementation Strategy:**
1. **Headless Execution:** Watcher shells out to `gemini -p "<prompt>" --approval-mode plan`. This runs the AI agent in a safe, read-only "dry run" mode. 
2. **Context Gathering:** Because we run the `gemini` command within the selected project's `workingDirectory`, the CLI automatically handles reading the `.beads/config.yaml`, the git repository state, and relevant source files, completely abstracting this complexity away from the Flutter app.
3. **Structured Outputs:** We prompt the LLM to output its plan *exclusively* as a bash script of `bd create` or `bd update` commands wrapped in a markdown code block.
4. **Human in the Loop:** Watcher intercepts this response, parses the markdown, and presents the generated bash script to the user in a native `MacosSheet` modal (`PlannerModal` / `AssessmentModal`). The user must explicitly click "Approve & Execute" before the script is saved to a temporary file and executed against the repository.

## macOS HIG Compliance: Outline Views

**Decision:** The hierarchical "Tree View" must strictly map to Apple's Human Interface Guidelines (HIG) for Outline Views.

**Context:**
Originally, Watcher's tree view attempted to mimic the command-line styling of `bd list --tree` by rendering continuous graphical lines (`├──`) and non-standard text prefixes (`↳`) for child nodes.

**Implementation Strategy:**
1. **Hierarchy via Indentation:** Do not draw branch lines or text prefixes to connect children to parents. Hierarchy is communicated entirely through negative space (indentation) and the presence of a disclosure triangle (chevron) on parent nodes.
2. **Consistent Leading Icons:** Outline views expect visual context for each item. We render the `issue.issueType` icon (e.g., epic, bug, feature) as the leading element immediately following the disclosure triangle for *all* nodes, regardless of their depth in the tree.
3. **Trailing Badges for Status:** The right side of the Outline View is reserved for secondary metadata. We map semantic statuses like `blocked` (Red/Minus Symbol) and `deferred` (Grey/Snow Symbol) to specific colors to allow quick scanning without interrupting the primary hierarchical layout on the left.
