import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../models/issue.dart';
import '../utils/app_logger.dart';
import '../models/interaction.dart';
import '../services/beads_service.dart';
import '../services/generative_ai_service.dart';
import '../services/tmux_service.dart';
import 'settings_repository.dart';
import 'project_repository.dart';
import 'watcher_coordinator.dart';

export 'settings_repository.dart' show GenerativeModelConfig, SidebarSortOrder;
export 'project_repository.dart' show Project;

/// Outcome of an issue mutation (RACE-03 / REL-01).
enum MutationResult {
  /// The change was applied.
  success,

  /// Rejected because the issue changed since it was loaded (optimistic
  /// concurrency). The UI should tell the user their edit was discarded; the
  /// data has already been refreshed.
  conflict,

  /// A generic failure (daemon error, timeout, etc.).
  failure,
}

class AppState extends ChangeNotifier {
  List<Project> projects = [];
  Project? selectedProject;
  SidebarSortOrder sidebarSortOrder = SidebarSortOrder.alphabetical;

  List<GenerativeModelConfig> aiModels = [];
  String? defaultAiModelId;

  List<Issue> currentIssues = [];
  List<Interaction> currentInteractions = [];
  List<Map<String, String>> currentPeers = [];
  Issue? selectedIssue;
  List<Map<String, dynamic>> selectedIssueComments = [];
  String? daemonVersion;
  String? cliVersion;
  String? upstreamVersion;
  String? projectRequiredVersion;
  String? appVersion;
  String? currentConnectionMode;

  bool isLoading = false;
  bool isRefreshing = false;

  /// REL-05: true while the daemon has crashed and we are auto-reconnecting.
  /// The UI can show a transient "Reconnecting…" banner instead of a hard error.
  bool daemonReconnecting = false;

  // RACE-02: re-entrancy guard for _refreshData. Multiple concurrent triggers
  // (file-watcher debounce, heartbeat timer, sync timer, UI actions) must not
  // flood the IPC pipe. `_refreshInFlight` serializes them; `_refreshQueued`
  // records a request that arrived mid-refresh so we re-run EXACTLY ONCE at the
  // end (trailing edge) — this coalesces bursts without dropping the latest
  // change (a naive early-return would lose in-flight file-watcher events).
  bool _refreshInFlight = false;
  bool _refreshQueued = false;

  // Track errors per project path so the sidebar icon persists
  Map<String, String> projectErrors = {};

  // Track expanded nodes in the tree view per project
  Set<String> expandedNodes = {};

  // Track the last time a project was selected to calculate "unread" badges
  Map<String, DateTime> projectLastViewed = {};

  String? get error =>
      selectedProject != null ? projectErrors[selectedProject!.path] : null;

  late final WatcherCoordinator _watcher;
  BeadsService? _currentService;
  BeadsService? get currentService => _currentService;

  @visibleForTesting
  set currentServiceForTesting(BeadsService? service) =>
      _currentService = service;

  int syncIntervalMinutes = 5; // Default to 5 minutes. 0 means disabled.
  int heartbeatIntervalSeconds =
      30; // Default to 30 seconds safety heartbeat. 0 means disabled.
  String actorName = 'Watcher UI'; // Default identity
  String preferredTerminal = 'Ghostty'; // Default to Ghostty
  String? ghosttyTheme;
  String? ghosttyFontFamily;

  bool showClosedInTree = false;
  String customBdPath = '';

  GenerativeModelConfig? get defaultAiModel {
    if (defaultAiModelId == null || aiModels.isEmpty) return null;
    return aiModels.firstWhere(
      (m) => m.id == defaultAiModelId,
      orElse: () => aiModels.first,
    );
  }

  // Vertex AI Settings
  String? gcpProjectId;

  static final _log = AppLogger('AppState');

  final _settingsRepo = SettingsRepository();
  final _projectRepo = ProjectRepository();

