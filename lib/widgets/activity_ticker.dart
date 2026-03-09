import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import '../main.dart';

class ActivityTicker extends StatelessWidget {
  const ActivityTicker({super.key});

  @override
  Widget build(BuildContext context) {
    final interactions = appState.currentInteractions;
    if (interactions.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: MacosDynamicColor.resolve(CupertinoColors.systemGrey6, context),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Text('No recent activity found.', style: TextStyle(color: CupertinoColors.systemGrey)),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: MacosDynamicColor.resolve(CupertinoColors.systemGrey6, context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MacosTheme.of(context).dividerColor),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: interactions.length > 20 ? 20 : interactions.length, // Show up to 20
        separatorBuilder: (context, index) => Container(
          height: 1,
          color: MacosTheme.of(context).dividerColor,
        ),
        itemBuilder: (context, index) {
          final interaction = interactions[index];
          final timeStr = '${interaction.timestamp.hour.toString().padLeft(2, '0')}:${interaction.timestamp.minute.toString().padLeft(2, '0')}';
          
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 60,
                  child: Text(
                    timeStr,
                    style: const TextStyle(color: CupertinoColors.systemGrey, fontSize: 12),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${interaction.actor} performed ${interaction.action}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      if (interaction.issueId != null) ...[
                        const SizedBox(height: 4),
                        GestureDetector(
                          onTap: () {
                            // Find the issue and open it in the inspector
                            final issue = appState.currentIssues.where((i) => i.id == interaction.issueId).firstOrNull;
                            if (issue != null) {
                              appState.selectIssue(issue);
                            }
                          },
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: Text(
                              'Issue: ${interaction.issueId}',
                              style: TextStyle(
                                fontSize: 12,
                                color: MacosTheme.of(context).primaryColor,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
