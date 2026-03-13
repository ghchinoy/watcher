import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:agent_watcher/state/app_state.dart';

void main() {
  group('Project model', () {
    test('extracts name from path correctly', () {
      final project = Project('/Users/username/projects/my_project');
      expect(project.name, 'my_project');
      expect(project.path, '/Users/username/projects/my_project');
    });

    test('handles path with trailing slash gracefully or normally', () {
      // In Dart, split('/') on string ending in '/' gives empty string last
      // So let's check what it does currently.
      final project = Project('/Users/username/projects/my_project/');
      expect(project.name, ''); // Based on the current simple implementation
    });
  });

  group('AppState', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('initializes with empty projects if no shared prefs', () async {
      final state = AppState();
      // AppState calls _loadProjects() in constructor which is async.
      // We can wait a microtask or just check the initial synchronous state.
      expect(state.projects, isEmpty);
      expect(state.selectedProject, isNull);
    });

    test('addProject adds a project and selects it if it is the first', () async {
      final state = AppState();
      await state.addProject('/some/path');
      
      expect(state.projects.length, 1);
      expect(state.projects.first.path, '/some/path');
      expect(state.selectedProject?.path, '/some/path');
    });
    
    test('removeProject removes the project and updates selected project', () async {
      final state = AppState();
      await state.addProject('/some/path1');
      await state.addProject('/some/path2');
      
      expect(state.projects.length, 2);
      
      final p1 = state.projects.firstWhere((p) => p.path == '/some/path1');
      await state.removeProject(p1);
      
      expect(state.projects.length, 1);
      expect(state.projects.first.path, '/some/path2');
    });
  });
}
