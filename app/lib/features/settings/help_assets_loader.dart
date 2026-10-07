import 'package:flutter/material.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/features/settings/help_assets_repository.dart';

/// 拉取 OSS 帮助配图、预解码后再渲染正文，减轻进页抖动。
class HelpAssetsLoader extends StatefulWidget {
  const HelpAssetsLoader({
    super.key,
    required this.set,
    required this.builder,
  });

  final String set;
  final Widget Function(BuildContext context, List<String> urls) builder;

  @override
  State<HelpAssetsLoader> createState() => _HelpAssetsLoaderState();
}

class _HelpAssetsLoaderState extends State<HelpAssetsLoader> {
  final _repo = HelpAssetsRepository();
  late Future<List<String>> _future;

  @override
  void initState() {
    super.initState();
    _future = _prepare();
  }

  Future<List<String>> _prepare() async {
    final urls = await _repo.loadUrls(widget.set);
    if (mounted) {
      await precacheHelpImages(context, urls);
    }
    return urls;
  }

  void _retry() {
    setState(() {
      _future = _prepare();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<String>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.only(top: 80),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        if (snapshot.hasError) {
          final message = snapshot.error is ApiException
              ? (snapshot.error as ApiException).message
              : '配图加载失败';
          return Center(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 80, 24, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF737A85),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(onPressed: _retry, child: const Text('重试')),
                ],
              ),
            ),
          );
        }
        final urls = snapshot.data ?? const [];
        if (urls.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 80),
              child: TextButton(onPressed: _retry, child: const Text('重试')),
            ),
          );
        }
        return widget.builder(context, urls);
      },
    );
  }
}

/// 预解码帮助配图，进页后再 [Image.network] 时高度已稳定。
Future<void> precacheHelpImages(BuildContext context, List<String> urls) async {
  await Future.wait(
    urls.map(
      (url) => precacheImage(
        NetworkImage(url),
        context,
      ).catchError((_) {}),
    ),
  );
}

/// 帮助页配图：网络加载。
class HelpNetworkImage extends StatelessWidget {
  const HelpNetworkImage({
    super.key,
    required this.url,
    this.width,
    this.fit = BoxFit.fitWidth,
    this.borderRadius = 10,
    this.onTap,
  });

  final String url;
  final double? width;
  final BoxFit fit;
  final double borderRadius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Image.network(
        url,
        width: width,
        fit: fit,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _Placeholder(width: width),
      ),
    );
    if (onTap == null) return image;
    return GestureDetector(onTap: onTap, child: image);
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({this.width});

  final double? width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: width != null ? width! * 1.35 : 120,
      color: const Color(0xFFE8EBF0),
      alignment: Alignment.center,
      child: const Icon(
        Icons.broken_image_outlined,
        size: 24,
        color: Color(0xFF737A85),
      ),
    );
  }
}
