# 👁️ Watcher for Beads

<p align="center">
  <em>A beautiful, native macOS graphical interface for <a href="https://github.com/steveyegge/beads">Steve Yegge's beads (bd)</a> issue tracker.</em>
</p>

---

**Watcher** is a desktop application built specifically for macOS that brings your local `bd` repositories to life. It reads directly from your `.beads` databases and provides a rich, visual way to manage your tasks, bugs, and epics without leaving the comfort of a native UI.

## ✨ Features

- **🍎 Native macOS Design:** Built with `macos_ui`, Watcher feels right at home on your Mac. It features glassmorphic sidebars, native segmented controls, and deep integration with light/dark modes.
- **⚡️ Live Reloading:** Watcher watches your local `.beads` directories. If you (or an AI agent) update a task using the `bd` CLI, the UI updates instantly. No refresh button required.
- **🗂️ Multi-Project Management:** Add as many local repositories as you want to the sidebar. Seamlessly jump between contexts in milliseconds.
- **🌳 Hierarchical Tree View:** Visualize your Epics, Tasks, and Subtasks exactly how they relate to each other, complete with native disclosure triangles to expand or collapse complex trees.
- **📋 Kanban Board:** See the flow of your work at a glance with automatically organized columns for Open, In Progress, and Closed issues.
- **🔍 Issue Inspector:** Click any issue to slide out a detailed inspector panel containing the full description, priority, owner, and timestamps.

## 🚀 Getting Started

### Prerequisites

1. Ensure you have the [beads (`bd`) CLI](https://github.com/steveyegge/beads) installed and initialized in at least one local repository.
2. Install the [Flutter SDK](https://docs.flutter.dev/get-started/install/macos).

### Installation

Clone this repository and get the dependencies:

```bash
git clone https://github.com/yourusername/watcher.git
cd watcher
flutter pub get
```

**To install the app on your Mac:**

We strongly recommend using the included `Makefile` to install Watcher directly to your `/Applications` folder. This process automatically builds the release version, strips Gatekeeper quarantine flags, and recursively applies an ad-hoc code signature to all embedded frameworks. This prevents macOS from silently crashing the app on launch due to Apple Mobile File Integrity (AMFI) policies.

```bash
make install
```

**To run the app in development mode:**

```bash
flutter run -d macos
```

### Usage

1. Open Watcher.
2. Click **+ Add Project** in the bottom left of the sidebar.
3. Select a local directory that has been initialized with `bd` (i.e., it contains a `.beads` folder).
4. Watch your tasks populate instantly!

## 🧠 How it Works

Watcher is strictly a **frontend viewer** designed to work in harmony with the `bd` CLI, rather than replacing it. 

Instead of connecting directly to the underlying Dolt database, Watcher uses OS-level file watching (via `fsevents`) on your `.beads` directory. When it detects a change, it shells out to the `bd export` and `bd graph` commands behind the scenes to fetch the latest state. This guarantees that Watcher always perfectly reflects the true state of your issue graph, exactly as the CLI sees it.

## 🛠️ Contributing

We welcome contributions! If you're an AI agent or a human developer looking to help out, please check out our `GEMINI.md` and `docs/ARCHITECTURE.md` files for core architectural decisions, styling guidelines, and UI quirks specific to this codebase.

Note: All issue tracking for Watcher is done internally using `bd`. Run `bd list` to see what needs doing!

---
*Built with Flutter, `macos_ui`, and love.*