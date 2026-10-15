import 'package:flutter/material.dart';
import 'package:super_collection/core/network/media_http_headers.dart';
import 'package:super_collection/features/items/default_item_cover.dart';

/// 封面图：有 URL 则加载网络图；无图或加载失败则显示默认封面。
class CoverImage extends StatelessWidget {
  const CoverImage({
    super.key,
    this.url,
    this.pageUrl,
    this.height = 160,
    this.width,
    this.borderRadius = 12,
  });

  final String? url;
  /// 条目源站链接，用作 CDN Referer。
  final String? pageUrl;
  final double height;
  final double? width;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    final trimmed = url?.trim();
    final hasUrl = trimmed != null && trimmed.isNotEmpty;

    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        height: height,
        width: width ?? double.infinity,
        child: hasUrl
            ? Image.network(
                resolveMediaUrl(trimmed),
                fit: BoxFit.cover,
                headers: mediaHttpHeadersFor(
                  resolveMediaUrl(trimmed),
                  pageUrl: pageUrl,
                ),
                gaplessPlayback: true,
                filterQuality: FilterQuality.low,
                errorBuilder: (_, __, ___) => const DefaultItemCover(),
                // 加载中用同色底，避免先闪默认植物图再换成真封面
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const ColoredBox(
                    color: DefaultItemCover.fallbackColor,
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Color(0xFFB8D4C4),
                        ),
                      ),
                    ),
                  );
                },
              )
            : const DefaultItemCover(),
      ),
    );
  }
}
