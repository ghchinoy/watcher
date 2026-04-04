import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import '../main.dart';
import '../models/issue.dart';
import 'kanban_card.dart';

class KanbanColumn extends StatelessWidget {
  final String title;
  final String statusKey;
  final List<Issue> issues;

  const KanbanColumn({
    super.key,
    required this.title,
    required this.statusKey,
    required this.issues,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<Issue>(
      onWillAcceptWithDetails: (details) {
        return details.data.status != statusKey;
      },
      onAcceptWithDetails: (details) {
        final issue = details.data;
        appState.updateIssue(issue.id, status: statusKey);
      },
      builder: (context, candidateData, rejectedData) {
        return Container(
          width: 300,
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: candidateData.isNotEmpty
                ? MacosTheme.of(context).primaryColor.withValues(alpha: 0.1)
                : MacosTheme.of(context).canvasColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: candidateData.isNotEmpty
                  ? MacosTheme.of(context).primaryColor
                  : MacosTheme.of(context).dividerColor,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '$title (${issues.length})',
                  style: MacosTheme.of(context).typography.headline,
                ),
              ),
              Container(height: 1, color: MacosTheme.of(context).dividerColor),
              Expanded(
                child: ListView.builder(
                  itemCount: issues.length,
                  itemBuilder: (context, index) {
                    return KanbanCard(issue: issues[index]);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