  AppState() {
    _watcher = WatcherCoordinator(
      onRefreshNeeded: _refreshData,
      onSyncNeeded: syncPeer,
      onNonSelectedProjectChanged: (_) => notifyListeners(),
    );
    _loadSettings();
    _loadProjects();
  }

  void _startHeartbeat() {
    _watcher.startHeartbeat(heartbeatIntervalSeconds);
  }

  Future<void> refreshActiveProject() async {
    await _refreshData();
  }

  Future<HealthCheckResult> checkHealth() async {
    if (_currentService == null) {
      throw Exception('No project selected');
    }
    return await _currentService!.checkHealth();
  }

  Future<void> _loadSettings() async {
    final settings = await _settingsRepo.load();
    appVersion = settings.appVersion;
    syncIntervalMinutes = settings.syncIntervalMinutes;
    heartbeatIntervalSeconds = settings.heartbeatIntervalSeconds;
    preferredTerminal = settings.preferredTerminal;
    ghosttyTheme = settings.ghosttyTheme;
    ghosttyFontFamily = settings.ghosttyFontFamily;
    showClosedInTree = settings.showClosedInTree;
    customBdPath = settings.customBdPath;
    sidebarSortOrder = settings.sidebarSortOrder;
    gcpProjectId = settings.gcpProjectId;
    aiModels = settings.aiModels;
    defaultAiModelId = settings.defaultAiModelId;
    actorName = settings.actorName;
    projectLastViewed = settings.projectLastViewed;
    _startHeartbeat();
    notifyListeners();
  }

  Future<void> setHeartbeatInterval(int seconds) async {
    heartbeatIntervalSeconds = seconds;
    await _settingsRepo.saveHeartbeatInterval(seconds);
    notifyListeners();
    _startHeartbeat();
  }

  Future<void> setActorName(String name) async {
    actorName = name;
    await _settingsRepo.saveActorName(name);
    notifyListeners();
  }

  Future<void> setPreferredTerminal(String terminal) async {
    preferredTerminal = terminal;
    await _settingsRepo.savePreferredTerminal(terminal);
    notifyListeners();
  }

  Future<void> setGhosttyTheme(String? theme) async {
    ghosttyTheme = theme;
    await _settingsRepo.saveGhosttyTheme(theme);
    notifyListeners();
  }

  Future<void> setGhosttyFontFamily(String? fontFamily) async {
    ghosttyFontFamily = fontFamily;
    await _settingsRepo.saveGhosttyFontFamily(fontFamily);
    notifyListeners();
  }

  Future<void> toggleShowClosedInTree() async {
    showClosedInTree = !showClosedInTree;
    await _settingsRepo.saveShowClosedInTree(showClosedInTree);
    notifyListeners();
  }

  Future<void> setCustomBdPath(String path) async {
    customBdPath = path;
    await _settingsRepo.saveCustomBdPath(path);
    notifyListeners();
  }

  Future<void> setGcpProjectId(String? projectId) async {
    gcpProjectId = projectId;
    await _settingsRepo.saveGcpProjectId(projectId);
    notifyListeners();
  }

  Future<void> setSyncInterval(int minutes) async {
    syncIntervalMinutes = minutes;
    await _settingsRepo.saveSyncInterval(minutes);
    notifyListeners();
    if (selectedProject != null && currentPeers.isNotEmpty) {
      _startSyncTimer();
    }
  }

  bool isNodeExpanded(String issueId) {
    return expandedNodes.contains(issueId);
  }

  Future<void> toggleNodeExpansion(String issueId, bool isExpanded) async {
    if (isExpanded) {
      expandedNodes.add(issueId);
    } else {
      expandedNodes.remove(issueId);
    }
    notifyListeners();
    _saveExpandedNodes();
  }

  Future<void> setAllNodesExpanded(
    bool expanded,
    List<String> allIssueIds,
  ) async {
    if (expanded) {
      expandedNodes.addAll(allIssueIds);
    } else {
      expandedNodes.clear();
    }
    notifyListeners();
    _saveExpandedNodes();
  }

