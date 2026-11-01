import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/glass.dart';

class _Destination {
  const _Destination(this.label, this.icon, this.location);
  final String label;
  final IconData icon;
  final String location;
}

/// Phones: four primary tabs plus a "More" sheet. Tablets/desktop: a rail
/// with every destination.
class AdminShell extends StatelessWidget {
  const AdminShell({super.key, required this.child});
  final Widget child;

  static const _primary = [
    _Destination('Dashboard', Icons.dashboard_outlined, '/dashboard'),
    _Destination('Invoices', Icons.receipt_long_outlined, '/invoices'),
    _Destination('ITC', Icons.compare_arrows_outlined, '/itc'),
    _Destination('Employees', Icons.people_outline, '/employees'),
  ];

  static const _more = [
    _Destination('Categories', Icons.category_outlined, '/categories'),
    _Destination('Branches', Icons.location_on_outlined, '/branches'),
    _Destination('Announcements', Icons.campaign_outlined, '/announcements'),
    _Destination('Activity log', Icons.history_rounded, '/activity'),
    _Destination('Settings', Icons.settings_outlined, '/settings'),
    _Destination('Profile', Icons.account_circle_outlined, '/profile'),
  ];

  static const _all = [..._primary, ..._more];

  static int _indexIn(List<_Destination> list, String path) => list.indexWhere(
    (d) => path == d.location || path.startsWith('${d.location}/'),
  );

  void _showMore(BuildContext context, String path) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          children: [
            for (final d in _more)
              ListTile(
                leading: Icon(d.icon),
                title: Text(d.label),
                selected: _indexIn([d], path) == 0,
                onTap: () {
                  Navigator.pop(sheetContext);
                  context.go(d.location);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    final width = MediaQuery.sizeOf(context).width;
    final dark = isDarkTheme(context);
    // Shell tabs replace each other, so Android back returns to the
    // dashboard before it leaves the app.
    final content = PopScope(
      canPop: path == '/dashboard',
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go('/dashboard');
      },
      child: child,
    );
    if (width >= 900) {
      final selected = _indexIn(_all, path);
      final extended = width >= 1180;
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: selected < 0 ? null : selected,
              onDestinationSelected: (index) =>
                  context.go(_all[index].location),
              extended: extended,
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
                    if (extended) ...[
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
                for (final d in _all)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    label: Text(d.label),
                  ),
              ],
            ),
            VerticalDivider(width: 1, color: Theme.of(context).dividerColor),
            Expanded(child: content),
          ],
        ),
      );
    }
    final primaryIndex = _indexIn(_primary, path);
    final selected = primaryIndex < 0 ? _primary.length : primaryIndex;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const Row(
          children: [
            IconBadge(
              icon: Icons.receipt_long_rounded,
              color: Brand.primary,
              size: 34,
            ),
            SizedBox(width: 10),
            Flexible(
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
      body: content,
      // Solid translucent fill: a BackdropFilter here re-blurs the page on
      // every scroll frame, which stutters on low-end Android phones.
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            color: dark
                ? const Color(0xFF172033).withValues(alpha: 0.96)
                : Colors.white.withValues(alpha: 0.94),
            border: Border.all(
              color: Colors.white.withValues(alpha: dark ? 0.1 : 0.9),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A000000),
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: NavigationBar(
              selectedIndex: selected,
              onDestinationSelected: (index) => index == _primary.length
                  ? _showMore(context, path)
                  : context.go(_primary[index].location),
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              destinations: [
                for (final d in _primary)
                  NavigationDestination(icon: Icon(d.icon), label: d.label),
                const NavigationDestination(
                  icon: Icon(Icons.menu_rounded),
                  label: 'More',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
