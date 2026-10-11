import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_palette.dart';
import '../../core/theme_controller.dart';
import '../screens/insights_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/trash_screen.dart';
import 'appearance_sheet.dart';
import 'frosted_surface.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.watch<ThemeController>().palette;

    return Drawer(
      child: FrostedSurface(
        color: palette.surfaceElevated,
        borderRadius: BorderRadius.zero,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: palette.outline),
                      ),
                      clipBehavior: Clip.antiAlias,
                      padding: const EdgeInsets.all(4),
                      child: Image.asset('assets/icon/app_icon.png'),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Arast',
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Plan it. Do it. Rest well.',
                            style: TextStyle(
                              color: palette.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Divider(color: palette.outline, height: 1),
              const SizedBox(height: 8),
              _DrawerTile(
                palette: palette,
                icon: Icons.palette_outlined,
                title: 'Appearance',
                subtitle: 'Details color, background color and image',
                onTap: () {
                  final navigator = Navigator.of(context);
                  navigator.pop();
                  showAppearanceSheet(navigator.context);
                },
              ),
              _DrawerTile(
                palette: palette,
                icon: Icons.insights_outlined,
                title: 'Insights',
                subtitle: 'Your week in completed tasks and time',
                onTap: () {
                  final navigator = Navigator.of(context);
                  navigator.pop();
                  navigator.push(
                    MaterialPageRoute<void>(
                      builder: (_) => const InsightsScreen(),
                    ),
                  );
                },
              ),
              _DrawerTile(
                palette: palette,
                icon: Icons.settings_outlined,
                title: 'Settings',
                subtitle: 'Defaults, alarms, security, gestures, cleanup',
                onTap: () {
                  final navigator = Navigator.of(context);
                  navigator.pop();
                  navigator.push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SettingsScreen(),
                    ),
                  );
                },
              ),
              _DrawerTile(
                palette: palette,
                icon: Icons.delete_outline,
                title: 'Trash',
                subtitle: 'Recover or purge deleted tasks',
                onTap: () {
                  final navigator = Navigator.of(context);
                  navigator.pop();
                  navigator.push(
                    MaterialPageRoute<void>(
                      builder: (_) => const TrashScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  const _DrawerTile({
    required this.palette,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final AppPalette palette;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: palette.support),
      title: Text(
        title,
        style: TextStyle(color: palette.textPrimary, fontSize: 15),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: palette.textSecondary, fontSize: 12),
      ),
      onTap: onTap,
    );
  }
}
