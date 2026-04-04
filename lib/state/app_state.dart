import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../models/issue.dart';
import '../models/interaction.dart';
import '../services/beads_service.dart';

class Project {
  final String path;
  final String name;
  String? tmuxSessionName;

  Project(this.path, {this.tmuxSessionName}) : name = path.split('/').last;

  // Helper to get effective session name
  String get effectiveTmuxSessionName {
    if (tmuxSessionName != null && tmuxSessionName!.isNotEmpty) {
      return tmuxSessionName!;
    }
    // Default safe deterministic name based on project name
    return "watcher_${name.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')}";
  }
}

class AppState extends ChangeNotifier {
  List<Project> projects = [];
  Project? selectedProject;

  List<Issue> currentIssues = [];
  List<GraphNode> currentGraph = [];
  List<Interaction> currentInteractions = [];
  List<Map<String, String>> currentPeers = [];
  Issue? selectedIssue;
  List<Map<String, dynamic>> selectedIssueComments = [];
  String? daemonVersion;
  String? cliVersion;
  String? upstreamVersion;
  String? projectRequiredVersion;
  String? appVersion;

  bool isLoading = false;
  bool isRefreshing = false;

  // Track errors per project path so the sidebar icon persists
  Map<String, String> projectErrors = {};

  // Track expanded nodes in the tree view per project
  Set<String> expandedNodes = {};

  // Track the last time a project was selected to calculate "unread" badges
  Map<String, DateTime> projectLastViewed = {};

  String? get error =>
      selectedProject != null ? projectErrors[selectedProject!.path] : null;

  StreamSubscription<FileSystemEvent>? _watchSubscription;
  final Map<String, StreamSubscription<FileSystemEvent>> _globalWatchers = {};
  Timer? _debounceTimer;
  Timer? _syncTimer;
  BeadsService? _currentService;
  BeadsService? get currentService => _currentService;
  
  int syncIntervalMinutes = 5; // Default to 5 minutes. 0 means disabled.
  String actorName = 'Watcher UI'; // Default identity
  String preferredTerminal = 'Ghostty'; // Default to Ghostty
  String? ghosttyTheme;
  String? ghosttyFontFamily;

  AppState() {
    _loadSettings();
    _loadProjects();
  }

  Future<void> _loadSettings() async {
    final packageInfo = await PackageInfo.fromPlatform();
    appVersion = '${packageInfo.version}+${packageInfo.buildNumber}';

    final prefs = await SharedPreferences.getInstance();
    syncIntervalMinutes = prefs.getInt('sync_interval_minutes') ?? 5;
    preferredTerminal = prefs.getString('preferred_terminal') ?? 'Ghostty';
    ghosttyTheme = prefs.getString('ghostty_theme');
    ghosttyFontFamily = prefs.getString('ghostty_font_family');
    
    // Load last viewed timestamps
    final lastViewedStrings = prefs.getStringList('project_last_viewed') ?? [];
    for (final str in lastViewedStrings) {
      final parts = str.split('|||');
      if (parts.length == 2) {
        projectLastViewed[parts[0]] = DateTime.parse(parts[1]);
      }
    }

    // Load saved actor name, or try to get git username as a fallback
    String? savedActor = prefs.getString('actor_name');
    if (savedActor != null && savedActor.isNotEmpty) {
      actorName = savedActor;
    } else {
      try {
        final result = await Process.run('git', ['config', 'user.name']);
        if (result.exitCode == 0 && result.stdout.toString().trim().isNotEmpty) {
          actorName = result.stdout.toString().trim();
        }
      } catch (_) {
        // Fallback to Watcher UI if git fails
      }
    }
    notifyListeners();
  }

  Future<void> setActorName(String name) async {
    actorName = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('actor_name', name);
    notifyListeners();
  }

  Future<void> setPreferredTerminal(String terminal) async {
    preferredTerminal = terminal;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('preferred_terminal', terminal);
    notifyListeners();
  }

  Future<void> setGhosttyTheme(String? theme) async {
    ghosttyTheme = theme;
    final prefs = await SharedPreferences.getInstance();
    if (theme != null && theme.isNotEmpty) {
      await prefs.setString('ghostty_theme', theme);
    } else {
      await prefs.remove('ghostty_theme');
    }
    notifyListeners();
  }

