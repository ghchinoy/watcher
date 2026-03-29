import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import '../main.dart';
import '../models/issue.dart';
import '../widgets/view_mode_segmented_control.dart';
import '../widgets/tree_node.dart';
import '../widgets/create_issue_modal.dart';

class TreeViewScreen extends StatefulWidget {
  const TreeViewScreen({super.key});

  @override
  State<TreeViewScreen> createState() => _TreeViewScreenState();
}

class _TreeViewScreenState extends State<TreeViewScreen> {
  bool _defaultExpanded = true;
  Key _treeKey = UniqueKey();

  void _showCreateIssue(BuildContext context) {
    showMacosSheet(
      context: context,
      builder: (context) => MacosSheet(
        child: CreateIssueModal(appState: appState),
      ),
    );
  }

  void _expandAll() {
    setState(() {
      _defaultExpanded = true;
      _treeKey = UniqueKey();
    });
    // Find all node IDs that can be expanded (those with children)
    final allParentIds = appState.currentIssues
        .where(
          (i) => appState.currentIssues.any(
            (child) => child.isDirectChildOf(i),
          ),
        )
        .map((i) => i.id)
        .toList();
    appState.setAllNodesExpanded(true, allParentIds);
  }

  void _collapseAll() {
    setState(() {
      _defaultExpanded = false;
      _treeKey = UniqueKey();
    });
    appState.setAllNodesExpanded(false, []);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        if (appState.selectedProject == null) {
          return MacosScaffold(
            toolBar: ToolBar(
              title: const Text('Tree View'),
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
                    child: ViewModeSegmentedControl(currentRoute: '/tree'),
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
              title: const Text('Tree View'),
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
                    child: ViewModeSegmentedControl(currentRoute: '/tree'),
                  ),
                ),
              ],
            ),
            children: [
              ContentArea(
                builder: (context, scrollController) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Error: ${appState.error}',
                          style: const TextStyle(color: MacosColors.systemRedColor),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        PushButton(
                          controlSize: ControlSize.regular,
                          onPressed: () {
                            if (appState.selectedProject != null) {
                              appState.selectProject(appState.selectedProject!);
                            }
                          },
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],          );
        }

        final issues = appState.currentIssues;

        // Find all top-level issues (those without a parent-child dependency)
        // and filter out closed issues by default, UNLESS they have open children.
        final topLevelIssues = issues.where((issue) {
          final isTopLevel = !issue.hasParentIn(issues);
          if (!isTopLevel) return false;
          
          if (issue.status != 'closed') return true;

          // If it IS top-level but closed, we only show it if it has an open child.
          // This prevents open subtasks from disappearing when the parent Epic is closed.
          final hasOpenChild = issues.any((potentialChild) => 
            potentialChild.isDirectChildOf(issue) && potentialChild.status != 'closed'
          );
          
          return hasOpenChild;
        }).toList();

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
                label: 'Create Issue',
                icon: const MacosIcon(CupertinoIcons.plus_square),
                showLabel: false,
                tooltipMessage: 'Create Issue',
                onPressed: () => _showCreateIssue(context),
              ),
              ToolBarIconButton(
                label: 'Expand All',
                icon: const MacosIcon(CupertinoIcons.chevron_down),
                showLabel: false,
                tooltipMessage: 'Expand All',
                onPressed: _expandAll,
              ),
              ToolBarIconButton(
                label: 'Collapse All',
                icon: const MacosIcon(CupertinoIcons.chevron_right),
                showLabel: false,
                tooltipMessage: 'Collapse All',
                onPressed: _collapseAll,
              ),
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
                  child: ViewModeSegmentedControl(currentRoute: '/tree'),
                ),
              ),
            ],
          ),
          children: [
            ContentArea(
              builder: (context, scrollController) {
                if (topLevelIssues.isEmpty) {
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
                          'No open issues found',
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

                return ListView.builder(
                  key: _treeKey,
                  controller: scrollController,
                  itemCount: topLevelIssues.length,
                  itemBuilder: (context, index) {
                    return TreeNode(
                      issue: topLevelIssues[index],
                      allIssues: issues,
                      depth: 0,
                      defaultExpanded: _defaultExpanded,
                    );
                  },
                );
              },
            ),
          ],
        );
      },
    );
  }
}
