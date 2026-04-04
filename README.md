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
- **🤖 AI Terminal Orchestration:** Run AI Health Assessments and Planners transparently! Watcher seamlessly orchestrates `tmux` sessions in the background and can launch your preferred terminal emulator (Ghostty, iTerm2, or Terminal.app) so you can watch the AI agent work in real-time, approve commands, and retain context across sessions.
- **🤖 Native AI Integration:** Direct integration with Gemini via Firebase AI Logic (Vertex AI backend) for background task summarization and future voice mode features.

## 🚀 Getting Started

### Prerequisites

1. Ensure you have the [beads (`bd`) CLI](https://github.com/steveyegge/beads) installed and initialized in at least one local repository.
2. Install the [Flutter SDK](https://docs.flutter.dev/get-started/install/macos).
3. Ensure you have `tmux` installed (`brew install tmux`) for AI Terminal Orchestration features.

### 🤖 Firebase & AI Setup

Watcher uses **Firebase AI Logic** with the **Vertex AI** backend for native Gemini integration.

1.  **Install Firebase CLI:**
    ```bash
    npm install -g firebase-tools
    ```
2.  **Configure Firebase:**
    In the project root, run:
    ```bash
    flutterfire configure --project=YOUR_GCP_PROJECT_ID
    ```
    Select `macos` as the supported platform. This will generate `lib/firebase_options.dart`.
3.  **Enable APIs:**
    Ensure the **Vertex AI API** is enabled in your Google Cloud Console for the selected project.
4.  **Configure Watcher:**
    - Open Watcher Settings (`Cmd + ,`).
    - Enter your **GCP Project ID**.
    - Set your preferred **Vertex Location** (default: `us-central1`).
    - Select a **Gemini Model** (e.g., `gemini-3-flash-preview`).

*Note: Preview models like Gemini 3 Flash automatically use the `global` region.*

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

### AI Terminal Orchestration

Watcher leverages a unique "Asynchronous Handoff" architecture to provide AI assistance without hiding the agent's work. 
1. When you trigger an AI action, Watcher ensures a detached `tmux` session exists for the current project.
2. It constructs a shell command that runs `gemini`, uses `tee` to write the output to a `.beads/ai_out.md` file, and `touch`es a `.beads/ai_done` lockfile upon completion.
3. Watcher injects this command into the `tmux` session and tells macOS to launch your Preferred Terminal (configured in Global Settings).
4. You get to watch the AI work in a beautiful, native terminal. If the AI asks for permission to execute a shell command, you can interact with it directly!
5. Meanwhile, Watcher's UI polls for the `.beads/ai_done` file. Once the AI finishes, Watcher reads the generated plan back into the GUI for you to review and apply.

## 🛠️ Contributing

We welcome contributions! If you're an AI agent or a human developer looking to help out, please check out our `GEMINI.md` and `docs/ARCHITECTURE.md` files for core architectural decisions, styling guidelines, and UI quirks specific to this codebase.

Note: All issue tracking for Watcher is done internally using `bd`. Run `bd list` to see what needs doing!

---
*Built with Flutter, `macos_ui`, and love.*