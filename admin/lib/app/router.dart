import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/session.dart';
import '../features/activity/activity_screen.dart';
import '../features/announcements/announcements_screen.dart';
import '../features/auth/auth.dart';
import '../features/auth/blocked_screen.dart';
import '../features/auth/forgot_password_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/profile_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/branches/branches_screen.dart';
import '../features/categories/categories_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/employees/employees_screen.dart';
import '../features/invoices/invoice_detail_screen.dart';
import '../features/invoices/invoices_screen.dart';
import '../features/itc/itc_screen.dart';
import '../features/settings/settings_screen.dart';
import 'admin_shell.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

const _signedOutPaths = {'/login', '/register', '/forgot-password'};

class _RouterRefresh extends ChangeNotifier {
  void refresh() => notifyListeners();
}

/// Built once; auth and account-block changes re-run [GoRouter.redirect]
/// instead of recreating the router (which would reset navigation).
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh();
  ref.listen(authProvider, (_, _) => refresh.refresh());
  ref.listen(accountBlockProvider, (_, _) => refresh.refresh());

  final router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/dashboard',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final block = ref.read(accountBlockProvider);
      final path = state.uri.path;
      if (block != null) return path == '/blocked' ? null : '/blocked';
      if (!auth.hasValue && auth.isLoading) {
        return path == '/loading' ? null : '/loading';
      }
      final signedIn = auth.value != null;
      if (!signedIn) return _signedOutPaths.contains(path) ? null : '/login';
      if (_signedOutPaths.contains(path) ||
          path == '/loading' ||
          path == '/blocked') {
        return '/dashboard';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/loading', builder: (_, _) => const _LoadingScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
      GoRoute(
        path: '/forgot-password',
        builder: (_, state) =>
            ForgotPasswordScreen(initialEmail: state.extra as String?),
      ),
      GoRoute(path: '/blocked', builder: (_, _) => const BlockedScreen()),
      ShellRoute(
        builder: (context, state, child) => AdminShell(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (_, _) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/invoices',
            builder: (_, _) => const InvoicesScreen(),
            routes: [
              // Full-screen above the shell so Android back returns to the list.
              GoRoute(
                path: ':id',
                parentNavigatorKey: _rootNavigatorKey,
                builder: (_, state) =>
                    InvoiceDetailScreen(invoiceId: state.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(path: '/itc', builder: (_, _) => const ItcScreen()),
          GoRoute(
            path: '/employees',
            builder: (_, _) => const EmployeesScreen(),
          ),
          GoRoute(
            path: '/categories',
            builder: (_, _) => const CategoriesScreen(),
          ),
          GoRoute(path: '/branches', builder: (_, _) => const BranchesScreen()),
          GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
          GoRoute(
            path: '/announcements',
            builder: (_, _) => const AnnouncementsScreen(),
          ),
          GoRoute(path: '/activity', builder: (_, _) => const ActivityScreen()),
          GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
        ],
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();
  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: SizedBox.square(dimension: 32, child: CircularProgressIndicator()),
    ),
  );
}
