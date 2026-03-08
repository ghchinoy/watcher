import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import 'state/app_state.dart';
import 'router.dart';

final appState = AppState();

Future<void> _configureMacosWindowUtils() async {
  const config = MacosWindowUtilsConfig();
  await config.apply();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _configureMacosWindowUtils();
  runApp(const WatcherApp());
}

class WatcherApp extends StatelessWidget {
  const WatcherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        return MacosApp.router(
          title: 'Beads Watcher',
          theme: MacosThemeData.light(),
          darkTheme: MacosThemeData.dark(),
          themeMode: ThemeMode.system,
          routerConfig: appRouter,
        );
      },
    );
  }
}
