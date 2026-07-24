# Agent Instructions

**IMPORTANT FOR AI ASSISTANTS:** You must read **`GEMINI.md`** alongside this file. `GEMINI.md` contains core architectural rules, design patterns, and critical macOS-specific layout and execution quirks that you must adhere to when writing code.

## Issue Tracking

This project uses **bd (beads)** for issue tracking.
Run `bd prime` for workflow context, or install hooks (`bd hooks install`) for auto-injection.

**Quick reference:**
- `bd ready` - Find unblocked work
- `bd create "Title" --type task --priority 2` - Create issue
- `bd update <id> --claim` - Claim work atomically
- `bd close <id> --reason "Completed"` - Complete work
- `bd dolt push` - Push beads to remote

For full workflow details: `bd prime`

## Non-Interactive Shell Commands

**ALWAYS use non-interactive flags** with file operations to avoid hanging on confirmation prompts.

Shell commands like `cp`, `mv`, and `rm` may be aliased to include `-i` (interactive) mode on some systems, causing the agent to hang indefinitely waiting for y/n input.

**Use these forms instead:**
```bash
# Force overwrite without prompting
cp -f source dest           # NOT: cp source dest
mv -f source dest           # NOT: mv source dest
rm -f file                  # NOT: rm file

# For recursive operations
rm -rf directory            # NOT: rm -r directory
cp -rf source dest          # NOT: cp -r source dest
```

**Other commands that may prompt:**
- `scp` - use `-o BatchMode=yes` for non-interactive
- `ssh` - use `-o BatchMode=yes` to fail instead of prompting
- `apt-get` - use `-y` flag
- `brew` - use `HOMEBREW_NO_AUTO_UPDATE=1` env var
- `git` - background network tasks (e.g. `git pull`) can hang indefinitely due to SSH key passphrases or downstream server latency. If a Git background task takes more than 15 seconds, kill it, run `git status`, and confirm local branch status rather than looping.

## Conventional Commits & Automated Releases

This project uses Google's **Release Please** to automate versioning and release packaging.

- **Use Conventional Commits Exclusively:** Your git commit messages must use standard prefixes (e.g. `feat:`, `fix:`, `chore:`, `refactor:`, `test:`, `docs:`) so the automated release pipeline can parse them.
- **Commit Prefixes Rule the Version Bump:**
  - `fix:` triggers a **Patch** version bump (e.g. `0.7.0 -> 0.7.1`).
  - `feat:` triggers a **Minor** version bump (e.g. `0.7.0 -> 0.8.0`).
  - `BREAKING CHANGE:` or `!` suffix (e.g. `feat!:`) triggers a **Major** version bump.
- **NEVER Manually Edit Versions or Changelog:** Do not edit `CHANGELOG.md`, `pubspec.yaml`'s `version:` field, or `.release-please-manifest.json` directly. The release pipeline will automatically generate a release PR with these changes compiled based on your conventional commit messages.

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **Separate Commit from Network Push** - Run local committing (`git add ... && git commit ...`) as an isolated terminal command before running remote push commands (`git pull --rebase && git push`). This ensures your commit is locally saved before network requests or SSH/auth verification prompts occur.
5. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   git push
   git status  # MUST show "up to date with origin"
   ```
6. **Clean up** - Clear stashes, prune remote branches
7. **Verify** - All changes committed AND pushed
8. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
