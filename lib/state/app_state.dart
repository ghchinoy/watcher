import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/issue.dart';
import '../models/interaction.dart';
import '../services/beads_service.dart';

class Project {
  final String path;
  final String name;

  Project(this.path) : name = path.split('/').last;
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
  
  int syncIntervalMinutes = 5; // Default to 5 minutes. 0 means disabled.
  String actorName = 'Watcher UI'; // Default identity

  AppState() {
    _loadSettings();
    _loadProjects();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    syncIntervalMinutes = prefs.getInt('sync_interval_minutes') ?? 5;
    
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
    final paths = prefs.getStringList('project_paths') ?? [];
    projects = paths.map((p) => Project(p)).toList();
    if (projects.isNotEmpty) {
      selectProject(projects.first);
    } else {
      notifyListeners();
    }
    _setupGlobalWatchers();
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'project_paths',
      projects.map((p) => p.path).toList(),
    );
    notifyListeners();

    if (selectedProject == null) {
      selectProject(projects.last);
    }
  }
Future<void> removeProject(Project project) async {
  projects.remove(project);
  projectErrors.remove(project.path);
  final prefs = await SharedPreferences.getInstance();
  await prefs.setStringList(
    'project_paths',
    projects.map((p) => p.path).toList(),
  );

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
}
