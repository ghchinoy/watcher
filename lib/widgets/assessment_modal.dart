import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import '../services/planner_service.dart';
import '../state/app_state.dart';

class AssessmentModal extends StatefulWidget {
  final Project project;

  const AssessmentModal({super.key, required this.project});

  @override
  State<AssessmentModal> createState() => _AssessmentModalState();
}

class _AssessmentModalState extends State<AssessmentModal> {
  bool _isAssessing = true;
  bool _isFixing = false;
  bool _isExecuting = false;
  String? _assessmentMarkdown;
  String? _fixScriptMarkdown;
  String? _error;

  @override
  void initState() {
    super.initState();
    _runAssessment();
  }

  Future<void> _runAssessment() async {
    try {
      final result = await PlannerService.assessGraph(widget.project.path);
      if (mounted) {
        setState(() {
          _assessmentMarkdown = result;
          _isAssessing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isAssessing = false;
        });
      }
    }
  }

  Future<void> _generateFixScript() async {
    if (_assessmentMarkdown == null) return;

    setState(() {
      _isFixing = true;
      _error = null;
    });

    try {
      final script = await PlannerService.generateAutoFixScript(widget.project.path, _assessmentMarkdown!);
      if (mounted) {
        setState(() {
          _fixScriptMarkdown = script;
          _isFixing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Auto-fix generation failed: ${e.toString()}';
          _isFixing = false;
        });
      }
    }
  }

  Future<void> _executeFixScript() async {
    if (_fixScriptMarkdown == null) return;

    setState(() {
      _isExecuting = true;
      _error = null;
    });

    try {
      await PlannerService.executeScript(widget.project.path, _fixScriptMarkdown!);
      if (mounted) {
        Navigator.of(context).pop(); // Close the modal on success
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Execution failed: ${e.toString()}';
          _isExecuting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 600,
      height: 500,
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'AI Health Assessment',
                style: MacosTheme.of(context).typography.title1,
              ),
              MacosIconButton(
                icon: const MacosIcon(CupertinoIcons.clear),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_isAssessing)
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ProgressCircle(),
                    SizedBox(height: 16),
                    Text('Analyzing graph topology...'),
                  ],
                ),
              ),
            )
          else if (_error != null)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text('Error: $_error', style: const TextStyle(color: CupertinoColors.systemRed)),
                ),
              ),
            )
          else ...[
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: MacosDynamicColor.resolve(CupertinoColors.systemGrey6, context),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: MacosTheme.of(context).dividerColor),
                ),
                child: Markdown(
                  data: _fixScriptMarkdown ?? _assessmentMarkdown!,
                  selectable: true,
                  styleSheet: MarkdownStyleSheet(
                    p: MacosTheme.of(context).typography.body,
                    h1: MacosTheme.of(context).typography.title1,
                    h2: MacosTheme.of(context).typography.title2,
                    h3: MacosTheme.of(context).typography.title3,
                    code: TextStyle(
                      fontFamily: 'Courier',
                      backgroundColor: MacosDynamicColor.resolve(CupertinoColors.systemGrey4, context).withValues(alpha: 0.5),
                      color: MacosTheme.of(context).typography.body.color,
                    ),
                    codeblockPadding: const EdgeInsets.all(8),
                    codeblockDecoration: BoxDecoration(
                      color: MacosDynamicColor.resolve(CupertinoColors.systemGrey5, context),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Text('Error: $_error', style: const TextStyle(color: CupertinoColors.systemRed)),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_fixScriptMarkdown != null) ...[
                  PushButton(
                    controlSize: ControlSize.large,
                    secondary: true,
                    onPressed: () {
                      setState(() {
                        _fixScriptMarkdown = null; // Go back to assessment
                      });
                    },
                    child: const Text('Back'),
                  ),
                  const SizedBox(width: 12),
                  PushButton(
                    controlSize: ControlSize.large,
                    onPressed: _isExecuting ? null : _executeFixScript,
                    child: _isExecuting 
                        ? const ProgressCircle(radius: 8) 
                        : const Text('Approve & Execute Fixes'),
                  ),
                ] else ...[
                  PushButton(
                    controlSize: ControlSize.large,
                    secondary: true,
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                  const SizedBox(width: 12),
                  PushButton(
                    controlSize: ControlSize.large,
                    onPressed: _isFixing ? null : _generateFixScript,
                    child: _isFixing 
                        ? const ProgressCircle(radius: 8) 
                        : const Text('Generate Fix Script'),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}
