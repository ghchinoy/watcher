import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';
import 'screens/home_screen.dart';
import 'screens/project_dashboard.dart';
import 'screens/tree_view_screen.dart';
import 'screens/kanban_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/project_settings_screen.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);
final GlobalKey<NavigatorState> _shellNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'shell',
);

final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/',
  routes: [
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) {
        return HomeScreen(child: child);
      },
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const ProjectDashboard(),
        ),
        GoRoute(
          path: '/tree',
          builder: (context, state) => const TreeViewScreen(),
        ),
        GoRoute(
          path: '/kanban',
          builder: (context, state) => const KanbanScreen(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
        ),
        GoRoute(
          path: '/project/settings',
          builder: (context, state) => const ProjectSettingsScreen(),
        ),
      ],
    ),
  ],
);
