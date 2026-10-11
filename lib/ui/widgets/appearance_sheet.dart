import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_palette.dart';
import '../../core/constants.dart';
import '../../core/theme_controller.dart';
import 'color_wheel.dart';
import 'frosted_surface.dart';

Future<void> showAppearanceSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => const AppearanceSheet(),
  );
}

class AppearanceSheet extends StatelessWidget {
  const AppearanceSheet({super.key});

  static Key backgroundSwatchKey(Color color) =>
      ValueKey('bg-swatch-${color.toARGB32()}');

  static Key accentSwatchKey(Color color) =>
      ValueKey('accent-swatch-${color.toARGB32()}');

  static const Key customBackgroundSwatchKey = ValueKey('bg-swatch-custom');
  static const Key customAccentSwatchKey = ValueKey('accent-swatch-custom');

  @override
  Widget build(BuildContext context) {
    final themeController = context.watch<ThemeController>();
    final palette = themeController.palette;
    final accent = themeController.accentColor;

    return FrostedSurface(
      color: palette.surfaceElevated,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 16,
            bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.textFaint,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Icon(Icons.palette_outlined, color: palette.support),
                  const SizedBox(width: 10),
                  Text(
                    'Appearance',
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Colors and background, applied across every screen',
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 20),
              _SectionHeading(
                palette: palette,
                title: 'Details color',
                subtitle: 'Buttons, highlights and rings; applies across '
                    'every screen',
              ),
              const SizedBox(height: 12),
              _AccentSwatchRow(
                palette: palette,
                selected: accent,
                onSelected: themeController.commitAccentColor,
              ),
              const SizedBox(height: 24),
              Divider(color: palette.outline),
              const SizedBox(height: 12),
              _SectionHeading(
                palette: palette,
                title: 'Background color',
                subtitle: 'Applies instantly behind every screen',
              ),
              const SizedBox(height: 12),
              _BackgroundSwatchRow(
                palette: palette,
                selected: themeController.backgroundColor,
                onSelected: themeController.setBackgroundColor,
              ),
              const SizedBox(height: 24),
              Divider(color: palette.outline),
              const SizedBox(height: 12),
              _SectionHeading(
                palette: palette,
                title: 'Background image',
                subtitle: 'Shown edge to edge, on top of the background color',
              ),
              const SizedBox(height: 14),
              _BackgroundPreview(
                imagePath: themeController.backgroundImagePath,
                palette: palette,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: palette.onAccent,
                      ),
                      onPressed: () => themeController.pickBackgroundImage(),
                      icon: const Icon(Icons.image_outlined),
                      label: const Text('Choose image'),
                    ),
                  ),
                  if (themeController.hasCustomBackground) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: palette.textSecondary,
                          side: BorderSide(color: palette.outline),
                        ),
                        onPressed: () =>
                            themeController.clearBackgroundImage(),
                        icon: const Icon(Icons.close),
                        label: const Text('Remove'),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.palette,
    required this.title,
    required this.subtitle,
  });

  final AppPalette palette;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: palette.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(
            color: palette.textSecondary,
            fontSize: 12.5,
          ),
        ),
      ],
    );
  }
}

class _BackgroundPreview extends StatelessWidget {
  const _BackgroundPreview({required this.imagePath, required this.palette});

  final String? imagePath;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final path = imagePath;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.cornerRadius),
      child: SizedBox(
        height: 110,
        child: path != null
            ? Image.file(
                File(path),
                fit: BoxFit.cover,
                width: double.infinity,
                errorBuilder: (context, error, stackTrace) =>
                    _placeholder(),
              )
            : _placeholder(),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      width: double.infinity,
      color: palette.support.withValues(alpha: 0.10),
      child: Center(
        child: Icon(
          Icons.wallpaper_outlined,
          size: 34,
          color: palette.textFaint,
        ),
      ),
    );
  }
}

class _AccentSwatchRow extends StatelessWidget {
  const _AccentSwatchRow({
    required this.palette,
    required this.selected,
    required this.onSelected,
  });

  final AppPalette palette;
  final Color selected;
  final ValueChanged<Color> onSelected;

  @override
  Widget build(BuildContext context) {
    final ring = palette.textPrimary;

    return Wrap(
      spacing: 2,
      runSpacing: 6,
      children: [
        for (final color in AppPalette.accentSwatches)
          _Swatch(
            key: AppearanceSheet.accentSwatchKey(color),
            palette: palette,
            color: color,
            ringColor: ring,
            isSelected: color.toARGB32() == selected.toARGB32(),
            onTap: () => onSelected(color),
            semanticLabel: color.toARGB32() ==
                    AppConstants.defaultAccentColor.toARGB32()
                ? 'Default details color'
                : 'Details color',
          ),
        _CustomSwatch(
          key: AppearanceSheet.customAccentSwatchKey,
          palette: palette,
          isSelected: !AppPalette.accentSwatches
              .any((c) => c.toARGB32() == selected.toARGB32()),
          onTap: () => _openWheel(context),
          semanticLabel: 'Custom details color',
        ),
      ],
    );
  }

