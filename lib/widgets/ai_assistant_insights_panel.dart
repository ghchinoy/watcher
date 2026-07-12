import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import '../state/app_state.dart';
import '../services/generative_ai_service.dart';
import '../models/issue.dart';
import '../utils/dialog_utils.dart';

class AIAssistantInsightsPanel extends StatefulWidget {
  final AppState appState;

  const AIAssistantInsightsPanel({super.key, required this.appState});

  @override
  State<AIAssistantInsightsPanel> createState() => _AIAssistantInsightsPanelState();
}

class _AIAssistantInsightsPanelState extends State<AIAssistantInsightsPanel> {
  bool _isLoading = false;
  String? _error;
  String? _summary;
  List<Map<String, dynamic>> _recommendations = [];

  @override
  void initState() {
    super.initState();
    _loadInsights();
  }

  @override
  void didUpdateWidget(AIAssistantInsightsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If project path or issues count or health diagnostics changed, reload insights automatically!
    if (oldWidget.appState.selectedProject?.path != widget.appState.selectedProject?.path) {
      _loadInsights();
    }
  }

  Future<void> _loadInsights() async {
    final gcpId = widget.appState.gcpProjectId;
    final modelConfig = widget.appState.defaultAiModel;

    if (gcpId == null || gcpId.isEmpty || modelConfig == null) {
      setState(() {
        _error = 'AI configuration missing. Please configure GCP Project ID and AI Model in settings.';
        _summary = null;
        _recommendations = [];
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Run static checkHealth or use cached one
      HealthCheckResult? health = widget.appState.selectedProjectHealth;
      health ??= await widget.appState.checkHealth();

      final issues = widget.appState.currentIssues;
      final jsonStr = await GenerativeAiService.generateHealthInsights(
        gcpProjectId: gcpId,
        defaultAiModel: modelConfig,
        issues: issues,
        diagnostics: health.diagnostics,
      );

      if (jsonStr == null || jsonStr.isEmpty) {
        throw Exception('AI returned an empty response.');
      }

      final Map<String, dynamic> data = jsonDecode(jsonStr);
      final rawRecs = data['recommendations'] as List<dynamic>? ?? [];

      if (mounted) {
        setState(() {
          _summary = data['summary'] as String? ?? 'No narrative summary available.';
          _recommendations = rawRecs.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to generate insights: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  // Tracking which recommendation is currently executing a mutation to display a ProgressCircle
  final Map<int, bool> _executingIndexes = {};

  Future<void> _executeRecommendation(int index, Map<String, dynamic> rec) async {
    final actionType = rec['actionType'] as String?;
    final payload = rec['payload'] as Map<String, dynamic>? ?? {};

    setState(() {
      _executingIndexes[index] = true;
    });

    try {
      if (actionType == 'updateIssue') {
        final id = payload['id'] as String?;
        if (id == null) throw Exception('Mutation missing required field "id"');
        final status = payload['status'] as String?;
        final priority = payload['priority'] as int?;
        final owner = payload['owner'] as String?;
        final assignee = payload['assignee'] as String?;
        final parent = payload['parent'] as String?;

        final result = await widget.appState.updateIssue(
          id,
          status: status,
          priority: priority,
          owner: owner,
          assignee: assignee,
          parent: parent,
        );

        if (result == MutationResult.success) {
          if (mounted) DialogUtils.showToast(context, message: 'Successfully updated issue $id');
        } else if (result == MutationResult.conflict) {
          if (mounted) DialogUtils.showToast(context, message: 'Conflict: issue $id was updated elsewhere.', isError: true);
        } else {
          throw Exception('Failed to update issue');
        }
      } else if (actionType == 'addDependency') {
        final issueId = payload['issueId'] as String?;
        final dependsOn = payload['dependsOn'] as String?;
        final type = payload['type'] as String? ?? 'blocks';

        if (issueId == null || dependsOn == null) {
          throw Exception('Mutation missing "issueId" or "dependsOn"');
        }

        await widget.appState.addDependency(issueId, dependsOn, type);
        if (mounted) DialogUtils.showToast(context, message: 'Added dependency: $issueId now $type $dependsOn');
      } else if (actionType == 'removeDependency') {
        final issueId = payload['issueId'] as String?;
        final dependsOn = payload['dependsOn'] as String?;

        if (issueId == null || dependsOn == null) {
          throw Exception('Mutation missing "issueId" or "dependsOn"');
        }

        await widget.appState.removeDependency(issueId, dependsOn);
        if (mounted) DialogUtils.showToast(context, message: 'Removed dependency between $issueId and $dependsOn');
      } else if (actionType == 'createIssue') {
        final title = payload['title'] as String?;
        final description = payload['description'] as String? ?? '';
        final type = payload['type'] as String? ?? 'task';
        final parent = payload['parent'] as String?;
        final priority = payload['priority'] as int?;

        if (title == null) {
          throw Exception('Mutation missing required field "title"');
        }

        await widget.appState.createIssue(
          title,
          description,
          type,
          parent: parent,
          priority: priority,
        );
        if (mounted) DialogUtils.showToast(context, message: 'Created new issue: "$title"');
      } else {
        throw Exception('Unsupported action type: $actionType');
      }

      // Remove the executed recommendation from list on successful completion
      if (mounted) {
        setState(() {
          _recommendations.removeAt(index);
        });
      }
    } catch (e) {
      if (mounted) {
        DialogUtils.showToast(context, message: e.toString(), isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _executingIndexes[index] = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Dynamic contrast colors compliant with WCAG (defined in GEMINI.md)
    final cardBgColor = MacosDynamicColor.resolve(
      CupertinoDynamicColor.withBrightness(
        color: const Color(0xFFF4F5F6), // light mode background
        darkColor: const Color(0xFF28282B), // dark mode background
      ),
      context,
    );

    final textColor = MacosDynamicColor.resolve(
      CupertinoDynamicColor.withBrightness(
        color: const Color(0xFF1A1A1A), // light mode text
        darkColor: const Color(0xFFF1F2F3), // dark mode text
      ),
      context,
    );

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: MacosColors.systemGrayColor.withValues(alpha: 0.2),
        ),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const MacosIcon(
                CupertinoIcons.sparkles,
                color: MacosColors.systemPurpleColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'AI Assistant Insights',
                style: MacosTheme.of(context).typography.title3.copyWith(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const Spacer(),
              if (!_isLoading && _error == null)
                PushButton(
                  controlSize: ControlSize.small,
                  secondary: true,
                  onPressed: _loadInsights,
                  child: const Row(
                    children: [
                      MacosIcon(CupertinoIcons.refresh, size: 12),
                      SizedBox(width: 4),
                      Text('Regenerate'),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24.0),
              child: Center(
                child: Column(
                  children: [
                    ProgressCircle(),
                    SizedBox(height: 12),
                    Text('Consulting Gemini AI Assistant...'),
                  ],
                ),
              ),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: MacosColors.systemRedColor,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 12),
                  PushButton(
                    controlSize: ControlSize.regular,
                    onPressed: _loadInsights,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          else ...[
            if (_summary != null) ...[
              Text(
                _summary!,
                style: MacosTheme.of(context).typography.body.copyWith(
                      color: textColor,
                      height: 1.4,
                    ),
              ),
              const SizedBox(height: 16),
            ],
            if (_recommendations.isNotEmpty) ...[
              Text(
                'Recommended Next Actions',
                style: MacosTheme.of(context).typography.headline.copyWith(
                      color: textColor,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _recommendations.length,
                itemBuilder: (context, index) {
                  final rec = _recommendations[index];
                  final isExecuting = _executingIndexes[index] ?? false;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: MacosTheme.of(context).brightness.isDark
                            ? const Color(0xFF1E1E1E)
                            : MacosColors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: MacosColors.systemGrayColor.withValues(alpha: 0.15),
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
                                  rec['title'] as String? ?? '',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  rec['description'] as String? ?? '',
                                  style: TextStyle(
                                    color: MacosColors.systemGrayColor,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Align(
                            alignment: Alignment.centerRight,
                            child: PushButton(
                              controlSize: ControlSize.regular,
                              onPressed: isExecuting ? null : () => _executeRecommendation(index, rec),
                              child: isExecuting
                                  ? const ProgressCircle(radius: 8)
                                  : const Text('Execute'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ] else ...[
              const Row(
                children: [
                  MacosIcon(
                    CupertinoIcons.checkmark_seal_fill,
                    color: MacosColors.systemGreenColor,
                    size: 16,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'No outstanding recommendations. Project is in peak health!',
                    style: TextStyle(
                      color: MacosColors.systemGreenColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}