  Future<void> setGhosttyFontFamily(String? fontFamily) async {
    ghosttyFontFamily = fontFamily;
    final prefs = await SharedPreferences.getInstance();
    if (fontFamily != null && fontFamily.isNotEmpty) {
      await prefs.setString('ghostty_font_family', fontFamily);
    } else {
      await prefs.remove('ghostty_font_family');
    }
    notifyListeners();
  }

  Future<void> setSyncInterval(int minutes) async {
    syncIntervalMinutes = minutes;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('sync_interval_minutes', minutes);
    notifyListeners();
    
    // Restart the timer immediately with the new interval if we are on a federated project
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
    final prefs = await SharedPreferences.getInstance();
    final list =
        prefs.getStringList('expanded_nodes_${selectedProject!.path}') ?? [];
    expandedNodes = list.toSet();
    notifyListeners();
  }

  Future<void> _saveExpandedNodes() async {
    if (selectedProject == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'expanded_nodes_${selectedProject!.path}',
      expandedNodes.toList(),
    );
  }

  Future<void> selectIssue(Issue? issue) async {
    selectedIssue = issue;
    selectedIssueComments = [];
    notifyListeners();

    if (issue != null && _currentService != null) {
      try {
        selectedIssueComments = await _currentService!.getComments(issue.id);
        notifyListeners();
      } catch (e) {
        debugPrint('Failed to fetch comments: $e');
      }
    }
  }

  Future<void> _loadProjects() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Try to load from new JSON format first
    final projectDataList = prefs.getStringList('project_data');
    if (projectDataList != null) {
      projects = projectDataList.map((data) {
        try {
          final map = jsonDecode(data);
          return Project(map['path'], tmuxSessionName: map['tmuxSessionName']);
        } catch (_) {
          return Project(data); // Fallback for bad data
        }
      }).toList();
    } else {
      // Fallback to old string paths
      final paths = prefs.getStringList('project_paths') ?? [];
      projects = paths.map((p) => Project(p)).toList();
    }

