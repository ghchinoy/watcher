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
