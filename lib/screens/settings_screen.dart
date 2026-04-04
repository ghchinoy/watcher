import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show ReorderableListView, ReorderableDragStartListener, ListTile, Material;
import 'package:macos_ui/macos_ui.dart';
import 'package:go_router/go_router.dart';
import '../main.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _actorController;

  @override
  void initState() {
    super.initState();
    _actorController = TextEditingController(text: appState.actorName);
  }

  @override
  void dispose() {
    _actorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        return MacosScaffold(
          toolBar: ToolBar(
            title: const Text('Settings'),
            titleWidth: 150.0,
            leading: MacosTooltip(
              message: 'Back to Dashboard',
              useMousePosition: false,
              child: MacosIconButton(
                icon: const MacosIcon(
                  CupertinoIcons.back,
                  size: 20,
                ),
                boxConstraints: const BoxConstraints(
                  minHeight: 20,
                  minWidth: 20,
                  maxWidth: 48,
                  maxHeight: 38,
                ),
                onPressed: () {
                  context.go('/');
                },
              ),
            ),
          ),
          children: [
            ContentArea(
              builder: (context, scrollController) {
                return SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(40.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'User Identity',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'How your actions appear in the Activity Ticker and the database.',
                        style: MacosTheme.of(context).typography.footnote.copyWith(
                              color: MacosColors.systemGrayColor,
                            ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: 300,
                        child: MacosTextField(
                          controller: _actorController,
                          placeholder: 'e.g., Jane Doe',
                          onChanged: (value) {
                            appState.setActorName(value);
                          },
                        ),
                      ),
                      const SizedBox(height: 40),
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
                      SizedBox(
                        width: 300,
                        child: MacosPopupButton<int>(
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
                      ),
                      const SizedBox(height: 40),
                      const Text(
                        'Preferred Terminal',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Which terminal app should open when executing AI tasks?',
                        style: MacosTheme.of(context).typography.footnote.copyWith(
                              color: MacosColors.systemGrayColor,
                            ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: 300,
                        child: MacosPopupButton<String>(
                          value: appState.preferredTerminal,
                          onChanged: (String? newValue) {
                            if (newValue != null) {
                              appState.setPreferredTerminal(newValue);
                            }
                          },
                          items: const [
                            MacosPopupMenuItem(
                              value: 'Ghostty',
                              child: Text('Ghostty'),
                            ),
                            MacosPopupMenuItem(
                              value: 'iTerm2',
                              child: Text('iTerm2'),
                            ),
                            MacosPopupMenuItem(
                              value: 'Terminal',
                              child: Text('Terminal.app'),
                            ),
                          ],
                        ),
                      ),
                      if (appState.preferredTerminal == 'Ghostty') ...[
                        const SizedBox(height: 16),
                        const Text(
                          'Ghostty Custom Settings',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Theme',
                                    style: MacosTheme.of(context).typography.footnote.copyWith(
                                          color: MacosColors.systemGrayColor,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  MacosTextField(
                                    placeholder: 'e.g. catppuccin-mocha',
                                    onChanged: appState.setGhosttyTheme,
                                    controller: TextEditingController(text: appState.ghosttyTheme),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Font Family',
                                    style: MacosTheme.of(context).typography.footnote.copyWith(
                                          color: MacosColors.systemGrayColor,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  MacosTextField(
                                    placeholder: 'e.g. JetBrains Mono',
                                    onChanged: appState.setGhosttyFontFamily,
                                    controller: TextEditingController(text: appState.ghosttyFontFamily),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 40),
                      const Text(
                        'Gemini & Vertex AI',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'GCP Project ID',
                                  style: MacosTheme.of(context).typography.footnote.copyWith(
                                        color: MacosColors.systemGrayColor,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                MacosTextField(
                                  placeholder: 'e.g. my-project-id',
                                  onChanged: appState.setGcpProjectId,
                                  controller: TextEditingController(text: appState.gcpProjectId),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Vertex Location',
                                  style: MacosTheme.of(context).typography.footnote.copyWith(
                                        color: MacosColors.systemGrayColor,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                MacosTextField(
                                  placeholder: 'e.g. us-central1 or global',
                                  onChanged: appState.setVertexLocation,
                                  controller: TextEditingController(text: appState.vertexLocation),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Gemini Model',
                            style: MacosTheme.of(context).typography.footnote.copyWith(
                                  color: MacosColors.systemGrayColor,
                                ),
                          ),
                          const SizedBox(height: 4),
                          SizedBox(
                            width: 300,
                            child: MacosPopupButton<String>(
                              value: appState.geminiModel,
                              onChanged: (String? value) {
                                if (value != null) appState.setGeminiModel(value);
                              },
                              items: const [
                                MacosPopupMenuItem(
                                  value: 'gemini-3-flash-preview',
                                  child: Text('Gemini 3 Flash (Preview)'),
                                ),
                                MacosPopupMenuItem(
                                  value: 'gemini-2.5-flash',
                                  child: Text('Gemini 2.5 Flash'),
                                ),
                                MacosPopupMenuItem(
                                  value: 'gemini-2.5-flash-lite-preview',
                                  child: Text('Gemini 2.5 Flash Lite (Preview)'),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Note: Preview models will automatically set location to "global".',
                            style: MacosTheme.of(context).typography.caption1.copyWith(
                                  color: MacosColors.systemGrayColor,
                                  fontStyle: FontStyle.italic,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 40),
                      const Text(
                        'Project Order',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Drag to reorder your projects in the sidebar.',
                        style: MacosTheme.of(context).typography.footnote.copyWith(
                              color: MacosColors.systemGrayColor,
                            ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: 300,
                        constraints: const BoxConstraints(maxHeight: 400),
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
                        child: ReorderableListView(
                          shrinkWrap: true,
                          buildDefaultDragHandles: false,
                          proxyDecorator: (Widget child, int index, Animation<double> animation) {
                            return Material(
                              color: MacosColors.transparent,
                              elevation: 0.0,
                              child: child,
                            );
                          },
                          onReorderItem: (oldIndex, newIndex) {
                            // ReorderableListView.onReorderItem already adjusts the index!
                            // If we use this modern API, we don't need the manual -1 adjustment
                            // in the appState.reorderProjects method. Let's pass a flag or adjust.
                            // Actually, onReorderItem provides the EXACT post-removal index.
                            // So we should update appState.reorderProjects to accept absolute indexes,
                            // or just use the legacy onReorder and ignore the warning for now.
                            appState.reorderProjects(oldIndex, newIndex, isAdjusted: true);
                          },
                          children: appState.projects.asMap().entries.map((entry) {
                            final index = entry.key;
                            final project = entry.value;
                            return Material(
                              key: ValueKey(project.path),
                              color: MacosColors.transparent,
                              child: ListTile(
                                hoverColor: MacosColors.transparent,
                                selectedTileColor: MacosColors.transparent,
                                selectedColor: MacosColors.transparent,
                                dense: true,
                                title: Text(
                                  project.name,
                                  style: MacosTheme.of(context).typography.body,
                                ),
                                trailing: ReorderableDragStartListener(
                                  index: index,
                                  child: const MacosIcon(
                                    CupertinoIcons.bars,
                                    color: MacosColors.systemGrayColor,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 40),
                      const Text(
                        'System Information',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Watcher App Version',
                                  style: MacosTheme.of(context).typography.footnote.copyWith(
                                    color: MacosColors.systemGrayColor,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  appState.appVersion ?? "Unknown",
                                  style: MacosTheme.of(context).typography.body,
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Embedded Daemon Version',
                                  style: MacosTheme.of(context).typography.footnote.copyWith(
                                    color: MacosColors.systemGrayColor,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  appState.daemonVersion ?? "Unknown",
                                  style: MacosTheme.of(context).typography.body,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Local bd CLI Version',
                                  style: MacosTheme.of(context).typography.footnote.copyWith(
                                    color: MacosColors.systemGrayColor,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  appState.cliVersion ?? "Not installed or unavailable",
                                  style: MacosTheme.of(context).typography.body,
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Upstream Beads Version',
                                  style: MacosTheme.of(context).typography.footnote.copyWith(
                                    color: MacosColors.systemGrayColor,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  appState.upstreamVersion ?? "Checking...",
                                  style: MacosTheme.of(context).typography.body,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (appState.daemonVersion != null && appState.cliVersion != null && appState.daemonVersion != appState.cliVersion)
                        Padding(
                          padding: const EdgeInsets.only(top: 12.0),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: MacosColors.systemYellowColor.withValues(alpha: 0.1),
                              border: Border.all(color: MacosColors.systemYellowColor),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              children: [
                                const MacosIcon(CupertinoIcons.exclamationmark_triangle_fill, color: MacosColors.systemYellowColor),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Version Mismatch: Your embedded daemon and local CLI are running different versions. This may cause synchronization issues or errors reading newer schema changes.',
                                    style: MacosTheme.of(context).typography.footnote,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (appState.upstreamVersion != null && appState.daemonVersion != null && appState.upstreamVersion != appState.daemonVersion)
                        Padding(
                          padding: const EdgeInsets.only(top: 12.0),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: MacosColors.systemBlueColor.withValues(alpha: 0.1),
                              border: Border.all(color: MacosColors.systemBlueColor),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              children: [
                                const MacosIcon(CupertinoIcons.info_circle_fill, color: MacosColors.systemBlueColor),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Update Available: A newer version of beads (${appState.upstreamVersion}) is available upstream. Consider rebuilding Watcher to bundle the latest daemon.',
                                    style: MacosTheme.of(context).typography.footnote,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      Text(
                        'Database backend: Dolt SQL',
                        style: MacosTheme.of(context).typography.body,
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}