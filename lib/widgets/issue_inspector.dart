import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import '../main.dart';
import '../models/issue.dart';

class IssueInspector extends StatefulWidget {
  final Issue issue;
  final ScrollController scrollController;

  const IssueInspector({
    super.key,
    required this.issue,
    required this.scrollController,
  });

  @override
  State<IssueInspector> createState() => _IssueInspectorState();
}

class _IssueInspectorState extends State<IssueInspector> {
  final _commentController = TextEditingController();

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    final issue = widget.issue;

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
              controller: widget.scrollController,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Core Attributes
                  _buildStatusDropdown(context),
                  _buildPriorityDropdown(context),
                  _buildSection('Type', issue.issueType.toUpperCase(), context),
                  
                  // People
                  _buildEditableField('Owner', issue.owner ?? '', context, (value) {
                    appState.updateIssue(issue.id, owner: value);
                  }),
                  _buildEditableField('Assignee', issue.assignee ?? '', context, (value) {
                    appState.updateIssue(issue.id, assignee: value);
                  }),

                  _buildDependenciesSection(context),

                  const SizedBox(height: 8),
                  Container(height: 1, color: theme.dividerColor),
                  const SizedBox(height: 16),

                  // Description
                  Text(
                    'Description',
                    style: theme.typography.headline,
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

                  // Metadata (compact)
                  _buildMetadataSection(context, issue),

                  const SizedBox(height: 16),
                  Container(height: 1, color: theme.dividerColor),
                  const SizedBox(height: 16),

                  // Comments
                  _buildCommentsSection(context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetadataSection(BuildContext context, Issue issue) {
    final theme = MacosTheme.of(context);
    final textStyle = theme.typography.footnote.copyWith(
      color: MacosColors.systemGrayColor,
    );
    
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (issue.createdBy != null && issue.createdBy!.isNotEmpty)
            Text('Created by ${issue.createdBy} on ${_formatDate(issue.createdAt)}', style: textStyle)
          else
            Text('Created on ${_formatDate(issue.createdAt)}', style: textStyle),
          
          Text('Last updated ${_formatDate(issue.updatedAt)}', style: textStyle),
          
          if (issue.closedAt != null)
            Text(
              'Closed on ${_formatDate(issue.closedAt!)}${issue.closeReason?.isNotEmpty == true ? ' (${issue.closeReason})' : ''}', 
              style: textStyle
            ),
        ],
      ),
    );
  }

  Widget _buildDependenciesSection(BuildContext context) {
    final issue = widget.issue;
    final blocksIds =
        issue.dependencies
            ?.where((d) => d.type == 'blocks')
            .map((d) => d.dependsOnId)
            .toList() ??
        [];

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

  Widget _buildStatusDropdown(BuildContext context) {
    final issue = widget.issue;
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

  Widget _buildPriorityDropdown(BuildContext context) {
    final issue = widget.issue;
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
    final issue = widget.issue;
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

  Widget _buildCommentsSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Comments',
          style: MacosTheme.of(context).typography.headline,
        ),
        const SizedBox(height: 8),
        if (appState.selectedIssueComments.isEmpty)
          Text(
            'No comments yet.',
            style: MacosTheme.of(context).typography.footnote.copyWith(
                  color: MacosColors.systemGrayColor,
                  fontStyle: FontStyle.italic,
                ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: appState.selectedIssueComments.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final comment = appState.selectedIssueComments[index];
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: MacosDynamicColor.resolve(
                    MacosColors.controlBackgroundColor,
                    context,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          comment['author']?.toString() ?? 'Unknown',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        Text(
                          comment['created_at'] != null 
                            ? _formatDate(DateTime.parse(comment['created_at'].toString()).toLocal()) 
                            : '',
                          style: const TextStyle(
                            color: MacosColors.systemGrayColor,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      comment['text']?.toString() ?? '',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              );
            },
          ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: MacosTextField(
                controller: _commentController,
                placeholder: 'Add a comment...',
                maxLines: 3,
                minLines: 1,
              ),
            ),
            const SizedBox(width: 8),
            MacosIconButton(
              icon: MacosIcon(
                CupertinoIcons.arrow_up_circle_fill,
                color: MacosTheme.of(context).primaryColor,
                size: 24,
              ),
              onPressed: () {
                if (_commentController.text.trim().isNotEmpty) {
                  appState.addComment(widget.issue.id, _commentController.text.trim());
                  _commentController.clear();
                }
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSection(String title, String value, BuildContext context) {
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

  Widget _buildEditableField(String title, String initialValue, BuildContext context, Function(String) onSubmitted) {
    final controller = TextEditingController(text: initialValue);
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
          const SizedBox(height: 4),
          MacosTextField(
            controller: controller,
            maxLines: 1,
            onSubmitted: onSubmitted,
            placeholder: 'Unassigned',
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
