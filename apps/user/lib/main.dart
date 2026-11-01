import 'package:flutter/services.dart';
import 'package:x9_core/x9_core.dart';

import 'app.dart';
import 'services/push.dart';
import 'state/app_state.dart';

/// Starts through [runX9App]: every init step is guarded (try/catch + 5 s timeout) and runApp() is always
/// reached, so a failing plugin or an unreachable server can never leave a blank screen.
Future<void> main() async {
  Api.instance.appName = 'user';
  Api.instance.appVersion = '1.3.0';
  await runX9App(
    app: () => const X9UserApp(),
    navigatorKey: rootNavKey,
    stepNames: const ['session', 'app lock', 'theme', 'push', 'orientation'],
    initSteps: [
      () async {
        try {
          await SessionStore.instance.load();
        } catch (_) {
          // Corrupt secure storage (e.g. after a backup restore): start signed out.
          try {
            await SessionStore.instance.clear();
          } catch (_) {}
        }
      },
      () => AppLock.instance.load(),
      () => ThemeController.instance.load(), // saved Light / Dark / System choice (default Light)
      () => PushService.instance.init(),
      () => SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]),
    ],
  );
}
