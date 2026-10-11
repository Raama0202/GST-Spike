import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../features/announcements/announcements_screen.dart';
import '../features/auth/auth.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/profile_screen.dart';
import '../features/branches/branches_screen.dart';
import '../features/categories/categories_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/employees/employees_screen.dart';
import '../features/invoices/invoices.dart';
import '../features/itc/itc_screen.dart';
import '../features/settings/settings_screen.dart';
import 'admin_shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authProvider);
  return GoRouter(
    initialLocation: '/dashboard',
    redirect: (context, state) {
      if (auth.isLoading) {
        return state.uri.path == '/loading' ? null : '/loading';
      }
      final session = auth.value;
      final atLogin = state.uri.path == '/login';
      if (session == null) return atLogin ? null : '/login';
      if (atLogin || state.uri.path == '/loading') return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(path: '/loading', builder: (_, _) => const _LoadingScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      ShellRoute(
        builder: (context, state, child) {
          final session = auth.value;
          if (session == null) return const _LoadingScreen();
          return AdminShell(session: session, child: child);
        },
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (_, _) => const DashboardScreen(),
          ),
          GoRoute(path: '/invoices', builder: (_, _) => const InvoicesScreen()),
          GoRoute(
            path: '/invoices/:id',
            builder: (_, state) =>
                InvoiceDetailScreen(invoiceId: state.pathParameters['id']!),
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
          GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
        ],
      ),
    ],
  );
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
