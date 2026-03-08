import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/issue.dart';
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
  Issue? selectedIssue;
  
  bool isLoading = false;
  bool isRefreshing = false;
  
  // Track errors per project path so the sidebar icon persists
  Map<String, String> projectErrors = {};
  
  String? get error => selectedProject != null ? projectErrors[selectedProject!.path] : null;

  StreamSubscription<FileSystemEvent>? _watchSubscription;
  Timer? _debounceTimer;

  AppState() {
    _loadProjects();
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

    _setupWatcher(project.path);

    try {
      final service = BeadsService(project.path);
      currentIssues = await service.getIssues();
      currentGraph = await service.getGraph();
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

  Future<void> _refreshData() async {
    if (selectedProject == null) return;
    final projectPath = selectedProject!.path;
    
    isRefreshing = true;
    notifyListeners();
    
    try {
      final service = BeadsService(projectPath);
      final newIssues = await service.getIssues();
      final newGraph = await service.getGraph();
      
      currentIssues = newIssues;
      currentGraph = newGraph;
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
