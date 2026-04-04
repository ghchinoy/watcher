import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:firebase_core/firebase_core.dart';
import 'state/app_state.dart';
import 'router.dart';
import 'firebase_options.dart';

final appState = AppState();

Future<void> _configureMacosWindowUtils() async {
  const config = MacosWindowUtilsConfig();
  await config.apply();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _configureMacosWindowUtils();
  
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase initialization failed: $e');
  }

  runApp(const WatcherApp());
}

class WatcherApp extends StatelessWidget {
  const WatcherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        return PlatformMenuBar(
          menus: [
            PlatformMenu(
              label: 'Watcher',
              menus: [
                PlatformMenuItemGroup(
                  members: [
                    if (PlatformProvidedMenuItem.hasMenu(
                      PlatformProvidedMenuItemType.about,
                    ))
                      const PlatformProvidedMenuItem(
                        type: PlatformProvidedMenuItemType.about,
                      ),
                  ],
                ),
                PlatformMenuItemGroup(
                  members: [
                    PlatformMenuItem(
                      label: 'Settings...',
                      shortcut: const SingleActivator(
                        LogicalKeyboardKey.comma,
                        meta: true,
                      ),
                      onSelected: () => appRouter.go('/settings'),
                    ),
                  ],
                ),
                PlatformMenuItemGroup(
                  members: [
                    if (PlatformProvidedMenuItem.hasMenu(
                      PlatformProvidedMenuItemType.servicesSubmenu,
                    ))
                      const PlatformProvidedMenuItem(
                        type: PlatformProvidedMenuItemType.servicesSubmenu,
                      ),
                  ],
                ),
                PlatformMenuItemGroup(
                  members: [
                    if (PlatformProvidedMenuItem.hasMenu(
                      PlatformProvidedMenuItemType.hide,
                    ))
                      const PlatformProvidedMenuItem(
                        type: PlatformProvidedMenuItemType.hide,
                      ),
                    if (PlatformProvidedMenuItem.hasMenu(
                      PlatformProvidedMenuItemType.hideOtherApplications,
                    ))
                      const PlatformProvidedMenuItem(
                        type: PlatformProvidedMenuItemType.hideOtherApplications,
                      ),
                    if (PlatformProvidedMenuItem.hasMenu(
                      PlatformProvidedMenuItemType.showAllApplications,
                    ))
                      const PlatformProvidedMenuItem(
                        type: PlatformProvidedMenuItemType.showAllApplications,
                      ),
                  ],
                ),
                PlatformMenuItemGroup(
                  members: [
                    if (PlatformProvidedMenuItem.hasMenu(
                      PlatformProvidedMenuItemType.quit,
                    ))
                      const PlatformProvidedMenuItem(
                        type: PlatformProvidedMenuItemType.quit,
                      ),
                  ],
                ),
              ],
            ),
            const PlatformMenu(
              label: 'Edit',
              menus: [
                PlatformMenuItemGroup(
                  members: [
                    PlatformMenuItem(
                      label: 'Undo',
                      shortcut:
                          SingleActivator(LogicalKeyboardKey.keyZ, meta: true),
                      onSelected: null, // OS handles shortcut
                    ),
                    PlatformMenuItem(
                      label: 'Redo',
                      shortcut: SingleActivator(
                        LogicalKeyboardKey.keyZ,
                        meta: true,
                        shift: true,
                      ),
                      onSelected: null, // OS handles shortcut
                    ),
                  ],
                ),
                PlatformMenuItemGroup(
                  members: [
                    PlatformMenuItem(
                      label: 'Cut',
                      shortcut:
                          SingleActivator(LogicalKeyboardKey.keyX, meta: true),
                      onSelected: null,
                    ),
                    PlatformMenuItem(
                      label: 'Copy',
                      shortcut:
                          SingleActivator(LogicalKeyboardKey.keyC, meta: true),
                      onSelected: null,
                    ),
                    PlatformMenuItem(
                      label: 'Paste',
                      shortcut:
                          SingleActivator(LogicalKeyboardKey.keyV, meta: true),
                      onSelected: null,
                    ),
                    PlatformMenuItem(
                      label: 'Select All',
                      shortcut:
                          SingleActivator(LogicalKeyboardKey.keyA, meta: true),
                      onSelected: null,
                    ),
                  ],
                ),
              ],
            ),
            PlatformMenu(
              label: 'Window',
              menus: [
                if (PlatformProvidedMenuItem.hasMenu(
                  PlatformProvidedMenuItemType.minimizeWindow,
                ))
                  const PlatformProvidedMenuItem(
                    type: PlatformProvidedMenuItemType.minimizeWindow,
                  ),
                if (PlatformProvidedMenuItem.hasMenu(
                  PlatformProvidedMenuItemType.zoomWindow,
                ))
                  const PlatformProvidedMenuItem(
                    type: PlatformProvidedMenuItemType.zoomWindow,
                  ),
                if (PlatformProvidedMenuItem.hasMenu(
                  PlatformProvidedMenuItemType.arrangeWindowsInFront,
                ))
                  const PlatformProvidedMenuItem(
                    type: PlatformProvidedMenuItemType.arrangeWindowsInFront,
                  ),
              ],
            ),
          ],
          child: Shortcuts(
            shortcuts: <ShortcutActivator, Intent>{
              const SingleActivator(
                LogicalKeyboardKey.comma,
                control: false,
                alt: false,
                shift: false,
                meta: true,
              ): const _OpenSettingsIntent(),
            },
            child: Actions(
              actions: <Type, Action<Intent>>{
                _OpenSettingsIntent: CallbackAction<_OpenSettingsIntent>(
                  onInvoke: (intent) => appRouter.go('/settings'),
                ),
              },
              child: MacosApp.router(
                title: 'Beads Watcher',
                theme: MacosThemeData.light(),
                darkTheme: MacosThemeData.dark(),
                themeMode: ThemeMode.system,
                routerConfig: appRouter,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _OpenSettingsIntent extends Intent {
  const _OpenSettingsIntent();
}
