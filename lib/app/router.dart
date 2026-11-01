import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gst_expense_scanner/features/auth/domain/repositories/auth_repository.dart';
import 'package:gst_expense_scanner/features/auth/presentation/providers/auth_providers.dart';
import 'package:gst_expense_scanner/features/auth/presentation/screens/login_screen.dart';
import 'package:gst_expense_scanner/features/auth/presentation/screens/otp_screen.dart';
import 'package:gst_expense_scanner/features/home/presentation/screens/home_screen.dart';
import 'package:gst_expense_scanner/features/home/presentation/screens/splash_screen.dart';
import 'package:gst_expense_scanner/features/notifications/presentation/notifications_screen.dart';
import 'package:gst_expense_scanner/features/profile/presentation/screens/profile_screen.dart';
import 'package:gst_expense_scanner/features/review/presentation/screens/review_screen.dart';
import 'package:gst_expense_scanner/features/scanner/presentation/screens/scan_flow_screen.dart';
import 'package:gst_expense_scanner/features/uploads/presentation/screens/upload_detail_screen.dart';
import 'package:gst_expense_scanner/features/uploads/presentation/screens/uploads_screen.dart';

class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(this._ref) {
    _ref.listen(authStateProvider, (_, __) => notifyListeners());
  }

  final Ref _ref;
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefreshNotifier(ref);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authStateProvider);
      final location = state.matchedLocation;
      final isSplash = location == '/splash';
      final isAuthRoute = location == '/login' || location == '/otp';

      if (auth is AuthAuthenticating && isSplash) return null;

      if (auth is AuthAuthenticated) {
        if (isAuthRoute || isSplash) return '/home';
        return null;
      }

      if (auth is AuthUnauthenticated || auth is AuthErrorState) {
        if (isAuthRoute) return null;
        return '/login';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (_, __) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: '/otp',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return OtpScreen(
            mobile: extra['mobile'] as String? ?? '',
            rememberLogin: extra['rememberLogin'] as bool? ?? true,
            delivery: extra['delivery'] as OtpDelivery?,
          );
        },
      ),
      GoRoute(
        path: '/home',
        builder: (_, __) => const HomeScreen(),
      ),
      GoRoute(
        path: '/scan-processing',
        builder: (_, __) => const ScanFlowScreen(),
      ),
      GoRoute(
        path: '/review',
        builder: (_, __) => const ReviewScreen(),
      ),
      GoRoute(
        path: '/uploads',
        builder: (context, state) => UploadsScreen(
          initialFilter: state.uri.queryParameters['filter'],
        ),
        routes: [
          GoRoute(
            path: 'server/:serverId',
            builder: (context, state) => UploadDetailScreen.server(
              serverId: state.pathParameters['serverId']!,
            ),
          ),
          GoRoute(
            path: ':id',
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return UploadDetailScreen(localId: id);
            },
            routes: [
              GoRoute(
                path: 'resubmit',
                builder: (context, state) => ResubmitScreen(
                  localId: state.pathParameters['id']!,
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/profile',
        builder: (_, __) => const ProfileScreen(),
      ),
      GoRoute(
        path: '/notifications',
        builder: (_, __) => const NotificationsScreen(),
      ),
    ],
  );
});
