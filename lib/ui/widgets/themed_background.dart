import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_palette.dart';
import '../../core/theme_controller.dart';

class ThemedBackground extends StatelessWidget {
  const ThemedBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final imagePath = context.watch<ThemeController>().backgroundImagePath;
    final palette = AppPalette.of(context);

    final media = MediaQuery.of(context);
    final decodeWidth =
        (media.size.width * media.devicePixelRatio).round();

    return Stack(
      fit: StackFit.expand,
      children: [
        if (imagePath != null) ...[
          Image.file(
            File(imagePath),
            fit: BoxFit.cover,
            cacheWidth: decodeWidth,
            errorBuilder: (context, error, stackTrace) =>
                ColoredBox(color: palette.backdropBase),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.32),
                  Colors.black.withValues(alpha: 0.55),
                ],
              ),
            ),
          ),
        ] else
          ColoredBox(color: palette.backdropBase),
        child,
      ],
    );
  }
}
