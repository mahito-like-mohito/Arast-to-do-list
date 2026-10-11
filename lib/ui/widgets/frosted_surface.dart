import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/app_palette.dart';

class FrostedSurface extends StatelessWidget {
  const FrostedSurface({
    super.key,
    required this.color,
    required this.borderRadius,
    this.border,
    this.boxShadow,
    this.child,
  });

  final Color color;

  final BorderRadius borderRadius;

  final BoxBorder? border;

  final List<BoxShadow>? boxShadow;

  final Widget? child;

  static const double _blurSigma = 16;

  @override
  Widget build(BuildContext context) {
    if (!AppPalette.of(context).surfaceBlurred) {
      return Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: borderRadius,
          border: border,
          boxShadow: boxShadow,
        ),
        child: _inkHost(child),
      );
    }

    Widget surface = ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: _blurSigma, sigmaY: _blurSigma),
        child: Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: borderRadius,
            border: border,
          ),
          child: _inkHost(child),
        ),
      ),
    );

    if (boxShadow != null) {
      surface = Container(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: boxShadow,
        ),
        child: surface,
      );
    }
    return surface;
  }

  // paint ripples above the fill
  Widget _inkHost(Widget? child) {
    return Material(type: MaterialType.transparency, child: child);
  }
}
