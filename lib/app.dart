import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/app_update.dart';
import 'core/config.dart';
import 'core/theme.dart';
import 'features/admin/admin_screen.dart';
import 'features/people/people_screen.dart';
import 'features/attendance/attendance_screen.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/login_screen.dart';
import 'features/calls/calls_screen.dart';
import 'features/home/home_screen.dart';
import 'features/register/register_screen.dart';
import 'features/shell/app_shell.dart';

/// Tells go_router to re-check redirects whenever the signed-in user changes.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Ref ref) {
    ref.listen(authProvider, (_, _) => notifyListeners());
  }
}

/// Lets the update pop-up find the app's navigator from above the router.
final rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRefresh(ref);
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      if (auth.isLoading && !auth.hasValue) return null;
      final signedIn = auth.value != null;
      final onLogin = state.matchedLocation == '/login';
      if (!signedIn) return onLogin ? null : '/login';
      if (onLogin) return '/';
      if ((state.matchedLocation.startsWith('/admin') || state.matchedLocation.startsWith('/people')) && !(auth.value?.isAdmin ?? false)) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (c, s) => const LoginScreen()),
      ShellRoute(
        builder: (c, s, child) => AppShell(location: s.matchedLocation, child: child),
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (c, s) => const NoTransitionPage(child: HomeScreen()),
          ),
          GoRoute(
            path: '/attendance',
            pageBuilder: (c, s) => const NoTransitionPage(child: AttendanceScreen()),
          ),
          GoRoute(
            path: '/register',
            pageBuilder: (c, s) => const NoTransitionPage(child: RegisterScreen()),
          ),
          GoRoute(
            path: '/calls',
            pageBuilder: (c, s) => const NoTransitionPage(child: CallsScreen()),
          ),
          GoRoute(
            path: '/people',
            pageBuilder: (c, s) => const NoTransitionPage(child: PeopleScreen()),
          ),
          GoRoute(
            path: '/admin',
            pageBuilder: (c, s) => const NoTransitionPage(child: AdminScreen()),
          ),
        ],
      ),
    ],
  );
});

class FolkApp extends ConsumerWidget {
  const FolkApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    // Splash while the saved session is being checked.
    if (auth.isLoading && !auth.hasValue) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    return MaterialApp.router(
      title: 'FOLK Tracker',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: kThemeMode,
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) => UpdateGate(navigatorKey: rootNavigatorKey, child: child ?? const SizedBox.shrink()),
    );
  }
}
