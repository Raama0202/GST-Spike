import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/glass.dart';
import '../features/auth/auth.dart';

class _Destination {
  const _Destination(this.label, this.icon, this.location);
  final String label;
  final IconData icon;
  final String location;
}

class AdminShell extends StatelessWidget {
  const AdminShell({super.key, required this.session, required this.child});
  final AdminSession session;
  final Widget child;

  static const _destinations = [
    _Destination('Dashboard', Icons.dashboard_outlined, '/dashboard'),
    _Destination('Invoices', Icons.receipt_long_outlined, '/invoices'),
    _Destination('ITC', Icons.compare_arrows_outlined, '/itc'),
    _Destination('Employees', Icons.people_outline, '/employees'),
    _Destination('Categories', Icons.category_outlined, '/categories'),
    _Destination('Branches', Icons.location_on_outlined, '/branches'),
    _Destination('Announcements', Icons.campaign_outlined, '/announcements'),
    _Destination('Settings', Icons.settings_outlined, '/settings'),
    _Destination('Profile', Icons.account_circle_outlined, '/profile'),
  ];

  int _selected(String path) {
    final index = _destinations.indexWhere(
      (d) => path == d.location || path.startsWith('${d.location}/'),
    );
    return index < 0 ? 0 : index;
  }

  @override
  Widget build(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    final selected = _selected(path);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final compactDestinations = _destinations.take(5).toList();
    final compactSelected = selected >= compactDestinations.length
        ? 0
        : selected;
    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: selected,
              onDestinationSelected: (index) =>
                  context.go(_destinations[index].location),
              extended: MediaQuery.sizeOf(context).width >= 1180,
              minExtendedWidth: 220,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const IconBadge(
                      icon: Icons.receipt_long_rounded,
                      color: Brand.primary,
                      size: 40,
                    ),
                    if (MediaQuery.sizeOf(context).width >= 1180) ...[
                      const SizedBox(width: 10),
                      const Text(
                        'GST Expense Admin',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    label: Text(d.label),
                  ),
              ],
            ),
            VerticalDivider(
              width: 1,
              color: Colors.white.withValues(alpha: 0.8),
            ),
            Expanded(child: child),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            const IconBadge(
              icon: Icons.receipt_long_rounded,
              color: Brand.primary,
              size: 34,
            ),
            const SizedBox(width: 10),
            const Flexible(
              child: Text('GST Expense Admin', overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GlassIconButton(
              icon: Icons.person_outline_rounded,
              tooltip: 'Profile',
              onPressed: () => context.go('/profile'),
            ),
          ),
        ],
      ),
      drawer: NavigationDrawer(
        selectedIndex: selected,
        onDestinationSelected: (index) {
          Navigator.pop(context);
          context.go(_destinations[index].location);
        },
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 16, 20),
            child: Row(
              children: [
                const IconBadge(
                  icon: Icons.receipt_long_rounded,
                  color: Brand.primary,
                  size: 44,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'GST Expense Admin',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
          ),
          for (final d in _destinations)
            NavigationDrawerDestination(
              icon: Icon(d.icon),
              label: Text(d.label),
            ),
        ],
      ),
      body: child,
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: DecoratedBox(
              decoration: glassDecoration(radius: 28, opacity: 0.7),
              child: NavigationBar(
                selectedIndex: compactSelected,
                onDestinationSelected: (index) =>
                    context.go(compactDestinations[index].location),
                labelBehavior:
                    NavigationDestinationLabelBehavior.onlyShowSelected,
                destinations: [
                  for (final d in compactDestinations)
                    NavigationDestination(icon: Icon(d.icon), label: d.label),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
