import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import '../main.dart';
import '../models/issue.dart';
import '../widgets/view_mode_segmented_control.dart';
import '../widgets/error_display_view.dart';

/// A list of every blocked issue with its open blockers shown inline.
/// Mirrors `bd blocked` — the triage counterpart to the Ready Queue.
class BlockedScreen extends StatelessWidget {
  const BlockedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final all = appState.currentIssues;
        final blocked =
            all
                .where(
                  (i) =>
                      (i.status == 'open' || i.status == 'in_progress') &&
                      i.isBlocked(all),
                )
                .toList()
              ..sort((a, b) {
                final p = a.priority.compareTo(b.priority);
                if (p != 0) return p;
                return a.title.compareTo(b.title);
              });

        return MacosScaffold(
          toolBar: ToolBar(
            leading: MacosIconButton(
              icon: const MacosIcon(CupertinoIcons.sidebar_left),
              onPressed: () => MacosWindowScope.of(context).toggleSidebar(),
            ),
            title: Text(
              appState.selectedProject != null
                  ? '${appState.selectedProject!.name} — Blocked'
                  : 'Blocked Issues',
            ),
            actions: [
              ToolBarIconButton(
                label: 'Toggle Inspector',
                icon: const MacosIcon(CupertinoIcons.sidebar_right),
                showLabel: false,
                tooltipMessage: 'Toggle Inspector',
                onPressed: () =>
                    MacosWindowScope.maybeOf(context)?.toggleEndSidebar(),
              ),
              CustomToolbarItem(
                inToolbarBuilder: (context) => const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: ViewModeSegmentedControl(currentRoute: '/blocked'),
                ),
              ),
            ],
          ),
          children: [
            ContentArea(
              builder: (context, scrollController) {
                if (appState.selectedProject == null) {
                  return const Center(child: Text('No project selected.'));
                }
                if (appState.error != null) {
                  return ErrorDisplayView(
                    error: appState.error!,
                    onRetry: () {
                      if (appState.selectedProject != null) {
                        appState.selectProject(appState.selectedProject!);
                      }
                    },
                  );
                }
                if (appState.isLoading) {
                  return const Center(child: ProgressCircle());
                }
                if (blocked.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const MacosIcon(
                          CupertinoIcons.checkmark_shield,
                          size: 48,
                          color: MacosColors.systemGreenColor,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No impediments!',
                          style: MacosTheme.of(context).typography.title1,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No open issues are currently blocked.',
                          style: MacosTheme.of(context).typography.body
                              .copyWith(color: MacosColors.systemGrayColor),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: blocked.length,
                  itemBuilder: (context, index) {
                    final issue = blocked[index];
                    return _BlockedRow(issue: issue, allIssues: all);
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

class _BlockedRow extends StatelessWidget {
  final Issue issue;
  final List<Issue> allIssues;

  const _BlockedRow({required this.issue, required this.allIssues});

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    final isSelected = appState.selectedIssue?.id == issue.id;
    final openBlockers = issue.blockers(allIssues);

    return GestureDetector(
      onTap: () => appState.selectIssue(issue),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? MacosColors.systemRedColor.withValues(alpha: 0.08)
                : MacosDynamicColor.resolve(
                    theme.brightness.isDark
                        ? MacosColors.alternatingContentBackgroundColor
                        : MacosColors.controlBackgroundColor,
                    context,
                  ),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected
                  ? MacosColors.systemRedColor.withValues(alpha: 0.4)
                  : MacosColors.systemRedColor.withValues(alpha: 0.2),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Blocked issue header
                Row(
                  children: [
                    _priorityChip(issue.priority, context),
                    const SizedBox(width: 8),
                    const MacosIcon(
                      CupertinoIcons.exclamationmark_circle_fill,
                      size: 14,
                      color: MacosColors.systemRedColor,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            issue.title,
                            style: theme.typography.body.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            issue.id,
                            style: theme.typography.footnote.copyWith(
                              color: MacosColors.systemGrayColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                // Open blockers list
                if (openBlockers.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    margin: const EdgeInsets.only(left: 4),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: MacosColors.systemGrayColor.withValues(
                        alpha: 0.06,
                      ),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: MacosColors.systemGrayColor.withValues(
                          alpha: 0.15,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Blocked by:',
                          style: theme.typography.footnote.copyWith(
                            color: MacosColors.systemGrayColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        ...openBlockers.map((b) => _BlockerLink(blocker: b)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _priorityChip(int priority, BuildContext context) {
    final colors = [
      MacosColors.systemRedColor,
      MacosColors.systemOrangeColor,
      MacosColors.systemYellowColor,
      MacosColors.systemBlueColor,
      MacosColors.systemGrayColor,
    ];
    final color = MacosDynamicColor.resolve(
      colors[priority.clamp(0, 4)],
      context,
    );
    return Container(
      width: 28,
      padding: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Center(
        child: Text(
          'P$priority',
          style: TextStyle(
            fontSize: 10,
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _BlockerLink extends StatelessWidget {
  final Issue blocker;

  const _BlockerLink({required this.blocker});

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    return GestureDetector(
      onTap: () => appState.selectIssue(blocker),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(
            children: [
              MacosIcon(
                blocker.status == 'closed'
                    ? CupertinoIcons.checkmark_circle_fill
                    : CupertinoIcons.circle,
                size: 12,
                color: blocker.status == 'closed'
                    ? MacosColors.systemGreenColor
                    : MacosColors.systemOrangeColor,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${blocker.id}  ${blocker.title}',
                  style: theme.typography.footnote.copyWith(
                    color: theme.primaryColor,
                    decoration: TextDecoration.underline,
                    decorationColor: theme.primaryColor.withValues(alpha: 0.5),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                blocker.status.toUpperCase(),
                style: theme.typography.footnote.copyWith(
                  fontSize: 9,
                  color: MacosColors.systemGrayColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
