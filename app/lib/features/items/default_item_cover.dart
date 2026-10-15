import 'package:flutter/material.dart';

/// 无封面 / 加载中 / 加载失败时的占位（浅底 + loading，不再用植物默认图）。
class DefaultItemCover extends StatelessWidget {
  const DefaultItemCover({super.key, this.showSpinner = true});

  static const fallbackColor = Color(0xFFF0F2F5);
  static const _spinner = Color(0xFFB0B7C2);

  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: fallbackColor,
      child: showSpinner
          ? const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: _spinner,
                ),
              ),
            )
          : null,
    );
  }
}