  Future<void> _loadExpandedNodes() async {
    if (selectedProject == null) return;
    expandedNodes = await _settingsRepo.loadExpandedNodes(
      selectedProject!.path,
    );
    notifyListeners();
  }

  Future<void> _saveExpandedNodes() async {
    if (selectedProject == null) return;
    await _settingsRepo.saveExpandedNodes(selectedProject!.path, expandedNodes);
  }

  List<String> getAncestorIds(Issue issue) {
    final ancestors = <String>[];
    Issue? current = issue;
    final visited = <String>{issue.id};

    while (current != null) {
      String? parentId;
      final hasExplicit =
          current.dependencies?.any((d) => d.type == 'parent-child') ?? false;
      if (hasExplicit) {
        parentId = current.dependencies!
            .firstWhere((d) => d.type == 'parent-child')
            .dependsOnId;
      } else {
        final lastDotIndex = current.id.lastIndexOf('.');
        if (lastDotIndex != -1) {
          parentId = current.id.substring(0, lastDotIndex);
        }
      }

      if (parentId == null || visited.contains(parentId)) break;

      visited.add(parentId);
      ancestors.add(parentId);
      final parentIdx = currentIssues.indexWhere((i) => i.id == parentId);
      current = parentIdx != -1 ? currentIssues[parentIdx] : null;
    }
    return ancestors;
  }

  Future<void> selectIssue(Issue? issue) async {
    selectedIssue = issue;
    selectedIssueComments = [];

    if (issue != null) {
      final ancestors = getAncestorIds(issue);
      if (ancestors.isNotEmpty) {
        expandedNodes.addAll(ancestors);
        await _saveExpandedNodes();
      }
    }

    notifyListeners();

    if (issue != null && _currentService != null) {
      try {
        selectedIssueComments = await _currentService!.getComments(issue.id);
        notifyListeners();
      } catch (e) {
        _log.warning('Failed to fetch comments for ${issue.id}', error: e);
      }
    }
  }

  Future<void> _loadProjects() async {
    projects = await _projectRepo.load();
    if (projects.isNotEmpty) {
      final lastSelectedPath = await _settingsRepo.loadLastSelectedProject();
      final lastProject = projects.firstWhere(
        (p) => p.path == lastSelectedPath,
        orElse: () => projects.first,
      );
      selectProject(lastProject);
    } else {
      notifyListeners();
    }
    _setupGlobalWatchers();
  }

  Future<void> _saveProjects() async {
    await _projectRepo.save(projects);
  }

  void _setupGlobalWatchers() {
    _watcher.setupGlobalWatchers(projects);
  }

  Future<void> addProject(String path) async {
    if (projects.any((p) => p.path == path)) return;

    projects.add(Project(path));
    await _saveProjects();

    _setupGlobalWatchers(); // Update watchers to include new project

    // Always navigate to the newly added project so the UI reflects it
    // immediately, regardless of whether another project was previously open.
    selectProject(projects.last);
  }

  Future<void> reorderProjects(
    int oldIndex,
    int newIndex, {
    bool isAdjusted = false,
  }) async {
    if (oldIndex < 0 ||
        oldIndex >= projects.length ||
        newIndex < 0 ||
        newIndex > projects.length) {
      return;
    }

    if (!isAdjusted && oldIndex < newIndex) {
      newIndex -= 1;
    }

    final project = projects.removeAt(oldIndex);
    projects.insert(newIndex, project);

    await _saveProjects();

    notifyListeners();
  }

  Future<void> _saveAiModels() async {
    await _settingsRepo.saveAiModels(aiModels, defaultAiModelId);
  }

  Future<void> addAiModel(GenerativeModelConfig model) async {
    aiModels.add(model);
    defaultAiModelId ??= model.id;
    await _saveAiModels();
    notifyListeners();
  }

