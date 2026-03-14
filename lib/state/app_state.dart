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

  bool isLoading = false;
  bool isRefreshing = false;

  // Track errors per project path so the sidebar icon persists
  Map<String, String> projectErrors = {};

  // Track expanded nodes in the tree view per project
  Set<String> expandedNodes = {};

  String? get error =>
      selectedProject != null ? projectErrors[selectedProject!.path] : null;

  StreamSubscription<FileSystemEvent>? _watchSubscription;
  Timer? _debounceTimer;
  BeadsService? _currentService;

  AppState() {
    _loadProjects();
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

  void selectIssue(Issue? issue) {
    selectedIssue = issue;
    notifyListeners();
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

    if (selectedProject == project) {
      if (projects.isNotEmpty) {
        selectProject(projects.first);
      } else {
        selectedProject = null;
        currentIssues = [];
        currentGraph = [];
        currentInteractions = [];
        _watchSubscription?.cancel();
        notifyListeners();
      }
    } else {
      notifyListeners();
    }
  }

  Future<void> selectProject(Project project) async {
    _currentService?.dispose();
    _currentService = null;
    
    selectedProject = project;
    isLoading = true;
    projectErrors.remove(project.path);
    notifyListeners();

    await _loadExpandedNodes();
    _setupWatcher(project.path);

    try {
      _currentService = BeadsService(project.path);
      currentIssues = await _currentService!.getIssues();
      currentGraph = await _currentService!.getGraph();
      currentInteractions = await _currentService!.getInteractions();
      currentPeers = await _currentService!.getPeers();

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

  void _setupWatcher(String projectPath) {
    _watchSubscription?.cancel();
    final beadsDir = Directory('$projectPath/.beads');
    if (beadsDir.existsSync()) {
      _watchSubscription = beadsDir.watch(recursive: true).listen((event) {
        // Ignore changes to dolt-server.log, locks, and internal noms storage
        // to prevent infinite refresh loops when the DB server is active.
        if (event.path.endsWith('.log') ||
            event.path.endsWith('.lock') ||
            event.path.endsWith('.pid') ||
            event.path.endsWith('.port') ||
            event.path.contains('/.dolt/')) {
          return;
        }

        if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
        _debounceTimer = Timer(const Duration(milliseconds: 500), () {
          _refreshData();
        });
      });
    }
  }

  Future<void> updateIssue(String id, {String? status, int? priority}) async {
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
        await _currentService!.updateIssue(id, status: status, priority: priority);
      }
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
      if (_currentService == null) return;
      final newIssues = await _currentService!.getIssues();
      final newGraph = await _currentService!.getGraph();
      final newInteractions = await _currentService!.getInteractions();
      final newPeers = await _currentService!.getPeers();

      currentIssues = newIssues;
      currentGraph = newGraph;
      currentInteractions = newInteractions;
      currentPeers = newPeers;
      projectErrors.remove(projectPath);
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
    _debounceTimer?.cancel();
    _currentService?.dispose();
    super.dispose();
  }
}
