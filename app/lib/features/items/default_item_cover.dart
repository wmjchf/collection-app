import 'package:flutter/material.dart';

/// 无封面 / 加载失败时的默认图（墨绿植物氛围，无字）。
class DefaultItemCover extends StatelessWidget {
  const DefaultItemCover({super.key, this.showSpinner = false});

  static const assetPath = 'assets/branding/default-cover.jpg';
  static const fallbackColor = Color(0xFF1A2A22);

  final bool showSpinner;

  /// 首页叠卡等：提前解码，避免滑到默认图卡时闪一下
  static Future<void> precache(BuildContext context) {
    return precacheImage(const AssetImage(assetPath), context);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          assetPath,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) => const ColoredBox(color: fallbackColor),
        ),
        if (showSpinner)
          const Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: Color(0xFFB8D4C4),
              ),
            ),
          ),
      ],
    );
  }
}
