# Releasing Watcher

This document outlines the process for releasing a new version of Watcher.

## Versioning Scheme

Watcher follows [Semantic Versioning](https://semver.org/).
- **Major:** Breaking changes or significant architectural shifts.
- **Minor:** New features and major UI improvements.
- **Patch:** Bug fixes and maintenance.

Versions are tracked in `pubspec.yaml`.

## Automated Releases (GitHub Actions)

The preferred way to release is via the automated GitHub Actions workflow.

1.  **Update Version:** Bump the version in `pubspec.yaml`.
    ```yaml
    version: 0.2.0+1
    ```
2.  **Commit and Push:** Commit the version bump to `main`.
3.  **Create Tag:** Create a git tag matching the version (prefixed with `v`).
    ```bash
    git tag v0.2.0
    git push origin v0.2.0
    ```
4.  **Verification:** Monitor the "Actions" tab on GitHub. The "Release Watcher" workflow will build the Go daemon, the Flutter macOS app, bundle them, and create a new GitHub Release with the `.app.zip` attached.

## Local/Manual Release

If you need to build a release build locally for testing:

1.  **Update Dependencies:**
    ```bash
    make update-bd
    flutter pub get
    ```
2.  **Build and Install:**
    ```bash
    make build
    # Or to install to /Applications via symlink
    make install
    ```
3.  **Manual Bundling:**
    To create a standalone `.app` bundle manually:
    - Run `flutter build macos --release`.
    - Build the daemon: `cd daemon && CGO_ENABLED=1 go build -o watcher-daemon main.go`.
    - Copy the daemon to `build/macos/Build/Products/Release/Watcher.app/Contents/Resources/`.
    - Re-sign: `codesign --force --deep --sign - build/macos/Build/Products/Release/Watcher.app`.

## Dependency Updates

To update the embedded `beads` dependency to the latest upstream release:
```bash
make update-bd
```
This will pull the latest stable version from GitHub and update `daemon/go.mod`.
