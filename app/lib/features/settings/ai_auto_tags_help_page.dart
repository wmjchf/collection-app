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
            const _IntroCard(),
            const SizedBox(height: 24),
            const _SectionHeading('在 App 里整理标签'),
            const SizedBox(height: 10),
            const _GuideStepCard(
              figureIndex: 0,
              title: '标签与类别一览',
              desc:
                  '在「我的收藏」进入归类标签：顶部是未归类的标签，'
                  '下方按大类分组；点右上角 + 可新建类别，点类别或标签可查看对应内容。',
            ),
            const SizedBox(height: 12),
            const _GuideStepCard(
              figureIndex: 1,
              title: 'AI 一键归类',
              desc:
                  '未归类区点「AI 标签归类」可自动整理；'
                  '类别旁的 ··· 菜单可改名、往类别里加标签，或删除整个归类。',
            ),
            const SizedBox(height: 12),
            const _GuideStepCard(
              figureIndex: 2,
              title: '长按拖动归类',
              desc: '长按任意标签拖到目标类别，类别蓝色高亮时松手即可快速归类。',
            ),
            const SizedBox(height: 24),
            const _SectionHeading('解析后自动打标签'),
            const SizedBox(height: 10),
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
            const SizedBox(height: 24),
            const _SectionHeading('快速搜索'),
            const SizedBox(height: 10),
            const _WhiteCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.search_rounded, size: 18, color: _blue),
                      SizedBox(width: 6),
                      Text(
                        '按标签、文字、感想查找',
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

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AiAutoTagsHelpPage._muted,
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard();

  @override
  Widget build(BuildContext context) {
    return const _WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '一篇好内容可能同时包含不同类别的突出点，无法用简单的分类模式来收藏。'
            '我们开发了一套全新的标签内容分类模式：用标签表示内容的分类，'
            '再用标签归属大类的方式帮助你管理内容。',
            style: TextStyle(fontSize: 15, color: AiAutoTagsHelpPage._text, height: 1.55),
          ),
          SizedBox(height: 16),
          Text(
            '举个例子',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AiAutoTagsHelpPage._blue,
            ),
          ),
          SizedBox(height: 10),
          _ExampleBlock(),
        ],
      ),
    );
  }
}

class _ExampleBlock extends StatelessWidget {
  const _ExampleBlock();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AiAutoTagsHelpPage._tint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: _RichBody(
        children: [
          const TextSpan(
            text:
                '夏天去海边游玩赶海的游记，内容里有赶海攻略、夏日美景，'
                '以及旅途中遇到的美食、金黄色的日落，可以打标签为',
          ),
          AiAutoTagsHelpPage._tag('旅游攻略'),
          const TextSpan(text: '、'),
          AiAutoTagsHelpPage._tag('夏日美景'),
          const TextSpan(text: '、'),
          AiAutoTagsHelpPage._tag('海边'),
          const TextSpan(text: '、'),
          AiAutoTagsHelpPage._tag('赶海'),
          const TextSpan(text: '、'),
          AiAutoTagsHelpPage._tag('美食'),
          const TextSpan(text: '。\n\n再把标签归入不同大类，比如'),
          AiAutoTagsHelpPage._tag('旅游攻略'),
          const TextSpan(text: '、'),
          AiAutoTagsHelpPage._tag('夏日美景'),
          const TextSpan(text: '、'),
          AiAutoTagsHelpPage._tag('海边'),
          const TextSpan(text: '、'),
          AiAutoTagsHelpPage._tag('赶海'),
          const TextSpan(text: '属于旅游类，'),
          AiAutoTagsHelpPage._tag('美食'),
          const TextSpan(text: '属于生活类，从而实现整体管理。\n\n'),
          const TextSpan(
            text: '新建标签和 AI 自动打的标签若尚未归类，会显示在「未归类」里。',
          ),
        ],
      ),
    );
  }
}

class _GuideStepCard extends StatelessWidget {
  const _GuideStepCard({
    required this.figureIndex,
    required this.title,
    required this.desc,
  });

  final int figureIndex;
  final String title;
  final String desc;

  @override
  Widget build(BuildContext context) {
    final asset = AiAutoTagsHelpPage._figures[figureIndex];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => showAssetImagePreview(
              context,
              assets: AiAutoTagsHelpPage._figures,
              initialIndex: figureIndex,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                asset,
                width: 118,
                fit: BoxFit.fitWidth,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4, right: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AiAutoTagsHelpPage._text,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    desc,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AiAutoTagsHelpPage._muted,
                      height: 1.45,
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
