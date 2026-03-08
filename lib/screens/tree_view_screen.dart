import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import '../main.dart';
import '../models/issue.dart';
import '../widgets/view_mode_segmented_control.dart';

class TreeViewScreen extends StatefulWidget {
  const TreeViewScreen({super.key});

  @override
  State<TreeViewScreen> createState() => _TreeViewScreenState();
}

class _TreeViewScreenState extends State<TreeViewScreen> {
  bool _defaultExpanded = true;
  Key _treeKey = UniqueKey();

  void _expandAll() {
    setState(() {
      _defaultExpanded = true;
      _treeKey = UniqueKey();
    });
  }

  void _collapseAll() {
    setState(() {
      _defaultExpanded = false;
      _treeKey = UniqueKey();
    });
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
              title: const Text('Tree View'),
              actions: [
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
                    child: Text('Error: ${appState.error}', style: const TextStyle(color: CupertinoColors.systemRed)),
                  ),
                ),
              ),
            ],
          );
        }

        final issues = appState.currentIssues;
        
        // Find all top-level issues (those without a parent-child dependency)
        // and filter out closed issues by default.
        final topLevelIssues = issues.where((issue) {
          if (issue.status == 'closed') return false;
          final hasParent = issue.dependencies?.any((d) => d.type == 'parent-child') ?? false;
          return !hasParent;
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
                          color: MacosTheme.of(context).typography.body.color?.withValues(alpha: 0.2),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No open issues found',
                          style: MacosTheme.of(context).typography.title2.copyWith(
                                color: MacosTheme.of(context).typography.body.color?.withValues(alpha: 0.5),
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
                    return _TreeNode(
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

class _TreeNode extends StatefulWidget {
  final Issue issue;
  final List<Issue> allIssues;
  final int depth;
  final bool defaultExpanded;

  const _TreeNode({
    required this.issue,
    required this.allIssues,
    required this.depth,
    this.defaultExpanded = true,
  });

  @override
  State<_TreeNode> createState() => _TreeNodeState();
}

class _TreeNodeState extends State<_TreeNode> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.defaultExpanded;
  }

  @override
  Widget build(BuildContext context) {
    // Find children of this issue and filter out closed issues
    final children = widget.allIssues.where((potentialChild) {
      if (potentialChild.status == 'closed') return false;
      return potentialChild.dependencies?.any((d) => d.type == 'parent-child' && d.dependsOnId == widget.issue.id) ?? false;
    }).toList();

    return Padding(
      padding: EdgeInsets.only(
        left: widget.depth == 0 ? 16 : 24, 
        top: widget.depth == 0 ? 8 : 4, 
        right: 16, 
        bottom: widget.depth == 0 ? 8 : 0
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (children.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _isExpanded = !_isExpanded;
                    });
                  },
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4.0),
                      child: MacosIcon(
                        _isExpanded ? CupertinoIcons.chevron_down : CupertinoIcons.chevron_right,
                        size: 12,
                        color: CupertinoColors.systemGrey,
                      ),
                    ),
                  ),
                )
              else
                const SizedBox(width: 16),
              Expanded(
                child: GestureDetector(
                  onTap: () => appState.selectIssue(widget.issue),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: _buildIssueRow(widget.issue, context, isRoot: widget.depth == 0),
                  ),
                ),
              ),
            ],
          ),
          if (children.isNotEmpty && _isExpanded)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children.map((child) => _TreeNode(
                issue: child, 
                allIssues: widget.allIssues, 
                depth: widget.depth + 1,
                defaultExpanded: widget.defaultExpanded,
              )).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildIssueRow(Issue issue, BuildContext context, {required bool isRoot}) {
    return Row(
      children: [
        if (isRoot)
          MacosIcon(
            _getIconForType(issue.issueType),
            color: MacosTheme.of(context).primaryColor,
            size: 16,
          )
        else
          const Text('↳', style: TextStyle(color: CupertinoColors.systemGrey)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${issue.id} - ${issue.title}',
            style: TextStyle(
              fontWeight: isRoot ? FontWeight.bold : FontWeight.normal,
              fontSize: isRoot ? 14 : 13,
              decoration: issue.status == 'closed' ? TextDecoration.lineThrough : null,
              color: issue.status == 'closed' ? CupertinoColors.systemGrey : null,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 32,
              height: 20,
              child: Align(
                alignment: Alignment.centerRight,
                child: _buildPriorityBadge(issue.priority, context),
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 24,
              height: 20,
              child: Align(
                alignment: Alignment.centerRight,
                child: _buildStatusBadge(issue.status, context),
              ),
            ),
          ],
        ),
      ],
    );
  }

  IconData _getIconForType(String type) {
    switch (type.toLowerCase()) {
      case 'epic':
        return CupertinoIcons.square_stack_3d_up;
      case 'bug':
        return CupertinoIcons.ant;
      case 'feature':
        return CupertinoIcons.star;
      default:
        return CupertinoIcons.doc_text;
    }
  }

  Widget _buildPriorityBadge(int priority, BuildContext context) {
    Color baseColor;
    switch (priority) {
      case 0:
        baseColor = CupertinoColors.systemRed;
        break;
      case 1:
        baseColor = CupertinoColors.systemOrange;
        break;
      case 2:
        baseColor = CupertinoColors.systemYellow;
        break;
      case 3:
        baseColor = CupertinoColors.systemBlue;
        break;
      default:
        baseColor = CupertinoColors.systemGrey;
    }
    final resolvedColor = MacosDynamicColor.resolve(baseColor, context);

    return MacosTooltip(
      message: 'Priority $priority',
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: resolvedColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: resolvedColor.withValues(alpha: 0.3)),
        ),
        child: Text(
          'P$priority',
          style: TextStyle(fontSize: 10, color: resolvedColor, fontWeight: FontWeight.w600, height: 1.0),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status, BuildContext context) {
    Color baseColor;
    IconData iconData;
    switch (status.toLowerCase()) {
      case 'open':
        baseColor = CupertinoColors.systemBlue;
        iconData = CupertinoIcons.circle;
        break;
      case 'in_progress':
        baseColor = CupertinoColors.systemIndigo;
        iconData = CupertinoIcons.circle_lefthalf_fill;
        break;
      case 'closed':
        baseColor = CupertinoColors.systemGreen;
        iconData = CupertinoIcons.check_mark_circled_solid;
        break;
      default:
        baseColor = CupertinoColors.systemGrey;
        iconData = CupertinoIcons.circle;
    }
    final resolvedColor = MacosDynamicColor.resolve(baseColor, context);

    return MacosTooltip(
      message: 'Status: $status',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: MacosIcon(
          iconData,
          color: resolvedColor,
          size: 16,
        ),
      ),
    );
  }
}
