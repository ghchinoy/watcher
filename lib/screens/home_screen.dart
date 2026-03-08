import 'package:file_selector/file_selector.dart';
import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import '../main.dart';
import '../widgets/issue_inspector.dart';

class HomeScreen extends StatefulWidget {
  final Widget child;

  const HomeScreen({super.key, required this.child});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int get _currentIndex {
    if (appState.projects.isEmpty) return 0;
    if (appState.selectedProject == null) return appState.projects.length;
    final index = appState.projects.indexOf(appState.selectedProject!);
    return index == -1 ? 0 : index;
  }

  void _onItemTapped(int index) {
    if (index < appState.projects.length) {
      appState.selectProject(appState.projects[index]);
    } else {
      _addProject();
    }
  }

  Future<void> _addProject() async {
    final String? directoryPath = await getDirectoryPath();
    if (directoryPath != null) {
      appState.addProject(directoryPath);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        return MacosWindow(
          backgroundColor: const Color(0x00000000), // Transparent to allow vibrancy
          sidebar: Sidebar(
            minWidth: 200,
            builder: (context, scrollController) {
              return SidebarItems(
                currentIndex: _currentIndex,
                onChanged: _onItemTapped,
                scrollController: scrollController,
                items: [
                  const SidebarItem(
                    section: true,
                    label: Text('PROJECTS'),
                  ),
                  ...appState.projects.map((p) {
                    final isSelected = appState.selectedProject == p;
                    final isRefreshing = isSelected && appState.isRefreshing;
                    final hasError = appState.projectErrors.containsKey(p.path);
                    
                    Widget leadingIcon;
                    if (isRefreshing) {
                      leadingIcon = const CupertinoActivityIndicator(radius: 8);
                    } else if (hasError) {
                      leadingIcon = const MacosIcon(CupertinoIcons.exclamationmark_triangle_fill, color: CupertinoColors.systemRed);
                    } else {
                      leadingIcon = MacosIcon(
                        CupertinoIcons.folder,
                        color: isSelected ? null : MacosTheme.of(context).typography.body.color?.withValues(alpha: 0.5),
                      );
                    }

                    return SidebarItem(
                      leading: leadingIcon,
                      label: Text(p.name),
                      unselectedColor: isSelected
                          ? MacosTheme.of(context).primaryColor.withValues(alpha: 0.2)
                          : null,
                      trailing: isSelected
                          ? MacosIconButton(
                              icon: const MacosIcon(CupertinoIcons.clear_circled, size: 14),
                              onPressed: () => appState.removeProject(p),
                              boxConstraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                              padding: EdgeInsets.zero,
                            )
                          : null,
                    );
                  }),
                  const SidebarItem(
                    leading: MacosIcon(CupertinoIcons.add),
                    label: Text('Add Project'),
                  ),
                ],
              );
            },
          ),
          endSidebar: Sidebar(
            startWidth: 300,
            minWidth: 200,
            maxWidth: 400,
            isResizable: true,
            shownByDefault: false,
            builder: (context, scrollController) {
              if (appState.selectedIssue == null) return const SizedBox.shrink();
              return IssueInspector(
                issue: appState.selectedIssue!,
                onClose: () => appState.selectIssue(null),
                scrollController: scrollController,
              );
            },
          ),
          child: _InspectorController(child: widget.child),
        );
      },
    );
  }
}

class _InspectorController extends StatefulWidget {
  final Widget child;

  const _InspectorController({required this.child});

  @override
  State<_InspectorController> createState() => _InspectorControllerState();
}

class _InspectorControllerState extends State<_InspectorController> {
  @override
  void initState() {
    super.initState();
    appState.addListener(_onAppStateChanged);
  }

  @override
  void dispose() {
    appState.removeListener(_onAppStateChanged);
    super.dispose();
  }

  void _onAppStateChanged() {
    if (!mounted) return;
    final scope = MacosWindowScope.maybeOf(context);
    if (scope == null) return;

    final shouldShow = appState.selectedIssue != null;
    if (scope.isEndSidebarShown != shouldShow) {
      scope.toggleEndSidebar();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Also sync state on build if it got out of sync, safely using addPostFrameCallback
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final scope = MacosWindowScope.maybeOf(context);
      if (scope != null) {
        final shouldShow = appState.selectedIssue != null;
        if (scope.isEndSidebarShown != shouldShow) {
          scope.toggleEndSidebar();
        }
      }
    });

    return widget.child;
  }
}
