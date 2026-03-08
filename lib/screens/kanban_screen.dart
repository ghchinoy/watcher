import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import '../main.dart';
import '../models/issue.dart';
import '../widgets/view_mode_segmented_control.dart';

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
                builder: (context, scrollController) => const Center(
                  child: Text('No project selected.'),
                ),
              ),
            ],
          );
        }

        if (appState.error != null) {
          return MacosScaffold(
            toolBar: ToolBar(
              title: const Text('Kanban View'),
              actions: [
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
                    child: Text('Error: ${appState.error}', style: const TextStyle(color: CupertinoColors.systemRed)),
                  ),
                ),
              ),
            ],
          );
        }

        final issues = appState.currentIssues;
        final openIssues = issues.where((i) => i.status == 'open').toList();
        final inProgressIssues = issues.where((i) => i.status == 'in_progress').toList();
        final closedIssues = issues.where((i) => i.status == 'closed').toList();

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
                          color: MacosTheme.of(context).typography.body.color?.withValues(alpha: 0.2),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No issues found',
                          style: MacosTheme.of(context).typography.title2.copyWith(
                                color: MacosTheme.of(context).typography.body.color?.withValues(alpha: 0.5),
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
                      _KanbanColumn(title: 'Open', issues: openIssues),
                      _KanbanColumn(title: 'In Progress', issues: inProgressIssues),
                      _KanbanColumn(title: 'Closed', issues: closedIssues),
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

class _KanbanColumn extends StatelessWidget {
  final String title;
  final List<Issue> issues;

  const _KanbanColumn({required this.title, required this.issues});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MacosTheme.of(context).canvasColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MacosTheme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              '$title (${issues.length})',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Container(height: 1, color: MacosTheme.of(context).dividerColor),
          Expanded(
            child: ListView.builder(
              itemCount: issues.length,
              itemBuilder: (context, index) {
                return _KanbanCard(issue: issues[index]);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _KanbanCard extends StatelessWidget {
  final Issue issue;

  const _KanbanCard({required this.issue});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => appState.selectIssue(issue),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          margin: const EdgeInsets.all(8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: CupertinoColors.systemGrey6,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: MacosTheme.of(context).dividerColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    issue.id,
                    style: const TextStyle(fontSize: 12, color: CupertinoColors.systemGrey),
                  ),
                  _buildTypeBadge(issue.issueType),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                issue.title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              if (issue.owner != null && issue.owner!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Owner: ${issue.owner}',
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypeBadge(String type) {
    Color color;
    switch (type.toLowerCase()) {
      case 'epic':
        color = CupertinoColors.systemPurple;
        break;
      case 'bug':
        color = CupertinoColors.systemRed;
        break;
      case 'task':
        color = CupertinoColors.systemBlue;
        break;
      case 'feature':
        color = CupertinoColors.systemGreen;
        break;
      default:
        color = CupertinoColors.systemGrey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        type.toUpperCase(),
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold),
      ),
    );
  }
}
