import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import '../main.dart';
import '../widgets/view_mode_segmented_control.dart';
import '../widgets/kanban_column.dart';

class KanbanScreen extends StatelessWidget {
  const KanbanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        if (appState.selectedProject == null) {
          return MacosScaffold(
            toolBar: ToolBar(
              title: const Text('Kanban View'),
              actions: [
                ToolBarIconButton(
                label: 'Toggle Inspector',
                icon: const MacosIcon(CupertinoIcons.sidebar_right),
                showLabel: false,
                tooltipMessage: 'Toggle Inspector',
                onPressed: () => MacosWindowScope.maybeOf(context)?.toggleEndSidebar(),
              ),
              CustomToolbarItem(
                  inToolbarBuilder: (context) => const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.0),
                    child: ViewModeSegmentedControl(currentRoute: '/kanban'),
                  ),
                ),
              ],
            ),
            children: [
              ContentArea(
                builder: (context, scrollController) =>
                    const Center(child: Text('No project selected.')),
              ),
            ],
          );
        }

        if (appState.error != null) {
          return MacosScaffold(
            toolBar: ToolBar(
              title: const Text('Kanban View'),
              actions: [
                ToolBarIconButton(
                label: 'Toggle Inspector',
                icon: const MacosIcon(CupertinoIcons.sidebar_right),
                showLabel: false,
                tooltipMessage: 'Toggle Inspector',
                onPressed: () => MacosWindowScope.maybeOf(context)?.toggleEndSidebar(),
              ),
              CustomToolbarItem(
                  inToolbarBuilder: (context) => const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.0),
                    child: ViewModeSegmentedControl(currentRoute: '/kanban'),
                  ),
                ),
              ],
            ),
            children: [
              ContentArea(
                builder: (context, scrollController) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'Error: ${appState.error}',
                      style: const TextStyle(color: MacosColors.systemRedColor),
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        final issues = appState.currentIssues;
        final openIssues = issues.where((i) => i.status == 'open').toList();
        final inProgressIssues = issues
            .where((i) => i.status == 'in_progress')
            .toList();

        // Sort closed issues by updatedAt descending (most recently closed/updated first)
        final closedIssues = issues.where((i) => i.status == 'closed').toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

        return MacosScaffold(
          toolBar: ToolBar(
            leading: MacosIconButton(
              icon: const MacosIcon(CupertinoIcons.sidebar_left),
              onPressed: () {
                MacosWindowScope.of(context).toggleSidebar();
              },
            ),
            title: Text(appState.selectedProject!.name),
            actions: [
              ToolBarIconButton(
                label: 'Toggle Inspector',
                icon: const MacosIcon(CupertinoIcons.sidebar_right),
                showLabel: false,
                tooltipMessage: 'Toggle Inspector',
                onPressed: () => MacosWindowScope.maybeOf(context)?.toggleEndSidebar(),
              ),
              CustomToolbarItem(
                inToolbarBuilder: (context) => const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8.0),
                  child: ViewModeSegmentedControl(currentRoute: '/kanban'),
                ),
              ),
            ],
          ),
          children: [
            ContentArea(
              builder: (context, scrollController) {
                if (issues.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        MacosIcon(
                          CupertinoIcons.checkmark_seal_fill,
                          size: 48,
                          color: MacosTheme.of(
                            context,
                          ).typography.body.color?.withValues(alpha: 0.2),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No issues found',
                          style: MacosTheme.of(context).typography.title2
                              .copyWith(
                                color: MacosTheme.of(
                                  context,
                                ).typography.body.color?.withValues(alpha: 0.5),
                              ),
                        ),
                      ],
                    ),
                  );
                }

                return SingleChildScrollView(
                  controller: scrollController,
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      KanbanColumn(
                        title: 'Open',
                        statusKey: 'open',
                        issues: openIssues,
                      ),
                      KanbanColumn(
                        title: 'In Progress',
                        statusKey: 'in_progress',
                        issues: inProgressIssues,
                      ),
                      KanbanColumn(
                        title: 'Closed',
                        statusKey: 'closed',
                        issues: closedIssues,
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}
