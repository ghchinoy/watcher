import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import '../main.dart';
import '../models/issue.dart';

class IssueInspector extends StatelessWidget {
  final Issue issue;
  final ScrollController scrollController;

  const IssueInspector({
    super.key,
    required this.issue,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);

    return Container(
      width: 300,
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context),
          Expanded(
            child: SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatusDropdown(),
                  _buildPriorityDropdown(),
                  _buildSection('Type', issue.issueType.toUpperCase()),
                  if (issue.owner != null && issue.owner!.isNotEmpty)
                    _buildSection('Owner', issue.owner!),
                  if (issue.assignee != null && issue.assignee!.isNotEmpty)
                    _buildSection('Assignee', issue.assignee!),
                  if (issue.createdBy != null && issue.createdBy!.isNotEmpty)
                    _buildSection('Created By', issue.createdBy!),
                  _buildSection('Created', _formatDate(issue.createdAt)),
                  _buildSection('Updated', _formatDate(issue.updatedAt)),
                  if (issue.closedAt != null)
                    _buildSection('Closed', _formatDate(issue.closedAt!)),
                  if (issue.closeReason != null &&
                      issue.closeReason!.isNotEmpty)
                    _buildSection('Close Reason', issue.closeReason!),

                  _buildDependenciesSection(context),

                  const SizedBox(height: 16),
                  Text(
                    'Description',
                    style: MacosTheme.of(context).typography.headline,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    issue.description?.isNotEmpty == true
                        ? issue.description!
                        : 'No description provided.',
                    style: TextStyle(
                      color: issue.description?.isNotEmpty == true
                          ? null
                          : MacosColors.systemGrayColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDependenciesSection(BuildContext context) {
    // Find what this issue blocks
    final blocksIds =
        issue.dependencies
            ?.where((d) => d.type == 'blocks')
            .map((d) => d.dependsOnId)
            .toList() ??
        [];

    // Find what this issue is blocked by
    final blockedByIds = appState.currentIssues
        .where(
          (i) =>
              i.dependencies?.any(
                (d) => d.type == 'blocks' && d.dependsOnId == issue.id,
              ) ??
              false,
        )
        .map((i) => i.id)
        .toList();

    if (blocksIds.isEmpty && blockedByIds.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (blockedByIds.isNotEmpty) ...[
            Text(
              'Blocked By',
              style: MacosTheme.of(context).typography.footnote.copyWith(
                color: MacosColors.systemGrayColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            ...blockedByIds.map((id) => _buildDependencyLink(id, context)),
            const SizedBox(height: 8),
          ],
          if (blocksIds.isNotEmpty) ...[
            Text(
              'Blocks',
              style: MacosTheme.of(context).typography.footnote.copyWith(
                color: MacosColors.systemGrayColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            ...blocksIds.map((id) => _buildDependencyLink(id, context)),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildDependencyLink(String issueId, BuildContext context) {
    return GestureDetector(
      onTap: () {
        final targetIssue = appState.currentIssues
            .where((i) => i.id == issueId)
            .firstOrNull;
        if (targetIssue != null) {
          appState.selectIssue(targetIssue);
        }
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            issueId,
            style: MacosTheme.of(context).typography.footnote.copyWith(
              color: MacosTheme.of(context).primaryColor,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusDropdown() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Status',
            style: MacosTheme.of(context).typography.footnote.copyWith(
              color: MacosColors.systemGrayColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          MacosPopupButton<String>(
            value: issue.status.toLowerCase(),
            onChanged: (String? newValue) {
              if (newValue != null && newValue != issue.status) {
                appState.updateIssue(issue.id, status: newValue);
              }
            },
            items: const [
              MacosPopupMenuItem(value: 'open', child: Text('OPEN')),
              MacosPopupMenuItem(
                value: 'in_progress',
                child: Text('IN PROGRESS'),
              ),
              MacosPopupMenuItem(value: 'blocked', child: Text('BLOCKED')),
              MacosPopupMenuItem(value: 'closed', child: Text('CLOSED')),
              MacosPopupMenuItem(value: 'deferred', child: Text('DEFERRED')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPriorityDropdown() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Priority',
            style: MacosTheme.of(context).typography.footnote.copyWith(
              color: MacosColors.systemGrayColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          MacosPopupButton<int>(
            value: issue.priority,
            onChanged: (int? newValue) {
              if (newValue != null && newValue != issue.priority) {
                appState.updateIssue(issue.id, priority: newValue);
              }
            },
            items: const [
              MacosPopupMenuItem(value: 0, child: Text('P0 - Critical')),
              MacosPopupMenuItem(value: 1, child: Text('P1 - High')),
              MacosPopupMenuItem(value: 2, child: Text('P2 - Medium')),
              MacosPopupMenuItem(value: 3, child: Text('P3 - Low')),
              MacosPopupMenuItem(value: 4, child: Text('P4 - Backlog')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: MacosTheme.of(context).dividerColor),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  issue.id,
                  style: MacosTheme.of(context).typography.footnote.copyWith(
                    color: MacosColors.systemGrayColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  issue.title,
                  style: MacosTheme.of(context).typography.headline,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: MacosTheme.of(context).typography.footnote.copyWith(
              color: MacosColors.systemGrayColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(value),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
