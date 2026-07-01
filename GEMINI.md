# Watcher: AI Assistant Guidelines

## Project Overview
**Watcher** is a macOS desktop application built with Flutter and Dart. It provides a rich graphical user interface (GUI) for **beads (`bd`)**, a lightweight, dependency-aware issue tracker built on the Dolt database. 
The goal of this application is to allow users to visually manage, navigate, and triage their `bd` tasks across multiple local repositories via Kanban boards, Tree views, and Dashboards.

## Core Mandates & Architecture
For detailed architectural decisions, always refer to and update `docs/ARCHITECTURE.md`.

- **Data Ingestion (File Watching):** We do not connect to the Dolt database via SQL to read data. Instead, we use OS-level file watching on the local `.beads` directory. When changes are detected, we use Dart's `Process.run` to execute `bd export` and `bd graph` to refresh the data models.
- **State Management:** We use standard Flutter `ChangeNotifier` and `ListenableBuilder` (e.g., `AppState`) to manage and react to state changes. 
- **UI Framework:** We strictly use the `macos_ui` package to ensure the application looks and feels native to macOS.

## Development Workflow
1. **Issue Tracking:** All task tracking for the Watcher project itself must be done using the `bd` CLI. Follow the instructions in `AGENTS.md` for interacting with issues, claiming work, and completing tasks.
2. **Documenting Decisions:** When making significant architectural decisions, trade-offs, or choosing specific patterns, document them in `docs/ARCHITECTURE.md` to maintain a historical record of *why* choices were made.
3. **Adding Features:** When adding new UI screens, ensure they are properly registered in `lib/router.dart` (using `go_router`) and integrated into the `Sidebar` in `lib/screens/home_screen.dart`.
4. **Automated Releases (Release Please):** We use Google's *Release Please* to fully automate versioning and changelog generation based on Conventional Commits (prefixes like `feat:`, `fix:`, `chore:`, `refactor:`, `test:`, `docs:`). Do NOT manually bump versions in `pubspec.yaml` or edit `CHANGELOG.md` when closing `bd` tasks; let the automated release pipeline handle it on merge.

## Interaction & Command Execution
- Prefer using the `dart` tool integrations when manipulating Dart/Flutter code (e.g. `dart_format`, `dart_fix`, `analyze_files`, etc.).
- When running shell commands that modify the filesystem, prefer non-interactive flags as outlined in `AGENTS.md` (e.g., `rm -f`, `cp -f`).

## macOS UI & Flutter Quirks
- **Sidebar & Inspector Panels:** Never set `MacosWindow.endSidebar` or `sidebar` to `null` dynamically, as it crashes the internal layout builder. Instead, maintain the widget in the tree (e.g., with 0 width) and use `MacosWindowScope.of(context).toggleEndSidebar()` to animate it open and closed. Use `ValueKey` on the `Sidebar` if you need to force a rebuild for a new data selection.
- **ToolBar Layout:** Be cautious of `RenderFlex` overflows in the `ToolBar`. The `title` property has a strict width constraint. Interactive widgets like Segmented Controls should be placed in the `actions` array using `CustomToolbarItem`.
- **Shared Preferences:** macOS uses `NSUserDefaults` keyed to the `PRODUCT_BUNDLE_IDENTIFIER` in `macos/Runner/Configs/AppInfo.xcconfig`. Changing this ID will effectively wipe all saved `shared_preferences` for the application.

## macOS Build & Deployment Quirks
- **App Sandbox:** Watcher acts as a wrapper around local developer tools (`bd` and `gemini`). Because sandboxed macOS apps are strictly forbidden from executing arbitrary binaries outside of their own bundle, the **macOS App Sandbox MUST remain disabled** (`<key>com.apple.security.app-sandbox</key> <false/>` in `Release.entitlements`).
- **Deployment / Gatekeeper:** Because the sandbox is disabled and the app uses a local ad-hoc signature, copying the built `.app` bundle into `/Applications/` will cause macOS AMFI (Apple Mobile File Integrity) to instantly kill the app on launch due to the `com.apple.provenance` extended attribute.
- **The Symlink Workaround:** To bypass this, we strictly deploy the app by symlinking it. Never copy the `.app` bundle. Always use `make install` which creates an alias: `ln -s $(BUILD_DIR)/Watcher.app /Applications/Watcher.app`. This keeps the app outside Gatekeeper's quarantine rules while still being accessible via Spotlight and the Applications folder.

