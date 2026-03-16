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