import 'package:flutter/material.dart';

import '../headsapp_theme.dart';

class DotIndicator extends StatelessWidget {
  const DotIndicator({
    super.key,
    this.activeIndex,
    this.count = 3,
  });

  final int? activeIndex;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List<Widget>.generate(count, (index) {
        final active = activeIndex != null && activeIndex == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: active
                ? HeadsAppColors.brandPrimary
                : HeadsAppColors.border.withValues(alpha: 0.85),
          ),
        );
      }),
    );
  }
}
