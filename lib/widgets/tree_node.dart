import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import '../main.dart';
import '../models/issue.dart';

class TreeNode extends StatefulWidget {
  final Issue issue;
  final List<Issue> allIssues;
  final int depth;
  final bool defaultExpanded;

  const TreeNode({
    super.key,
    required this.issue,
    required this.allIssues,
    required this.depth,
    this.defaultExpanded = true,
  });

  @override
  State<TreeNode> createState() => _TreeNodeState();
}

class _TreeNodeState extends State<TreeNode> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    // Initialize from persisted state if available, otherwise use default
    if (appState.expandedNodes.isNotEmpty) {
      _isExpanded = appState.isNodeExpanded(widget.issue.id);
    } else {
      _isExpanded = widget.defaultExpanded;
    }
  }

  void _toggleExpansion() {
    setState(() {
      _isExpanded = !_isExpanded;
    });
    appState.toggleNodeExpansion(widget.issue.id, _isExpanded);
  }

  @override
  Widget build(BuildContext context) {
    // Find children of this issue and filter out closed issues
    final children = widget.allIssues.where((potentialChild) {
      if (potentialChild.status == 'closed') return false;
      return potentialChild.isDirectChildOf(widget.issue);
    }).toList();

    return Padding(
      padding: EdgeInsets.only(
        left: widget.depth == 0 ? 16 : 24,
        top: widget.depth == 0 ? 8 : 4,
        right: 16,
        bottom: widget.depth == 0 ? 8 : 0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (children.isNotEmpty)
                GestureDetector(
                  onTap: _toggleExpansion,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4.0),
                      child: MacosIcon(
                        _isExpanded
                            ? CupertinoIcons.chevron_down
                            : CupertinoIcons.chevron_right,
                        size: 12,
                        color: MacosColors.systemGrayColor,
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
                    child: _buildIssueRow(
                      widget.issue,
                      context,
                      isRoot: widget.depth == 0,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (children.isNotEmpty && _isExpanded)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children
                  .map(
                    (child) => TreeNode(
                      issue: child,
                      allIssues: widget.allIssues,
                      depth: widget.depth + 1,
                      defaultExpanded: widget.defaultExpanded,
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildIssueRow(
    Issue issue,
    BuildContext context, {
    required bool isRoot,
  }) {
    return Row(
      children: [
        MacosIcon(
          _getIconForType(issue.issueType),
          color: MacosTheme.of(context).primaryColor,
          size: 16,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${issue.id} - ${issue.title}',
            style: TextStyle(
              fontWeight: isRoot ? FontWeight.bold : FontWeight.normal,
              fontSize: isRoot ? 14 : 13,
              decoration: issue.status == 'closed'
                  ? TextDecoration.lineThrough
                  : null,
              color: issue.status == 'closed'
                  ? MacosColors.systemGrayColor
                  : null,
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
        baseColor = MacosColors.systemRedColor;
        break;
      case 1:
        baseColor = MacosColors.systemOrangeColor;
        break;
      case 2:
        baseColor = MacosColors.systemYellowColor;
        break;
      case 3:
        baseColor = MacosColors.systemBlueColor;
        break;
      default:
        baseColor = MacosColors.systemGrayColor;
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
          style: TextStyle(
            fontSize: 10,
            color: resolvedColor,
            fontWeight: FontWeight.w600,
            height: 1.0,
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status, BuildContext context) {
    Color baseColor;
    IconData iconData;
    switch (status.toLowerCase()) {
      case 'open':
        baseColor = MacosColors.systemBlueColor;
        iconData = CupertinoIcons.circle;
        break;
      case 'in_progress':
        baseColor = MacosColors.systemPurpleColor;
        iconData = CupertinoIcons.circle_lefthalf_fill;
        break;
      case 'blocked':
        baseColor = MacosColors.systemRedColor;
        iconData = CupertinoIcons.minus_circle_fill;
        break;
      case 'deferred':
        baseColor = MacosColors.systemGrayColor;
        iconData = CupertinoIcons.snow;
        break;
      case 'closed':
        baseColor = MacosColors.systemGreenColor;
        iconData = CupertinoIcons.check_mark_circled_solid;
        break;
      default:
        baseColor = MacosColors.systemGrayColor;
        iconData = CupertinoIcons.circle;
    }
    final resolvedColor = MacosDynamicColor.resolve(baseColor, context);

    return MacosTooltip(
      message: 'Status: $status',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: MacosIcon(iconData, color: resolvedColor, size: 16),
      ),
    );
  }
}