## Go Daemon Architecture
- **Compilation & Testing:** The Watcher application relies on a bundled Go binary (`watcher-daemon`) for database access. This binary must be compiled and copied into the `Watcher.app/Contents/Resources` directory during the build process. Note that both building and running tests (`go test ./...`) in the `daemon` directory require passing brew-specific ICU environment flags: `CGO_CFLAGS="-I$(brew --prefix icu4c)/include" CGO_LDFLAGS="-L$(brew --prefix icu4c)/lib" CGO_CXXFLAGS="-std=c++17 -I$(brew --prefix icu4c)/include"`.
- **RPC Communication:** The Dart UI communicates with the Go daemon via JSON-RPC 2.0 over standard input and output (`stdin`/`stdout`). We do not use gRPC or local TCP ports to avoid firewall issues and orphaned processes.
- **Go Standards:** The `daemon` directory must adhere to standard Go practices. It must pass `golangci-lint run` and should eventually include a `_test.go` suite to mock and verify JSON-RPC serialization.
+- **Subprocess Environment & PATH:** When shelling out to `bd` commands (`bd export`, `bd comments`, `bd federation sync`) from inside the daemon backend, you MUST explicitly append robust environment paths (`PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin`) to the process environment. Failure to do this causes executable-not-found errors when the `.app` runs in native macOS GUI environments (which lack shell profile environment inheritance).
+- **Database Lock Collisions:** `bd` runs on Dolt, which enforces file-system level locking. Avoid launching simultaneous parallel processes that read/write to the same database directory. When implementing daemon actions that shell out to the `bd` CLI (such as triggering background exports during active server operations), ensure transient lock exceptions are handled gracefully.

## macOS Execution & Path Quirks
- **macOS `PATH` and `Process.run` Limitations:** When using Dart's `Process.run` or `Process.start` to execute external CLI tools (like `tmux`, `gemini`, or `bd`), **never assume the binary is in the path.** macOS GUI applications (when launched from Finder or via `make install`) do not inherit the user's shell `$PATH` (e.g., `/opt/homebrew/bin`). Always provide an explicit environment map (e.g., `environment: {'PATH': '/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin'}`) or dynamically resolve the absolute path to the binary before executing.
- **Prefer Internal Daemon (`BeadsService`) over CLI Shell-outs:** When Watcher needs to read data (e.g., getting the issue graph for AI assessments), **do not shell out to `bd export`**. Always use the active `BeadsService` daemon RPC calls (e.g., `await appState.currentService!.getIssues()`). It avoids all macOS `$PATH` limitations and is significantly faster because the database connection is already hot.
- **Ghostty Execution (`ghostty -e`):** When telling Ghostty to execute a command via Dart's `Process.start`, **never pass the command as a single string** (e.g., `['-e', 'tmux attach -t session']`). Ghostty will interpret the entire string as a single executable filename and instantly crash the terminal instance. Pass every argument as a separate item in the list: `['-e', 'tmux', 'attach', '-t', 'sessionName']`.
- **Dart String Interpolation with Regex:** Be extremely careful when using Dart string interpolation `${...}` that contains nested raw strings or Regular Expressions (like `r'[^a-zA-Z0-9_]'`). Always use **double quotes** for the outer string (e.g., `"watcher_${name.replaceAll(...)}"`). If you use single quotes, the internal quotes in the regex will break the parser or force you into confusing escape sequences.

## Hybrid AI Strategy
- **Interactive Agents (Terminal):** Use the `tmux` + `geminicli` orchestration pattern for tasks requiring user visibility or multi-step tool interactions (e.g., Health Assessment, Planning).
- **Background Agents (Direct API):** Use `firebase_ai` (Vertex AI backend) for high-frequency, non-interactive tasks like automated task resolution summarization. This avoids UI disruption and terminal popups.

## Ghostty & AppleScript
- **Bypassing Security Dialogs:** Never use the `-e` flag with `open` for Ghostty as it triggers a per-command execution security check. Instead, use **AppleScript** (`osascript`) to "write text" into a fresh Ghostty window launched with `open -na`. This ensures a single-window experience and bypasses the dialog.

## Data Consistency
- **Refresh Heartbeat:** In addition to file watching, the application maintains a 30-second background heartbeat to ensure the UI stays synchronized even if OS-level events are missed.
- **Manual Refresh:** Always provide a manual refresh trigger in the UI (e.g., the PROJECTS header button) to allow users to force a data reload.
