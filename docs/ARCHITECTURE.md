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
