import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';

/// A11Y-02: wraps modal content so keyboard Tab/Shift-Tab traversal stays inside
/// the modal instead of leaking into the background screen's toolbar/sidebar.
///
/// Use as the root of a modal presented via `showMacosSheet` (which provides a
/// route barrier but no Tab trap). It creates a dedicated [FocusScope] that
/// requests focus on show and restores the previously-focused node on dismiss,
/// and a [FocusTraversalGroup] so Tab cycles only through this subtree.
class ModalFocusTrap extends StatefulWidget {
  final Widget child;
  const ModalFocusTrap({super.key, required this.child});

  @override
  State<ModalFocusTrap> createState() => _ModalFocusTrapState();
}

class _ModalFocusTrapState extends State<ModalFocusTrap> {
  final FocusScopeNode _scopeNode = FocusScopeNode();

  @override
  void initState() {
    super.initState();
    // Move focus into the modal once it is mounted so Tab starts inside it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scopeNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _scopeNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FocusScope(
      node: _scopeNode,
      child: FocusTraversalGroup(child: widget.child),
    );
  }
}

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
