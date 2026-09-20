import 'package:flutter/material.dart';
import 'package:super_collection/core/analytics/screen_dwell_tracker.dart';
import 'package:super_collection/features/items/item_image_gallery.dart';

/// 设置 → 使用帮助 → AI自动标签分类方法（本地写死，不走后台）
class AiAutoTagsHelpPage extends StatelessWidget {
  const AiAutoTagsHelpPage({super.key});

  static const _bg = Color(0xFFF7F7FA);
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _blue = Color(0xFF2F6FED);
  static const _tint = Color(0xFFEAF1FE);

  static const _figures = <String>[
    'assets/help/fig1.png',
    'assets/help/fig2.png',
    'assets/help/fig3.png',
  ];

  @override
  Widget build(BuildContext context) {
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
          title: const Text(
            'AI自动标签分类方法',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: _text,
            ),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            const _WhiteCard(
              child: Text(
                '一篇好内容可能同时包含不同类别的突出点，无法用简单的分类模式来收藏。'
                '我们开发了一套全新的标签内容分类模式：用标签表示内容的分类，'
                '再用标签归属大类的方式帮助你管理内容。',
                style: TextStyle(fontSize: 15, color: _text, height: 1.55),
              ),
            ),
            const SizedBox(height: 12),
            _WhiteCard(
              color: _tint,
              child: _RichBody(
                children: [
                  const TextSpan(
                    text:
                        '比如一篇夏天去海边游玩赶海的游记，内容里有赶海攻略、夏日美景，'
                        '以及旅途中遇到的美食、金黄色的日落，可以打标签为',
                  ),
                  _tag('旅游攻略'),
                  const TextSpan(text: '、'),
                  _tag('夏日美景'),
                  const TextSpan(text: '、'),
                  _tag('海边'),
                  const TextSpan(text: '、'),
                  _tag('赶海'),
                  const TextSpan(text: '、'),
                  _tag('美食'),
                  const TextSpan(text: '。\n\n再把标签归入不同大类，比如'),
                  _tag('旅游攻略'),
                  const TextSpan(text: '、'),
                  _tag('夏日美景'),
                  const TextSpan(text: '、'),
                  _tag('海边'),
                  const TextSpan(text: '、'),
                  _tag('赶海'),
                  const TextSpan(text: '属于旅游类，'),
                  _tag('美食'),
                  const TextSpan(text: '属于生活类，从而实现整体管理。\n\n'),
                  const TextSpan(
                    text: '新建标签和 AI 自动打的标签若尚未归类，会显示在「未归类」里。',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const _SectionLabel('图一'),
            const SizedBox(height: 8),
            _FigureCard(asset: _figures[0], index: 0),
            const SizedBox(height: 20),
            const _SectionLabel('图二'),
            const SizedBox(height: 8),
            _FigureCard(asset: _figures[1], index: 1),
            const SizedBox(height: 20),
            const _SectionLabel('图三'),
            const SizedBox(height: 8),
            _FigureCard(asset: _figures[2], index: 2),
            const SizedBox(height: 20),
            const _ProCard(
              child: Text(
                '升级为 Pro 的用户，在粘贴链接解析完成后，AI 会自动打标签并显示在内容上；'
                '点进去会显示在内容上方。',
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.white,
                  height: 1.55,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const _WhiteCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.search_rounded, size: 18, color: _blue),
                      SizedBox(width: 6),
                      Text(
                        '快速搜索',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: _text,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    '点击搜索按钮，即可快速搜索标签、文字、感想。'
                    '点击标签即可筛选打了相应标签的内容，快速精准。',
                    style: TextStyle(fontSize: 14, color: _muted, height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'AI自动标签分类 · 功能指引',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: _muted),
            ),
          ],
        ),
      ),
    );
  }

  static TextSpan _tag(String name) {
    return TextSpan(
      text: '#$name',
      style: const TextStyle(
        color: _blue,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: AiAutoTagsHelpPage._blue,
        height: 1.3,
      ),
    );
  }
}

class _WhiteCard extends StatelessWidget {
  const _WhiteCard({
    required this.child,
    this.color = Colors.white,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final Color color;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    );
  }
}

class _ProCard extends StatelessWidget {
  const _ProCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: AiAutoTagsHelpPage._blue,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome, size: 14, color: Colors.white),
                SizedBox(width: 4),
                Text(
                  'Pro',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _RichBody extends StatelessWidget {
  const _RichBody({required this.children});

  final List<InlineSpan> children;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: const TextStyle(
          fontSize: 15,
          color: AiAutoTagsHelpPage._text,
          height: 1.55,
        ),
        children: children,
      ),
    );
  }
}

class _FigureCard extends StatelessWidget {
  const _FigureCard({required this.asset, required this.index});

  final String asset;
  final int index;

  @override
  Widget build(BuildContext context) {
    return _WhiteCard(
      padding: const EdgeInsets.all(10),
      child: GestureDetector(
        onTap: () => showAssetImagePreview(
          context,
          assets: AiAutoTagsHelpPage._figures,
          initialIndex: index,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.asset(
            asset,
            width: double.infinity,
            fit: BoxFit.fitWidth,
          ),
        ),
      ),
    );
  }
}
