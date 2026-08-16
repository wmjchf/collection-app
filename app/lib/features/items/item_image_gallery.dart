import 'package:flutter/material.dart';
import 'package:super_collection/core/network/media_http_headers.dart';
import 'package:super_collection/features/items/cover_image.dart';

/// 多图轮播；点击可全屏预览。
class ItemImageGallery extends StatefulWidget {
  const ItemImageGallery({
    super.key,
    required this.urls,
    this.borderRadius = 12,
    this.height = 360,
    this.fit = BoxFit.contain,
  });

  final List<String> urls;
  final double borderRadius;
  final double height;
  /// 详情/阅读预览默认 contain 完整显示；需要铺满裁切时传 [BoxFit.cover]
  final BoxFit fit;

  @override
  State<ItemImageGallery> createState() => _ItemImageGalleryState();
}

class _ItemImageGalleryState extends State<ItemImageGallery> {
  static const _dot = Color(0xFFD0D5DD);
  static const _dotActive = Color(0xFF1F242E);

  late final PageController _controller;
  int _index = 0;

  List<String> get _list => widget.urls
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _openPreview(int initialIndex) {
    final list = _list;
    if (list.isEmpty) return;
    final i = initialIndex.clamp(0, list.length - 1);
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) => _ImagePreviewPage(
          urls: list,
          initialIndex: i,
        ),
        transitionsBuilder: (_, anim, __, child) {
          return FadeTransition(opacity: anim, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    if (list.isEmpty) return const SizedBox.shrink();

    if (list.length == 1) {
      return GestureDetector(
        onTap: () => _openPreview(0),
        child: _CarouselImage(
          url: list.first,
          height: widget.height,
          borderRadius: widget.borderRadius,
          fit: widget.fit,
        ),
      );
    }

    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: SizedBox(
            height: widget.height,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                PageView.builder(
                  controller: _controller,
                  itemCount: list.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) => GestureDetector(
                    onTap: () => _openPreview(i),
                    child: _CarouselImage(
                      url: list[i],
                      height: widget.height,
                      borderRadius: 0,
                      fit: widget.fit,
                    ),
                  ),
                ),
                Positioned(
                  right: 10,
                  top: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0x99000000),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_index + 1}/${list.length}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < list.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: i == _index ? 16 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == _index ? _dotActive : _dot,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _CarouselImage extends StatelessWidget {
  const _CarouselImage({
    required this.url,
    required this.height,
    required this.borderRadius,
    this.fit = BoxFit.contain,
  });

  final String url;
  final double height;
  final double borderRadius;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final child = ColoredBox(
      color: const Color(0xFFF0F2F5),
      child: Image.network(
        url,
        width: double.infinity,
        height: height,
        fit: fit,
        alignment: Alignment.center,
        headers: mediaHttpHeadersFor(url),
        errorBuilder: (_, __, ___) => CoverImage(
          url: null,
          height: height,
          borderRadius: borderRadius,
        ),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return CoverImage(
            url: null,
            height: height,
            borderRadius: borderRadius,
          );
        },
      ),
    );

    if (borderRadius <= 0) return child;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: child,
    );
  }
}

/// 全屏图片预览：左右滑动、双指缩放、点空白关闭
class _ImagePreviewPage extends StatefulWidget {
  const _ImagePreviewPage({
    required this.urls,
    required this.initialIndex,
  });

  final List<String> urls;
  final int initialIndex;

  @override
  State<_ImagePreviewPage> createState() => _ImagePreviewPageState();
}

class _ImagePreviewPageState extends State<_ImagePreviewPage> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.urls;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: list.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) {
              return GestureDetector(
                onTap: () => Navigator.of(context).maybePop(),
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Center(
                    child: Image.network(
                      list[i],
                      fit: BoxFit.contain,
                      headers: mediaHttpHeadersFor(list[i]),
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white54,
                        size: 48,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 12, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                  const Spacer(),
                  if (list.length > 1)
                    Text(
                      '${_index + 1}/${list.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
