import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import '../main.dart';
import '../models/issue.dart';

class KanbanCard extends StatelessWidget {
  final Issue issue;

  const KanbanCard({super.key, required this.issue});

  @override
  Widget build(BuildContext context) {
    // If an agent has claimed it or it's in progress, lock it to prevent drag-and-drop state changes
    final bool isLocked =
        issue.status == 'in_progress' &&
        (issue.assignee != null && issue.assignee!.isNotEmpty);

    final cardContent = GestureDetector(
      onTap: () => appState.selectIssue(issue),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          margin: const EdgeInsets.all(8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: MacosDynamicColor.resolve(
              MacosColors.controlBackgroundColor,
              context,
            ),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: MacosTheme.of(context).dividerColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        issue.id,
                        style: const TextStyle(
                          fontSize: 12,
                          color: MacosColors.systemGrayColor,
                        ),
                      ),
                      if (isLocked) ...[
                        const SizedBox(width: 6),
                        const MacosTooltip(
                          message: 'Locked (Agent in process)',
                          child: MacosIcon(
                            CupertinoIcons.lock_fill,
                            size: 10,
                            color: MacosColors.systemGrayColor,
                          ),
                        ),
                      ],
                    ],
                  ),
                  _buildTypeBadge(issue.issueType),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                issue.title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              if (issue.assignee != null && issue.assignee!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Assignee: ${issue.assignee}',
                  style: const TextStyle(fontSize: 11),
                ),
              ] else if (issue.owner != null && issue.owner!.isNotEmpty) ...[
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

    if (isLocked) {
      return cardContent;
    }

    return Draggable<Issue>(
      data: issue,
      feedback: SizedBox(
        width: 284, // Approximate width of the card minus margins
        child: Opacity(opacity: 0.8, child: cardContent),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: cardContent),
      child: cardContent,
    );
  }

  Widget _buildTypeBadge(String type) {
    Color color;
    switch (type.toLowerCase()) {
      case 'epic':
        color = MacosColors.systemPurpleColor;
        break;
      case 'bug':
        color = MacosColors.systemRedColor;
        break;
      case 'task':
        color = MacosColors.systemBlueColor;
        break;
      case 'feature':
        color = MacosColors.systemGreenColor;
        break;
      default:
        color = MacosColors.systemGrayColor;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        type.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
