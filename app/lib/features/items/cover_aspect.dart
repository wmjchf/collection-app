import 'package:flutter/material.dart';
import 'package:super_collection/core/network/media_http_headers.dart';
import 'package:super_collection/features/items/default_item_cover.dart';

/// 按 URL 缓存已解析的封面宽高比（宽/高），避免列表回滚重复测高。
class CoverAspectCache {
  CoverAspectCache._();

  static final Map<String, double> _byUrl = {};

  static double? get(String url) => _byUrl[url];

  static void put(String url, double aspect) {
    if (aspect > 0 && aspect.isFinite) _byUrl[url] = aspect;
  }
}

/// 按图片真实比例占位；加载中用 [fallbackAspect]，极端比例会夹紧。
class NaturalAspectCover extends StatefulWidget {
  const NaturalAspectCover({
    super.key,
    this.url,
    this.pageUrl,
    this.fallbackAspect = 0.75,
    this.minAspect = 0.5,
    this.maxAspect = 1.6,
    this.borderRadius = 0,
  });

  final String? url;
  final String? pageUrl;
  final double fallbackAspect;
  final double minAspect;
  final double maxAspect;
  final double borderRadius;

  @override
  State<NaturalAspectCover> createState() => _NaturalAspectCoverState();
}

class _NaturalAspectCoverState extends State<NaturalAspectCover> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  late double _aspect;

  @override
  void initState() {
    super.initState();
    _aspect = _initialAspect();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant NaturalAspectCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.pageUrl != widget.pageUrl) {
      _detach();
      _aspect = _initialAspect();
      _resolve();
    }
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  double _clamp(double a) => a.clamp(widget.minAspect, widget.maxAspect);

  double _initialAspect() {
    final raw = widget.url?.trim() ?? '';
    if (raw.isEmpty) return widget.fallbackAspect;
    final cached = CoverAspectCache.get(resolveMediaUrl(raw));
    if (cached != null) return _clamp(cached);
    return widget.fallbackAspect;
  }

  void _detach() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _stream = null;
    _listener = null;
  }

  void _resolve() {
    final raw = widget.url?.trim() ?? '';
    if (raw.isEmpty) return;
    final resolved = resolveMediaUrl(raw);
    final cached = CoverAspectCache.get(resolved);
    if (cached != null) {
      final next = _clamp(cached);
      if (next != _aspect) {
        setState(() => _aspect = next);
      }
      return;
    }

    final provider = NetworkImage(
      resolved,
      headers: mediaHttpHeadersFor(resolved, pageUrl: widget.pageUrl),
    );
    final stream = provider.resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        final w = info.image.width;
        final h = info.image.height;
        if (w <= 0 || h <= 0) return;
        final aspect = _clamp(w / h);
        CoverAspectCache.put(resolved, aspect);
        if (!mounted) return;
        if ((aspect - _aspect).abs() > 0.01) {
          setState(() => _aspect = aspect);
        }
      },
      onError: (Object _, StackTrace? _) {},
    );
    stream.addListener(listener);
    _stream = stream;
    _listener = listener;
  }

  @override
  Widget build(BuildContext context) {
    final raw = widget.url?.trim() ?? '';
    final hasUrl = raw.isNotEmpty;
    final radius = BorderRadius.circular(widget.borderRadius);

    return AspectRatio(
      aspectRatio: _aspect,
      child: ClipRRect(
        borderRadius: radius,
        child: hasUrl
            ? Image.network(
                resolveMediaUrl(raw),
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                headers: mediaHttpHeadersFor(
                  resolveMediaUrl(raw),
                  pageUrl: widget.pageUrl,
                ),
                gaplessPlayback: true,
                filterQuality: FilterQuality.low,
                errorBuilder: (context, error, stackTrace) =>
                    const DefaultItemCover(),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const DefaultItemCover(showSpinner: true);
                },
              )
            : const DefaultItemCover(),
      ),
    );
  }
}
