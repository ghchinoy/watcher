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
  Issue? selectedIssue;
  
  bool isLoading = false;
  bool isRefreshing = false;
  
  // Track errors per project path so the sidebar icon persists
  Map<String, String> projectErrors = {};
  
  // Track expanded nodes in the tree view per project
  Set<String> expandedNodes = {};

  String? get error => selectedProject != null ? projectErrors[selectedProject!.path] : null;

  StreamSubscription<FileSystemEvent>? _watchSubscription;
  Timer? _debounceTimer;

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

  Future<void> setAllNodesExpanded(bool expanded, List<String> allIssueIds) async {
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
    final list = prefs.getStringList('expanded_nodes_${selectedProject!.path}') ?? [];
    expandedNodes = list.toSet();
    notifyListeners();
  }

  Future<void> _saveExpandedNodes() async {
    if (selectedProject == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('expanded_nodes_${selectedProject!.path}', expandedNodes.toList());
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
    await prefs.setStringList('project_paths', projects.map((p) => p.path).toList());
    notifyListeners();
    
    if (selectedProject == null) {
      selectProject(projects.last);
    }
  }

  Future<void> removeProject(Project project) async {
    projects.remove(project);
    projectErrors.remove(project.path);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('project_paths', projects.map((p) => p.path).toList());
    
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
    selectedProject = project;
    isLoading = true;
    projectErrors.remove(project.path);
    notifyListeners();

    await _loadExpandedNodes();
    _setupWatcher(project.path);

    try {
      final service = BeadsService(project.path);
      currentIssues = await service.getIssues();
      currentGraph = await service.getGraph();
      currentInteractions = await service.getInteractions();
      
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
      final service = BeadsService(selectedProject!.path);
      await service.updateIssue(id, status: status, priority: priority);
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
      final service = BeadsService(projectPath);
      final newIssues = await service.getIssues();
      final newGraph = await service.getGraph();
      final newInteractions = await service.getInteractions();
      
      currentIssues = newIssues;
      currentGraph = newGraph;
      currentInteractions = newInteractions;
      projectErrors.remove(projectPath);
    } catch (e) {
      projectErrors[projectPath] = e.toString();
    } finally {
      isRefreshing = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _watchSubscription?.cancel();
    _debounceTimer?.cancel();
    super.dispose();
  }
}
