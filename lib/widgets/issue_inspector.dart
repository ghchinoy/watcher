import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import '../models/issue.dart';

class IssueInspector extends StatelessWidget {
  final Issue issue;
  final VoidCallback onClose;
  final ScrollController scrollController;

  const IssueInspector({super.key, required this.issue, required this.onClose, required this.scrollController});

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    
    return Container(
      width: 300,
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: theme.dividerColor,
          ),
        ),
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
                  _buildSection('Status', issue.status.toUpperCase()),
                  _buildSection('Priority', 'P${issue.priority}'),
                  _buildSection('Type', issue.issueType.toUpperCase()),
                  if (issue.owner != null && issue.owner!.isNotEmpty)
                    _buildSection('Owner', issue.owner!),
                  if (issue.createdBy != null && issue.createdBy!.isNotEmpty)
                    _buildSection('Created By', issue.createdBy!),
                  _buildSection('Created', _formatDate(issue.createdAt)),
                  _buildSection('Updated', _formatDate(issue.updatedAt)),
                  
                  const SizedBox(height: 16),
                  const Text('Description', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    issue.description?.isNotEmpty == true ? issue.description! : 'No description provided.',
                    style: TextStyle(
                      color: issue.description?.isNotEmpty == true ? null : CupertinoColors.systemGrey,
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
                  style: const TextStyle(fontSize: 12, color: CupertinoColors.systemGrey),
                ),
                const SizedBox(height: 4),
                Text(
                  issue.title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
          ),
          MacosIconButton(
            icon: const MacosIcon(CupertinoIcons.clear),
            onPressed: onClose,
            boxConstraints: const BoxConstraints(minWidth: 20, minHeight: 20),
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
          Text(title, style: const TextStyle(fontSize: 11, color: CupertinoColors.systemGrey, fontWeight: FontWeight.bold)),
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