  Future<void> removeAiModel(String id) async {
    aiModels.removeWhere((m) => m.id == id);
    if (defaultAiModelId == id) {
      defaultAiModelId = aiModels.isNotEmpty ? aiModels.first.id : null;
    }
    await _saveAiModels();
    notifyListeners();
  }

  Future<void> setDefaultAiModel(String id) async {
    defaultAiModelId = id;
    await _saveAiModels();
    notifyListeners();
  }

  /// Removes a project. Returns `true` on success, `false` if persistence
  /// failed. REL-01: previously this swallowed a failed [_saveProjects] and the
  /// removal would silently reappear on next launch.
  Future<bool> removeProject(Project project) async {
    // Snapshot for rollback if persistence fails.
    final index = projects.indexOf(project);
    projects.remove(project);
    final savedError = projectErrors.remove(project.path);

    try {
      await _saveProjects();
    } catch (e) {
      // Roll back the in-memory removal so UI and persisted state stay in sync.
      if (index >= 0 && !projects.contains(project)) {
        projects.insert(index, project);
      }
      if (savedError != null) projectErrors[project.path] = savedError;
      projectErrors[project.path] = 'Failed to remove project: $e';
      notifyListeners();
      return false;
    }

    _watcher.cancelGlobalWatcher(project.path);

    if (selectedProject == project) {
      if (projects.isNotEmpty) {
        selectProject(projects.first);
      } else {
        selectedProject = null;
        currentIssues = [];
        currentInteractions = [];
        currentPeers = [];
        _currentService?.dispose();
        _currentService = null;
        notifyListeners();
      }
    } else {
      notifyListeners();
    }
    return true;
  }

  bool hasUnreadActivity(Project project) {
    if (selectedProject?.path == project.path) return false;

    final lastViewed = projectLastViewed[project.path];
    if (lastViewed == null) return false;

    final file = File('${project.path}/.beads/backup/events.jsonl');
    if (file.existsSync()) {
      final lastModified = file.lastModifiedSync();
      return lastModified.isAfter(lastViewed);
    }
    return false;
  }

  String? getProjectLastActivity(Project project) {
    final file = File('${project.path}/.beads/backup/events.jsonl');
    if (!file.existsSync()) return null;

    final lastModified = file.lastModifiedSync();
    final difference = DateTime.now().difference(lastModified);

    if (difference.inMinutes < 1) {
      return 'now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h';
    } else if (difference.inDays < 30) {
      return '${difference.inDays}d';
    }
    return null; // Don't show anything for very old projects
  }

  List<Project> get sortedProjects {
    final list = List<Project>.from(projects);
    if (sidebarSortOrder == SidebarSortOrder.alphabetical) {
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } else {
      list.sort((a, b) {
        final fileA = File('${a.path}/.beads/backup/events.jsonl');
        final fileB = File('${b.path}/.beads/backup/events.jsonl');
        final timeA = fileA.existsSync()
            ? fileA.lastModifiedSync()
            : DateTime(1970);
        final timeB = fileB.existsSync()
            ? fileB.lastModifiedSync()
            : DateTime(1970);
        return timeB.compareTo(timeA); // Newest first
      });
    }
    return list;
  }

  Future<void> setSidebarSortOrder(SidebarSortOrder order) async {
    sidebarSortOrder = order;
    await _settingsRepo.saveSidebarSortOrder(order);
    notifyListeners();
  }

  Future<void> setProjectTmuxSessionName(
    Project project,
    String? sessionName,
  ) async {
    project.tmuxSessionName = sessionName;
    await _saveProjects();
    notifyListeners();
  }

