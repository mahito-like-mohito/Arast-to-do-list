import 'package:flutter/material.dart';

import '../../core/app_palette.dart';
import '../../core/constants.dart';
import '../../data/models/time_section.dart';
import 'frosted_surface.dart';

class TimeSectionHeaderDelegate extends SliverPersistentHeaderDelegate {
  TimeSectionHeaderDelegate({
    required this.section,
    required this.taskCount,
    required this.palette,
  });

  final TimeSection section;
  final int taskCount;
  final AppPalette palette;

  static const double extent = 92;

  @override
  double get maxExtent => extent;

  @override
  double get minExtent => extent;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: FrostedSurface(
        color: palette.surfaceElevated,
        borderRadius: BorderRadius.circular(AppConstants.cornerRadius),
        border: Border.all(color: palette.accent.withValues(alpha: 0.65)),
        boxShadow: [
          BoxShadow(
            color: palette.support.withValues(alpha: 0.30),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      section.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      section.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: palette.support.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  taskCount == 1 ? '1 task' : '$taskCount tasks',
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(TimeSectionHeaderDelegate oldDelegate) {
    return oldDelegate.section != section ||
        oldDelegate.taskCount != taskCount ||
        oldDelegate.palette != palette;
  }
}
