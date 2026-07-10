import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectableText;
import 'package:flutter/services.dart';
import 'package:macos_ui/macos_ui.dart';

class ErrorDisplayView extends StatefulWidget {
  final String error;
  final VoidCallback? onRetry;

  const ErrorDisplayView({
    super.key,
    required this.error,
    this.onRetry,
  });

  @override
  State<ErrorDisplayView> createState() => _ErrorDisplayViewState();
}

class _ErrorDisplayViewState extends State<ErrorDisplayView> {
  bool _copied = false;

  void _copyError() async {
    await Clipboard.setData(ClipboardData(text: widget.error));
    if (mounted) {
      setState(() => _copied = true);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() => _copied = false);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          padding: const EdgeInsets.all(20.0),
          decoration: BoxDecoration(
            color: MacosDynamicColor.resolve(
              MacosColors.controlBackgroundColor,
              context,
            ),
            borderRadius: BorderRadius.circular(8.0),
            border: Border.all(
              color: MacosColors.systemRedColor.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const MacosIcon(
                CupertinoIcons.exclamationmark_triangle_fill,
                size: 36,
                color: MacosColors.systemRedColor,
              ),
              const SizedBox(height: 12),
              Text(
                'An Error Occurred',
                style: MacosTheme.of(context).typography.headline.copyWith(
                  color: MacosColors.systemRedColor,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: MacosDynamicColor.resolve(
                    MacosColors.alternatingContentBackgroundColor,
                    context,
                  ),
                  borderRadius: BorderRadius.circular(6.0),
                ),
                child: SelectableText(
                  widget.error,
                  style: MacosTheme.of(context).typography.body.copyWith(
                    fontFamily: 'CupertinoSystemMonospaced',
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.left,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  PushButton(
                    controlSize: ControlSize.regular,
                    secondary: true,
                    onPressed: _copyError,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        MacosIcon(
                          _copied
                              ? CupertinoIcons.checkmark_alt
                              : CupertinoIcons.doc_on_clipboard,
                          size: 14,
                          color: _copied
                              ? MacosColors.systemGreenColor
                              : MacosTheme.of(context).typography.body.color,
                        ),
                        const SizedBox(width: 6),
                        Text(_copied ? 'Copied!' : 'Copy Error'),
                      ],
                    ),
                  ),
                  if (widget.onRetry != null) ...[
                    const SizedBox(width: 12),
                    PushButton(
                      controlSize: ControlSize.regular,
                      onPressed: widget.onRetry,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          MacosIcon(
                            CupertinoIcons.refresh,
                            size: 14,
                            color: MacosColors.white,
                          ),
                          SizedBox(width: 6),
                          Text('Retry'),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
