import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import '../models/issue.dart';
import '../state/app_state.dart';

class HealthCheckModal extends StatefulWidget {
  final AppState appState;

  const HealthCheckModal({super.key, required this.appState});

  @override
  State<HealthCheckModal> createState() => _HealthCheckModalState();
}

class _HealthCheckModalState extends State<HealthCheckModal> {
  late Future<HealthCheckResult> _healthCheckFuture;

  @override
  void initState() {
    super.initState();
    _healthCheckFuture = widget.appState.checkHealth();
  }

  @override
  Widget build(BuildContext context) {
    return MacosSheet(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const MacosIcon(CupertinoIcons.heart_fill, color: MacosColors.systemRedColor),
                const SizedBox(width: 12),
                Text(
                  'Project Health Check',
                  style: MacosTheme.of(context).typography.largeTitle,
                ),
                const Spacer(),
                PushButton(
                  controlSize: ControlSize.regular,
                  secondary: true,
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Structural analysis of the beads dependency graph.',
              style: MacosTheme.of(context).typography.body.copyWith(
                    color: MacosColors.systemGrayColor,
                  ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: FutureBuilder<HealthCheckResult>(
                future: _healthCheckFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: ProgressCircle());
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Health Check Failed: ${snapshot.error}',
                        style: const TextStyle(color: MacosColors.systemRedColor),
                      ),
                    );
                  }

                  final result = snapshot.data!;
                  if (result.diagnostics.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const MacosIcon(
                            CupertinoIcons.checkmark_circle_fill,
                            color: MacosColors.systemGreenColor,
                            size: 48,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Your project is healthy!',
                            style: MacosTheme.of(context).typography.headline,
                          ),
                          const SizedBox(height: 8),
                          const Text('No structural issues or circular dependencies found.'),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: result.diagnostics.length,
                    itemBuilder: (context, index) {
                      final diag = result.diagnostics[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: MacosDynamicColor.resolve(
                              MacosColors.controlBackgroundColor,
                              context,
                            ),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: MacosColors.systemGrayColor.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  MacosIcon(
                                    diag.type == 'cycle'
                                        ? CupertinoIcons.arrow_2_circlepath
                                        : CupertinoIcons.exclamationmark_triangle_fill,
                                    color: MacosColors.systemOrangeColor,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    diag.issueId,
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: MacosColors.systemOrangeColor.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      diag.type.toUpperCase().replaceAll('_', ' '),
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: MacosColors.systemOrangeColor,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                diag.message,
                                style: MacosTheme.of(context).typography.body,
                              ),
                              if (diag.fix != null) ...[
                                const SizedBox(height: 16),
                                const Text(
                                  'Suggested Fix:',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: MacosColors.systemGrayColor,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: MacosColors.black.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    diag.fix!,
                                    style: const TextStyle(
                                      fontFamily: 'SF Mono',
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
