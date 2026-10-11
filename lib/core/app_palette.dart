import 'package:flutter/material.dart';

@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.accent,
    required this.onAccent,
    required this.support,
    required this.onSupport,
    required this.backdropBase,
    required this.surfaceBlurred,
    required this.surface,
    required this.surfaceElevated,
    required this.outline,
    required this.textPrimary,
    required this.textSecondary,
    required this.textFaint,
    required this.onBackdrop,
    required this.onBackdropMuted,
    required this.inverseSurface,
    required this.onInverseSurface,
    required this.danger,
  });

  final Color accent;

  final Color onAccent;

  final Color support;

  final Color onSupport;

  final Color backdropBase;

  final bool surfaceBlurred;

  final Color surface;

  final Color surfaceElevated;

  final Color outline;

  final Color textPrimary;
  final Color textSecondary;
  final Color textFaint;

  final Color onBackdrop;
  final Color onBackdropMuted;

  final Color inverseSurface;
  final Color onInverseSurface;

  final Color danger;

  static const Color lightBlue = Color(0xFF8FB8DC);
  static const Color brown = Color(0xFF7A5B41);
  static const Color cream = Color(0xFFF7F1E8);
  static const Color sand = Color(0xFFD9C7AF);
  static const Color paleBlue = Color(0xFFBFD9EC);
  static const Color espresso = Color(0xFF362A1F);

  static const Color _darkInk = espresso;
  static const Color _darkInkSoft = Color(0xFF6E5A48);
  static const Color _darkInkFaint = Color(0xFF9C8B79);
  static const Color _lightInk = Color(0xFFF5F1EA);
  static const Color _lightInkSoft = Color(0xFFDECFBD);
  static const Color _lightInkFaint = Color(0xFFBBA98F);

  static const List<Color> backgroundSwatches = [
    cream,
    Color(0xFFFFFFFF),
    Color(0xFFEFF4F9),
    paleBlue,
    Color(0xFFE7EDE8),
    sand,
    Color(0xFFDCC9B0),
    Color(0xFF3B3128),
    Color(0xFF23303A),
    Color(0xFF000000),
  ];

  static const List<Color> accentSwatches = [
    lightBlue,
    Color(0xFF5B8DB8),
    Color(0xFF4FA3A0),
    Color(0xFF7FA88D),
    Color(0xFF6E77C4),
    Color(0xFF9B6BA8),
    Color(0xFFD4708F),
    Color(0xFFC96F4A),
    Color(0xFFD9A03C),
    Color(0xFFB98A5E),
    Color(0xFF9C8B79),
    brown,
  ];

  factory AppPalette.fromSeeds({
    required Color accent,
    required bool hasBackdropImage,
    Color? backgroundColor,
  }) {
    final onAccent = _foregroundFor(accent);

    // with no saved colour fall back to the first swatch
    final background = backgroundColor ?? backgroundSwatches.first;
    final backdropBase = hasBackdropImage ? _scrimmedPhotoBase : background;
    final backdropIsDark =
        ThemeData.estimateBrightnessForColor(backdropBase) == Brightness.dark;

    final surface = hasBackdropImage
        ? _frostedSurface
        : _surfaceFor(backdropBase, 1);
    final surfaceElevated = hasBackdropImage
        ? _frostedSurfaceElevated
        : _surfaceFor(backdropBase, 2);

    final surfaceInk = _inkSetFor(surface);
    final surfaceIsLight =
        ThemeData.estimateBrightnessForColor(surface) == Brightness.light;
    final support = surfaceIsLight ? brown : _brownLifted;

    return AppPalette(
      accent: accent,
      onAccent: onAccent,
      support: support,
      onSupport: _foregroundFor(support),
      backdropBase: backdropBase,
      surfaceBlurred: hasBackdropImage,
      surface: surface,
      surfaceElevated: surfaceElevated,
      outline: surfaceInk.$1.withValues(alpha: surfaceIsLight ? 0.20 : 0.28),
      textPrimary: surfaceInk.$1,
      textSecondary: surfaceInk.$2,
      textFaint: surfaceInk.$3,
      onBackdrop: backdropIsDark ? _lightInk : _darkInk,
      onBackdropMuted: backdropIsDark ? _lightInkSoft : _darkInkSoft,
      inverseSurface: surfaceIsLight ? const Color(0xF2322A20) : _lightInk,
      onInverseSurface: surfaceIsLight ? _lightInk : _darkInk,
      danger: surfaceIsLight ? _danger : _dangerLifted,
    );
  }

  static const Color _scrimmedPhotoBase = Color(0xFF2A2622);
  static const Color _danger = Color(0xFFB9502F);

  static const Color _frostedSurface = Color(0xB3FFFFFF);
  static const Color _frostedSurfaceElevated = Color(0xCCFFFFFF);

  static final Color _brownLifted = HSLColor.fromColor(brown)
      .withSaturation(0.30)
      .withLightness(0.68)
      .toColor();
  static final Color _dangerLifted =
      HSLColor.fromColor(_danger).withLightness(0.64).toColor();

  static Color _surfaceFor(Color backdrop, int step) {
    final hsl = HSLColor.fromColor(backdrop);
    final isLight =
        ThemeData.estimateBrightnessForColor(backdrop) == Brightness.light;

    final double lightness;
    if (isLight) {
      lightness = hsl.lightness >= 0.90
          ? hsl.lightness - 0.045 * step
          : hsl.lightness + 0.065 * step;
    } else {
      lightness = hsl.lightness + 0.085 * step;
    }

    return hsl
        .withSaturation((hsl.saturation * 0.5).clamp(0.0, 0.35))
        .withLightness(lightness.clamp(0.04, 0.98))
        .toColor();
  }

  static Color _foregroundFor(Color background) {
    return ThemeData.estimateBrightnessForColor(background) == Brightness.light
        ? _darkInk
        : _lightInk;
  }

  static (Color, Color, Color) _inkSetFor(Color surface) {
    final isLight =
        ThemeData.estimateBrightnessForColor(surface) == Brightness.light;
    return isLight
        ? (_darkInk, _darkInkSoft, _darkInkFaint)
        : (_lightInk, _lightInkSoft, _lightInkFaint);
  }

  static AppPalette of(BuildContext context) {
    return Theme.of(context).extension<AppPalette>() ??
        AppPalette.fromSeeds(
          accent: lightBlue,
          hasBackdropImage: false,
        );
  }

  @override
  AppPalette copyWith({
    Color? accent,
    Color? onAccent,
    Color? support,
    Color? onSupport,
    Color? backdropBase,
    bool? surfaceBlurred,
    Color? surface,
    Color? surfaceElevated,
    Color? outline,
    Color? textPrimary,
    Color? textSecondary,
    Color? textFaint,
    Color? onBackdrop,
    Color? onBackdropMuted,
    Color? inverseSurface,
    Color? onInverseSurface,
    Color? danger,
  }) {
    return AppPalette(
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      support: support ?? this.support,
      onSupport: onSupport ?? this.onSupport,
      backdropBase: backdropBase ?? this.backdropBase,
      surfaceBlurred: surfaceBlurred ?? this.surfaceBlurred,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      outline: outline ?? this.outline,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textFaint: textFaint ?? this.textFaint,
      onBackdrop: onBackdrop ?? this.onBackdrop,
      onBackdropMuted: onBackdropMuted ?? this.onBackdropMuted,
      inverseSurface: inverseSurface ?? this.inverseSurface,
      onInverseSurface: onInverseSurface ?? this.onInverseSurface,
      danger: danger ?? this.danger,
    );
  }

  @override
  AppPalette lerp(AppPalette? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      accent: mix(accent, other.accent),
      onAccent: mix(onAccent, other.onAccent),
      support: mix(support, other.support),
      onSupport: mix(onSupport, other.onSupport),
      backdropBase: mix(backdropBase, other.backdropBase),
      surfaceBlurred: t < 0.5 ? surfaceBlurred : other.surfaceBlurred,
      surface: mix(surface, other.surface),
      surfaceElevated: mix(surfaceElevated, other.surfaceElevated),
      outline: mix(outline, other.outline),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      textFaint: mix(textFaint, other.textFaint),
      onBackdrop: mix(onBackdrop, other.onBackdrop),
      onBackdropMuted: mix(onBackdropMuted, other.onBackdropMuted),
      inverseSurface: mix(inverseSurface, other.inverseSurface),
      onInverseSurface: mix(onInverseSurface, other.onInverseSurface),
      danger: mix(danger, other.danger),
    );
  }
}
