import 'package:flutter/material.dart';
import 'package:super_collection/core/network/media_http_headers.dart';

/// 封面图：有 URL 则加载网络图；无图或加载失败则显示默认封面。
class CoverImage extends StatelessWidget {
  const CoverImage({
    super.key,
    this.url,
    this.height = 160,
    this.width,
    this.borderRadius = 12,
  });

  final String? url;
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
                trimmed,
                fit: BoxFit.cover,
                headers: mediaHttpHeadersFor(trimmed),
                errorBuilder: (_, __, ___) => const _DefaultCover(),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const _DefaultCover(showSpinner: true);
                },
              )
            : const _DefaultCover(),
      ),
    );
  }
}

class _DefaultCover extends StatelessWidget {
  const _DefaultCover({this.showSpinner = false});

  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFE8EEF7),
            Color(0xFFD5E0F0),
            Color(0xFFC5D4E8),
          ],
        ),
      ),
      child: Center(
        child: showSpinner
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Color(0xFF8FA3BF),
                ),
              )
            : const Icon(
                Icons.auto_stories_outlined,
                size: 36,
                color: Color(0xFF8FA3BF),
              ),
      ),
    );
  }
}