  Future<void> _openWheel(BuildContext context) async {
    final controller = context.read<ThemeController>();
    final startedAt = controller.accentColor;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final sheetPalette = AppPalette.of(sheetContext);
        return FrostedSurface(
          color: sheetPalette.surfaceElevated,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Custom details color',
                    style: TextStyle(
                      color: sheetPalette.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'The whole app follows the wheel as you drag',
                    style: TextStyle(
                      color: sheetPalette.textSecondary,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 18),
                  ColorWheel(
                    color: startedAt,
                    onChanged: controller.previewAccentColor,
                    onChangeEnd: controller.commitAccentColor,
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: sheetPalette.textSecondary,
                            side: BorderSide(color: sheetPalette.outline),
                          ),
                          onPressed: () {
                            controller.commitAccentColor(startedAt);
                            Navigator.of(sheetContext).pop();
                          },
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: sheetPalette.accent,
                            foregroundColor: sheetPalette.onAccent,
                          ),
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          child: const Text('Done'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BackgroundSwatchRow extends StatelessWidget {
  const _BackgroundSwatchRow({
    required this.palette,
    required this.selected,
    required this.onSelected,
  });

  final AppPalette palette;
  final Color? selected;
  final ValueChanged<Color> onSelected;

  static const double swatchSize = 40;
  static const double ringGap = 4;
  static const double ringWidth = 2;

  static const double slotSize = swatchSize + 2 * (ringGap + ringWidth);

  @override
  Widget build(BuildContext context) {
    // with no saved colour fall back to the first swatch
    final effective = selected ?? AppPalette.backgroundSwatches.first;
    return Wrap(
      spacing: 2,
      runSpacing: 6,
      children: [
        // wrap the row because scrolling once hid the dark half
        for (final color in AppPalette.backgroundSwatches)
          _Swatch(
            key: AppearanceSheet.backgroundSwatchKey(color),
            palette: palette,
            color: color,
            isSelected: effective.toARGB32() == color.toARGB32(),
            onTap: () => onSelected(color),
          ),
        _CustomSwatch(
          key: AppearanceSheet.customBackgroundSwatchKey,
          palette: palette,
          isSelected: !AppPalette.backgroundSwatches
              .any((c) => c.toARGB32() == effective.toARGB32()),
          onTap: () => _openWheel(context),
        ),
      ],
    );
  }

  Future<void> _openWheel(BuildContext context) async {
    final controller = context.read<ThemeController>();
    final startedAt = controller.backgroundColor;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final sheetPalette = AppPalette.of(sheetContext);
        return FrostedSurface(
          color: sheetPalette.surfaceElevated,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Custom background',
                    style: TextStyle(
                      color: sheetPalette.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'The whole app follows the wheel as you drag',
                    style: TextStyle(
                      color: sheetPalette.textSecondary,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 18),
                  ColorWheel(
                    color: startedAt ?? sheetPalette.backdropBase,
                    onChanged: controller.previewBackgroundColor,
                    onChangeEnd: controller.setBackgroundColor,
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: sheetPalette.textSecondary,
                            side: BorderSide(color: sheetPalette.outline),
                          ),
                          onPressed: () {
                            controller.setBackgroundColor(startedAt);
                            Navigator.of(sheetContext).pop();
                          },
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: sheetPalette.accent,
                            foregroundColor: sheetPalette.onAccent,
                          ),
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          child: const Text('Done'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CustomSwatch extends StatelessWidget {
  const _CustomSwatch({
    super.key,
    required this.palette,
    required this.isSelected,
    required this.onTap,
    this.semanticLabel = 'Custom background color',
  });

  final AppPalette palette;
  final bool isSelected;
  final VoidCallback onTap;

  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return _Swatch(
      palette: palette,
      color: null,
      isSelected: isSelected,
      onTap: onTap,
      gradient: const SweepGradient(
        colors: [
          Color(0xFFFF0000),
          Color(0xFFFFFF00),
          Color(0xFF00FF00),
          Color(0xFF00FFFF),
          Color(0xFF0000FF),
          Color(0xFFFF00FF),
          Color(0xFFFF0000),
        ],
      ),
      semanticLabel: semanticLabel,
    );
  }
}

class _Swatch extends StatefulWidget {
  const _Swatch({
    super.key,
    required this.palette,
    required this.color,
    required this.isSelected,
    required this.onTap,
    this.gradient,
    this.semanticLabel,
    this.ringColor,
  });

  final AppPalette palette;

  final Color? color;

  final Gradient? gradient;

  final String? semanticLabel;

  final Color? ringColor;

  final bool isSelected;
  final VoidCallback onTap;

  @override
  State<_Swatch> createState() => _SwatchState();
}

class _SwatchState extends State<_Swatch>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _selection;

  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
      value: widget.isSelected ? 1 : 0,
    );
    _selection = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeOutCubic,
    );
  }

  @override
  void didUpdateWidget(_Swatch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected != oldWidget.isSelected) {
      widget.isSelected ? _controller.forward() : _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setPressed(bool pressed) {
    if (_pressed == pressed) return;
    setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final fill = widget.color;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Semantics(
        selected: widget.isSelected,
        button: true,
        label: widget.semanticLabel ?? 'Background color',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onTapDown: (_) => _setPressed(true),
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          child: AnimatedScale(
            scale: _pressed ? 0.90 : 1,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            child: AnimatedBuilder(
              animation: _selection,
              builder: (context, child) {
                final t = _selection.value;
                return SizedBox(
                  width: _BackgroundSwatchRow.slotSize,
                  height: _BackgroundSwatchRow.slotSize,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Opacity(
                        opacity: t.clamp(0.0, 1.0),
                        child: Transform.scale(
                          scale: 0.78 + 0.22 * t,
                          child: Container(
                            width: _BackgroundSwatchRow.slotSize,
                            height: _BackgroundSwatchRow.slotSize,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: widget.ringColor ??
                                    widget.palette.accent,
                                width: _BackgroundSwatchRow.ringWidth,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Transform.scale(
                        scale: 1 + 0.06 * t.clamp(0.0, 1.0),
                        child: child,
                      ),
                    ],
                  ),
                );
              },
              child: Container(
                width: _BackgroundSwatchRow.swatchSize,
                height: _BackgroundSwatchRow.swatchSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: fill,
                  gradient: widget.gradient,
                  border: Border.all(color: widget.palette.outline),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
