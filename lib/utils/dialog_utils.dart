import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';

/// Shared alert helpers (REL-01).
///
/// Fire-and-forget UI mutations (updateIssue, removeProject, drag-and-drop
/// reparenting/status changes) previously swallowed failures, so a user could
/// perform an action, see nothing happen, and not know why. These helpers give
/// those call sites a consistent native failure alert.
class DialogUtils {
  DialogUtils._();

  /// Shows a native macOS error alert. Safe to call after an `await`: callers
  /// should guard with a `context.mounted` check first.
  static Future<void> showError(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    return showMacosAlertDialog(
      context: context,
      builder: (context) => MacosAlertDialog(
        appIcon: const MacosIcon(
          CupertinoIcons.exclamationmark_triangle_fill,
          size: 56,
          color: MacosColors.systemRedColor,
        ),
        title: Text(title),
        message: Text(
          message,
          textAlign: TextAlign.center,
          style: MacosTheme.of(context).typography.body,
        ),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ),
    );
  }
}
