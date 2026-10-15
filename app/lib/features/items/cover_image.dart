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
    this.fit,
  });

  final String? url;
  /// 条目源站链接，用作 CDN Referer。
  final String? pageUrl;
  final double height;
  final double? width;
  final double borderRadius;
  /// 缺省：普通图 cover；品牌方标（如使用指引）自动 contain，避免裁掉四角
  final BoxFit? fit;

  /// 使用指引等：封面是方形 App 图标，cover 会切顶
  static bool isBrandIconUrl(String? raw) {
    final u = (raw ?? '').trim().toLowerCase();
    if (u.isEmpty) return false;
    return u.endsWith('/assets/icon.png') ||
        u.endsWith('/icon.png') ||
        u.contains('/assets/icon.png?');
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    final trimmed = url?.trim();
    final hasUrl = trimmed != null && trimmed.isNotEmpty;
    final resolvedFit = fit ??
        (isBrandIconUrl(trimmed) ? BoxFit.contain : BoxFit.cover);
    final brandIcon = isBrandIconUrl(trimmed);

    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        height: height,
        width: width ?? double.infinity,
        child: hasUrl
            ? ColoredBox(
                // 方标 contain 时露白底，不要墨绿/黑边
                color: brandIcon ? Colors.white : Colors.transparent,
                child: Image.network(
                  resolveMediaUrl(trimmed),
                  fit: resolvedFit,
                  alignment: Alignment.center,
                  headers: mediaHttpHeadersFor(
                    resolveMediaUrl(trimmed),
                    pageUrl: pageUrl,
                  ),
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.low,
                  errorBuilder: (_, __, ___) => const DefaultItemCover(),
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return const DefaultItemCover();
                  },
                ),
              )
            : const DefaultItemCover(),
      ),
    );
  }
}