    if (projects.isNotEmpty) {
      selectProject(projects.first);
    } else {
      notifyListeners();
    }
    _setupGlobalWatchers();
  }

  Future<void> _saveProjects() async {
    final prefs = await SharedPreferences.getInstance();
    final projectDataList = projects.map((p) => jsonEncode({
      'path': p.path,
      'tmuxSessionName': p.tmuxSessionName,
    })).toList();
    await prefs.setStringList('project_data', projectDataList);
    // Also save simple paths for backwards compatibility / safety
    await prefs.setStringList('project_paths', projects.map((p) => p.path).toList());
  }

  void _setupGlobalWatchers() {
    for (var sub in _globalWatchers.values) {
      sub.cancel();
    }
    _globalWatchers.clear();

    for (final project in projects) {
      final backupDir = Directory('${project.path}/.beads/backup');
      if (backupDir.existsSync()) {
        _globalWatchers[project.path] = backupDir.watch(recursive: true).listen((event) {
          // If this is NOT the currently selected project, notify listeners
          // so the sidebar can re-render and check the lastModified timestamps for the blue dot.
          if (selectedProject?.path != project.path) {
            notifyListeners();
          }
        });
      }
    }
  }

  Future<void> addProject(String path) async {
    if (projects.any((p) => p.path == path)) return;

    projects.add(Project(path));
    await _saveProjects();

    if (selectedProject == null) {
      selectProject(projects.last);
    }
  }

  Future<void> reorderProjects(int oldIndex, int newIndex, {bool isAdjusted = false}) async {
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

  Future<void> removeProject(Project project) async {
  projects.remove(project);
  projectErrors.remove(project.path);
  await _saveProjects();

  _globalWatchers[project.path]?.cancel();
  _globalWatchers.remove(project.path);

  if (selectedProject == project) {
    if (projects.isNotEmpty) {
      selectProject(projects.first);
    } else {
      selectedProject = null;
      currentIssues = [];
      currentGraph = [];
      currentInteractions = [];
      currentPeers = [];
      _currentService?.dispose();
      _currentService = null;
      notifyListeners();
    }
  } else {
    notifyListeners();
  }
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

  Future<void> setProjectTmuxSessionName(Project project, String? sessionName) async {
    project.tmuxSessionName = sessionName;
    await _saveProjects();
    notifyListeners();
  }

  Future<void> selectProject(Project project) async {
    _currentService?.dispose();
    _currentService = null;
    _syncTimer?.cancel();
    
    selectedProject = project;
    isLoading = true;
    projectErrors.remove(project.path);

    projectLastViewed[project.path] = DateTime.now();
    _saveLastViewed();

    notifyListeners();

    await _loadExpandedNodes();
    _setupWatcher(project.path);

    try {
      _currentService = BeadsService(project.path);
      
      // Fetch daemon and CLI versions explicitly on first load
      daemonVersion = await _currentService!.getVersion();
      cliVersion = await _currentService!.getCliVersion();
      projectRequiredVersion = await _currentService!.getProjectRequiredVersion();
      _checkUpstreamVersion();

      currentIssues = await _currentService!.getIssues();
      currentGraph = await _currentService!.getGraph();
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
    final prefs = await SharedPreferences.getInstance();
    final list = projectLastViewed.entries.map((e) => '${e.key}|||${e.value.toIso8601String()}').toList();
    await prefs.setStringList('project_last_viewed', list);
  }

  void _startSyncTimer() {
    _syncTimer?.cancel();
    if (syncIntervalMinutes <= 0) return; // Disabled

    _syncTimer = Timer.periodic(Duration(minutes: syncIntervalMinutes), (_) {
      syncPeer();
    });
  }

  void _setupWatcher(String projectPath) {
    _watchSubscription?.cancel();
    // We specifically watch the backup folder to avoid the massive I/O noise
    // generated by the Dolt SQL server writing to .beads/dolt/.
    // The bd CLI reliably flushes state to the backup folder after every mutation.
    final backupDir = Directory('$projectPath/.beads/backup');
    if (backupDir.existsSync()) {
      _watchSubscription = backupDir.watch(recursive: true).listen((event) {
        if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
        _debounceTimer = Timer(const Duration(milliseconds: 100), () {
          _refreshData();
        });
      });
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
      debugPrint('Failed to add comment: $e');
    }
  }

  Future<void> updateIssue(String id, {String? status, int? priority, String? owner, String? assignee}) async {
    if (selectedProject == null) return;

    // Optimistically update the selected issue if it matches
    if (selectedIssue?.id == id) {
      // Create a copy with the new values
      // Note: we can't easily construct a new Issue without all properties,
      // but since we only need UI to be snappy, we'll let the watcher handle it,
      // or we can set a flag. Actually, letting the watcher handle it is fine since it's 500ms.
      // But for maximum responsiveness, let's just wait for the file watcher.
    }

    try {
      if (_currentService != null) {
        await _currentService!.updateIssue(
          id, 
          status: status,
          priority: priority,
          owner: owner,
          assignee: assignee,
          actor: actorName,
          );      }
    } catch (e) {
      projectErrors[selectedProject!.path] = 'Failed to update issue: $e';
      notifyListeners();
    }
  }

  Future<void> createIssue(String title, String description, String type, {String? parent, int? priority}) async {
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

  Future<void> _refreshData() async {
    if (selectedProject == null) return;
    final projectPath = selectedProject!.path;

    isRefreshing = true;
    notifyListeners();

    try {
      final newIssues = await _currentService!.getIssues();
      final newGraph = await _currentService!.getGraph();
      final newInteractions = await _currentService!.getInteractions();
      final newPeers = await _currentService!.getPeers();

      currentIssues = newIssues;
      currentGraph = newGraph;
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

  @override
  void dispose() {
    _watchSubscription?.cancel();
    for (var sub in _globalWatchers.values) {
      sub.cancel();
    }
    _globalWatchers.clear();
    _debounceTimer?.cancel();
    _syncTimer?.cancel();
    _currentService?.dispose();
    super.dispose();
  }

  Future<void> _checkUpstreamVersion() async {
    try {
      final response = await http.get(Uri.parse('https://api.github.com/repos/steveyegge/beads/releases/latest'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        upstreamVersion = data['tag_name'] as String?;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Failed to fetch upstream version: $e');
    }
  }
}
