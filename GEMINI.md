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

## Interaction & Command Execution
- Prefer using the `dart` tool integrations when manipulating Dart/Flutter code (e.g. `dart_format`, `dart_fix`, `analyze_files`, etc.).
- When running shell commands that modify the filesystem, prefer non-interactive flags as outlined in `AGENTS.md` (e.g., `rm -f`, `cp -f`).

## macOS UI & Flutter Quirks
- **Sidebar & Inspector Panels:** Never set `MacosWindow.endSidebar` or `sidebar` to `null` dynamically, as it crashes the internal layout builder. Instead, maintain the widget in the tree (e.g., with 0 width) and use `MacosWindowScope.of(context).toggleEndSidebar()` to animate it open and closed. Use `ValueKey` on the `Sidebar` if you need to force a rebuild for a new data selection.
- **ToolBar Layout:** Be cautious of `RenderFlex` overflows in the `ToolBar`. The `title` property has a strict width constraint. Interactive widgets like Segmented Controls should be placed in the `actions` array using `CustomToolbarItem`.
- **Shared Preferences:** macOS uses `NSUserDefaults` keyed to the `PRODUCT_BUNDLE_IDENTIFIER` in `macos/Runner/Configs/AppInfo.xcconfig`. Changing this ID will effectively wipe all saved `shared_preferences` for the application.
