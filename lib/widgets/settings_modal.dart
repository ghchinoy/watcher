import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import '../state/app_state.dart';

class SettingsModal extends StatelessWidget {
  final AppState appState;

  const SettingsModal({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    return MacosScaffold(
      backgroundColor: MacosDynamicColor.resolve(MacosColors.windowBackgroundColor, context),
      children: [
        ContentArea(
          builder: (context, scrollController) {
            return Container(
              constraints: const BoxConstraints(maxWidth: 400),
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const MacosIcon(CupertinoIcons.settings, size: 24),
                      const SizedBox(width: 12),
                      Text(
                        'Global Settings',
                        style: MacosTheme.of(context).typography.title2,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Federation Sync Interval',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'How often should federated projects check the cloud for updates?',
                    style: MacosTheme.of(context).typography.footnote.copyWith(
                          color: MacosColors.systemGrayColor,
                        ),
                  ),
                  const SizedBox(height: 12),
                  MacosPopupButton<int>(
                    value: appState.syncIntervalMinutes,
                    onChanged: (int? newValue) {
                      if (newValue != null) {
                        appState.setSyncInterval(newValue);
                      }
                    },
                    items: const [
                      MacosPopupMenuItem(
                        value: 1,
                        child: Text('Every 1 minute'),
                      ),
                      MacosPopupMenuItem(
                        value: 5,
                        child: Text('Every 5 minutes'),
                      ),
                      MacosPopupMenuItem(
                        value: 15,
                        child: Text('Every 15 minutes'),
                      ),
                      MacosPopupMenuItem(
                        value: 60,
                        child: Text('Every hour'),
                      ),
                      MacosPopupMenuItem(
                        value: 0,
                        child: Text('Manual only (Disabled)'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      PushButton(
                        controlSize: ControlSize.regular,
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