  Future<void> selectProject(Project project) async {
    _currentService?.dispose();
    _currentService = null;
    _watcher.stopSyncTimer();

    selectedProject = project;
    await _settingsRepo.saveLastSelectedProject(project.path);
    isLoading = true;
    currentConnectionMode = null;
    projectErrors.remove(project.path);

    projectLastViewed[project.path] = DateTime.now();
    _saveLastViewed();

    notifyListeners();

    await _loadExpandedNodes();
    _setupWatcher(project.path);

    try {
      _currentService = BeadsService(
        project.path,
        onModeChanged: (mode) {
          currentConnectionMode = mode;
          notifyListeners();
        },
        onCrash: (code, {required bool wasKilled}) {
          _handleDaemonCrash(project.path, code, wasKilled: wasKilled);
        },
        bdPathResolver: () => customBdPath.isNotEmpty ? customBdPath : 'bd',
      );

      // Fetch daemon and CLI versions explicitly on first load
      daemonVersion = await _currentService!.getVersion();
      cliVersion = await _currentService!.getCliVersion();
      projectRequiredVersion = await _currentService!
          .getProjectRequiredVersion();
      _checkUpstreamVersion();

      currentIssues = await _currentService!.getIssues();
      currentInteractions = await _currentService!.getInteractions();
      currentPeers = await _currentService!.getPeers();

      if (currentPeers.isNotEmpty) {
        _startSyncTimer();
      }

      // By default, if nodes haven't been saved before, maybe we want to expand them all?
      // Actually, if expandedNodes is empty, we can populate it with all nodes that have children if we want them expanded by default.
      // But let's keep it simple: if it's completely empty, maybe it's the first run, but we don't know for sure.
    } catch (e) {
      projectErrors[project.path] = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _saveLastViewed() async {
    await _settingsRepo.saveProjectLastViewed(projectLastViewed);
  }

  void _startSyncTimer() {
    _watcher.startSyncTimer(syncIntervalMinutes);
  }

  void _setupWatcher(String projectPath) {
    _watcher.watchProject(projectPath);
  }

  Future<void> addDependency(
    String issueId,
    String dependsOn,
    String type,
  ) async {
    if (_currentService == null || selectedProject == null) return;
    try {
      await _currentService!.addDependency(
        issueId,
        dependsOn,
        type,
        actor: actorName,
      );
      await _refreshData();
    } catch (e) {
      projectErrors[selectedProject!.path] = 'Failed to add dependency: $e';
      notifyListeners();
    }
  }

  Future<void> removeDependency(String issueId, String dependsOn) async {
    if (_currentService == null || selectedProject == null) return;
    try {
      await _currentService!.removeDependency(
        issueId,
        dependsOn,
        actor: actorName,
      );
      await _refreshData();
    } catch (e) {
      projectErrors[selectedProject!.path] = 'Failed to remove dependency: $e';
      notifyListeners();
    }
  }

  Future<void> addComment(String issueId, String text) async {
    if (_currentService == null) return;
    try {
      await _currentService!.addComment(issueId, text, actor: actorName);
      // Immediately refresh comments to show the new one
      selectedIssueComments = await _currentService!.getComments(issueId);
      notifyListeners();
    } catch (e) {
      _log.warning('Failed to add comment to $issueId', error: e);
    }
  }

  /// Updates an issue.
  ///
  /// RACE-03: passes the issue's current `updatedAt` as an optimistic-concurrency
  /// token. If the issue was changed by someone else in the meantime the daemon
  /// rejects the write; we auto-refresh and return [MutationResult.conflict] so
  /// the UI can tell the user their edit was discarded.
  /// REL-01: returns [MutationResult.failure] on generic errors (also recorded
  /// in [projectErrors] for the sidebar indicator); [MutationResult.success]
  /// otherwise.
  Future<MutationResult> updateIssue(
    String id, {
    String? status,
    int? priority,
    String? owner,
    String? assignee,
    String? parent,
  }) async {
    if (selectedProject == null) return MutationResult.failure;
    if (_currentService == null) return MutationResult.failure;

    // RACE-03: the updated_at the UI currently sees for this issue.
    final known = currentIssues.where((i) => i.id == id).firstOrNull;
    final expectedUpdatedAt = known?.updatedAt;

    try {
      await _currentService!.updateIssue(
        id,
        status: status,
        priority: priority,
        owner: owner,
        assignee: assignee,
        parent: parent,
        actor: actorName,
        expectedUpdatedAt: expectedUpdatedAt,
      );

      // If closing, trigger background summarization (Task watcher-v2n.4 / b2n.2)
      if (status == 'closed') {
        final issue = currentIssues.where((i) => i.id == id).firstOrNull;
        if (issue != null) {
          _summarizeResolution(issue);
        }
      }
      return MutationResult.success;
    } on ConflictException catch (e) {
      // RACE-03: someone changed this issue first. Discard this edit and refresh
      // so the user sees the current values.
      _log.info('Update conflict on $id: $e');
      await _refreshData();
      return MutationResult.conflict;
    } catch (e) {
      projectErrors[selectedProject!.path] = 'Failed to update issue: $e';
      notifyListeners();
      return MutationResult.failure;
    }
  }

  Future<void> _summarizeResolution(Issue issue) async {
    try {
      final comments = await _currentService!.getComments(issue.id);
      final summary = await GenerativeAiService.summarizeIssueResolution(
        gcpProjectId: gcpProjectId,
        defaultAiModel: defaultAiModel,
        issue: issue,
        comments: comments,
      );

      if (summary != null && summary.isNotEmpty) {
        await addComment(issue.id, '🤖 **Resolution Summary:**\n$summary');
      }
    } catch (e) {
      _log.warning('Background summarization failed for ${issue.id}', error: e);
    }
  }

  Future<void> createIssue(
    String title,
    String description,
    String type, {
    String? parent,
    int? priority,
  }) async {
    if (_currentService == null || selectedProject == null) return;
    try {
      await _currentService!.createIssue(
        title,
        description,
        type,
        parent: parent,
        priority: priority,
        actor: actorName,
      );
      // Wait a moment before refreshing to allow the daemon to process the export
      await Future.delayed(const Duration(milliseconds: 500));
      await _refreshData();
    } catch (e) {
      projectErrors[selectedProject!.path] = 'Failed to create issue: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// Public/observable refresh entry point with trailing-edge coalescing
  /// (RACE-02). If a refresh is already running, this records a pending re-run
  /// and returns immediately; the in-flight refresh will loop once more when it
  /// finishes so the newest data is always picked up.
  Future<void> _refreshData() async {
    if (_refreshInFlight) {
      _refreshQueued = true;
      return;
    }

    _refreshInFlight = true;
    try {
      do {
        _refreshQueued = false;
        await _performRefresh();
      } while (_refreshQueued);
    } finally {
      _refreshInFlight = false;
    }
  }

  @visibleForTesting
  Future<void> refreshDataForTesting() => _refreshData();

  Future<void> _performRefresh() async {
    if (selectedProject == null) return;
    final projectPath = selectedProject!.path;

    isRefreshing = true;
    notifyListeners();

    try {
      final newIssues = await _currentService!.getIssues();
      final newInteractions = await _currentService!.getInteractions();
      final newPeers = await _currentService!.getPeers();

      currentIssues = newIssues;
      currentInteractions = newInteractions;
      currentPeers = newPeers;
      projectErrors.remove(projectPath);

      projectLastViewed[projectPath] = DateTime.now();
      _saveLastViewed();
    } catch (e) {
      projectErrors[projectPath] = e.toString();
    } finally {
      isRefreshing = false;
      notifyListeners();
    }
  }

  /// REL-05: recover from an unexpected daemon exit (e.g. SIGKILL/-9 from OS
  /// memory pressure or a sleep transition). Rather than surfacing a raw crash,
  /// mark the UI as reconnecting and re-fetch — [_refreshData] -> [getIssues]
  /// transparently respawns the daemon via BeadsService._ensureDaemonRunning.
  /// Retries a few times with backoff; on repeated failure leaves a clear error.
  Future<void> _handleDaemonCrash(
    String projectPath,
    int code, {
    required bool wasKilled,
  }) async {
    // Ignore stale crashes from a project the user already navigated away from.
    if (selectedProject?.path != projectPath) return;
    // If a recovery is already running, let it continue.
    if (daemonReconnecting) return;

    _log.warning(
      'Daemon crashed (exit $code, wasKilled=$wasKilled); attempting recovery.',
    );
    daemonReconnecting = true;
    // Clear any raw crash error so the banner shows "reconnecting" instead.
    projectErrors.remove(projectPath);
    notifyListeners();

    const maxAttempts = 3;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      // Brief backoff so the OS/Dolt lock settles before respawning.
      await Future.delayed(Duration(milliseconds: 300 * attempt));

      // Bail if the user switched projects or the service was torn down.
      if (selectedProject?.path != projectPath || _currentService == null) {
        daemonReconnecting = false;
        notifyListeners();
        return;
      }

      try {
        await _refreshData(); // respawns the daemon on the next RPC
        if (projectErrors[projectPath] == null) {
          _log.info('Daemon recovered after crash (attempt $attempt).');
          daemonReconnecting = false;
          notifyListeners();
          return;
        }
      } catch (e) {
        _log.warning('Daemon recovery attempt $attempt failed', error: e);
      }
    }

    // Recovery exhausted — surface a clear, actionable error.
    daemonReconnecting = false;
    projectErrors[projectPath] =
        'The background service stopped (exit code $code) and could not be '
        'restarted automatically. Try reselecting the project.';
    notifyListeners();
  }

  Future<void> syncPeer([String? peer]) async {
    if (_currentService == null || selectedProject == null) return;
    try {
      isRefreshing = true;
      notifyListeners();
      await _currentService!.syncPeer(peer);
      await _refreshData(); // triggers notifyListeners and resets isRefreshing
    } catch (e) {
      projectErrors[selectedProject!.path] = 'Failed to sync: $e';
      isRefreshing = false;
      notifyListeners();
    }
  }

  Future<void> addPeer(String name, String url) async {
    if (_currentService == null || selectedProject == null) return;
    try {
      await _currentService!.addPeer(name, url);
      await _refreshData();
    } catch (e) {
      projectErrors[selectedProject!.path] = 'Failed to add peer: $e';
      notifyListeners();
    }
  }

  Future<void> reconnectActiveProject() async {
    if (selectedProject == null) return;
    await selectProject(selectedProject!);
  }

  Future<void> launchDoltServer() async {
    if (selectedProject == null) return;

    final sessionName = "${selectedProject!.effectiveTmuxSessionName}_server";
    try {
      await TmuxService.ensureSession(sessionName, selectedProject!.path);
      await TmuxService.sendKeys(
        sessionName,
        'bd dolt server',
        customBdPath: customBdPath,
      );
      await TmuxService.attachInTerminal(
        sessionName,
        terminalApp: preferredTerminal,
        ghosttyTheme: ghosttyTheme,
        ghosttyFontFamily: ghosttyFontFamily,
        workingDirectory: selectedProject!.path,
      );
    } catch (e) {
      projectErrors[selectedProject!.path] = 'Failed to launch Dolt server: $e';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _watcher.dispose();
    _currentService?.dispose();
    super.dispose();
  }

  Future<void> _checkUpstreamVersion() async {
    try {
      // REL-04 (r1f.10): bound the request so a degraded/offline network can't
      // leak a background socket indefinitely.
      final response = await http
          .get(
            Uri.parse(
              'https://api.github.com/repos/steveyegge/beads/releases/latest',
            ),
          )
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        upstreamVersion = data['tag_name'] as String?;
        notifyListeners();
      }
    } catch (e) {
      _log.info('Failed to fetch upstream beads version', error: e);
    }
  }
}
