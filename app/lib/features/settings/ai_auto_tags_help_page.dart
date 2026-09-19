import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:super_collection/core/analytics/screen_dwell_tracker.dart';
import 'package:super_collection/core/config/api_config.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/features/items/item_image_gallery.dart';
import 'package:super_collection/features/settings/help_repository.dart';

/// 设置 → 使用帮助 → AI自动标签分类方法（正文由后台配置）
class AiAutoTagsHelpPage extends StatefulWidget {
  const AiAutoTagsHelpPage({super.key});

  static const pageKey = 'ai_auto_tags';
  static const fallbackTitle = 'AI自动标签分类方法';

  @override
  State<AiAutoTagsHelpPage> createState() => _AiAutoTagsHelpPageState();
}

class _AiAutoTagsHelpPageState extends State<AiAutoTagsHelpPage> {
  static const _bg = Colors.white;
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);

  final _repo = HelpRepository();
  HelpPage? _page;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _repo.getPage(AiAutoTagsHelpPage.pageKey);
      if (!mounted) return;
      setState(() {
        _page = page;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '加载失败';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = (_page?.title.isNotEmpty ?? false)
        ? _page!.title
        : AiAutoTagsHelpPage.fallbackTitle;
    return ScreenDwellScope(
      screen: AnalyticsScreens.aiAutoTagsHelp,
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          leadingWidth: 80,
          leading: TextButton.icon(
            onPressed: () => Navigator.of(context).maybePop(),
            style: TextButton.styleFrom(
              foregroundColor: _text,
              padding: const EdgeInsets.only(left: 8),
            ),
            icon: const Icon(Icons.chevron_left, size: 30),
            label: const Text('返回', style: TextStyle(fontSize: 15)),
          ),
          title: Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: _text,
            ),
          ),
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(fontSize: 14, color: _muted)),
            TextButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    final page = _page;
    if (page == null || !page.hasBody) {
      return const Center(
        child: Text('暂无说明', style: TextStyle(fontSize: 14, color: _muted)),
      );
    }
    final pieces = _splitHelpHtml(_absoluteHelpHtml(page.html));
    final images = <String>[
      for (final piece in pieces)
        if (piece.src != null) _decodeHtmlAttr(piece.src!),
    ];
    return ListView(
      padding: const EdgeInsets.only(top: 16, bottom: 32),
      children: [
        for (final piece in pieces)
          if (piece.src != null)
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth.isFinite
                    ? constraints.maxWidth
                    : MediaQuery.sizeOf(context).width;
                final src = _decodeHtmlAttr(piece.src!);
                final index = images.indexOf(src);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: GestureDetector(
                    onTap: () => showNetworkImagePreview(
                      context,
                      urls: images,
                      initialIndex: index < 0 ? 0 : index,
                    ),
                    child: Image.network(
                      src,
                      width: width,
                      fit: BoxFit.fitWidth,
                      errorBuilder: (_, _, _) => const SizedBox(
                        height: 120,
                        child: Center(
                          child: Text(
                            '图片加载失败',
                            style: TextStyle(fontSize: 13, color: _muted),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Html(
                data: piece.html,
                style: {
                  'body': Style(
                    margin: Margins.zero,
                    padding: HtmlPaddings.zero,
                    fontSize: FontSize(14),
                    lineHeight: const LineHeight(1.6),
                    color: _text,
                  ),
                  'p': Style(margin: Margins.only(bottom: 12)),
                  'h2': Style(
                    margin: Margins.only(top: 4, bottom: 8),
                    fontSize: FontSize(17),
                    fontWeight: FontWeight.w700,
                    color: _text,
                    lineHeight: const LineHeight(1.35),
                  ),
                  'h3': Style(
                    margin: Margins.only(top: 4, bottom: 8),
                    fontSize: FontSize(15),
                    fontWeight: FontWeight.w700,
                    color: _text,
                    lineHeight: const LineHeight(1.35),
                  ),
                  'ul': Style(
                    margin: Margins.only(bottom: 12),
                    padding: HtmlPaddings.only(left: 18),
                  ),
                  'ol': Style(
                    margin: Margins.only(bottom: 12),
                    padding: HtmlPaddings.only(left: 18),
                  ),
                },
              ),
            ),
      ],
    );
  }
}

String _absoluteHelpHtml(String html) {
  final base = ApiConfig.baseUrl.replaceAll(RegExp(r'/+$'), '');
  return html.replaceAllMapped(
    RegExp('''src=(['"])/help/'''),
    (match) => 'src=${match[1]}$base/help/',
  );
}

class _HelpPiece {
  const _HelpPiece.text(this.html) : src = null;
  const _HelpPiece.image(this.src) : html = '';

  final String html;
  final String? src;
}

List<_HelpPiece> _splitHelpHtml(String html) {
  final normalized = html.replaceAllMapped(
    RegExp(r'<p>\s*(<img\b[^>]*>)\s*</p>', caseSensitive: false),
    (match) => match.group(1) ?? '',
  );
  final img = RegExp(
    '''<img\\b[^>]*\\bsrc=(['"])(.*?)\\1[^>]*>''',
    caseSensitive: false,
  );
  final pieces = <_HelpPiece>[];
  var start = 0;
  for (final match in img.allMatches(normalized)) {
    final before = _trimEmptyHtml(normalized.substring(start, match.start));
    if (before.isNotEmpty) pieces.add(_HelpPiece.text(before));
    final src = (match.group(2) ?? '').trim();
    if (src.isNotEmpty) pieces.add(_HelpPiece.image(src));
    start = match.end;
  }
  final rest = _trimEmptyHtml(normalized.substring(start));
  if (rest.isNotEmpty) pieces.add(_HelpPiece.text(rest));
  return pieces;
}

String _decodeHtmlAttr(String value) {
  return value
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'");
}

String _trimEmptyHtml(String html) {
  return html
      .replaceAll(RegExp(r'<p>(\s|<br\s*/?>)*</p>', caseSensitive: false), '')
      .trim();
}
