import 'package:flutter/material.dart';
import 'package:super_collection/features/settings/settings_modal.dart';
import 'package:super_collection/core/analytics/screen_dwell_tracker.dart';
import 'package:super_collection/features/items/item_image_gallery.dart';
import 'package:super_collection/features/settings/help_assets_loader.dart';
import 'package:super_collection/features/settings/help_assets_repository.dart';

/// 设置 → 使用帮助 → AI自动标签方法（文案本地写死，配图 OSS help/）
class AiAutoTagsHelpPage extends StatelessWidget {
  const AiAutoTagsHelpPage({super.key});

  static const _bg = Color(0xFFF7F7FA);
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _blue = Color(0xFF2F6FED);
  static const _tint = Color(0xFFEAF1FE);

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
          leadingWidth: SettingsBackButton.leadingWidth,
          leading: const SettingsBackButton(),
          title: const Text(
            'AI自动标签方法',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: _text,
            ),
          ),
        ),
        body: HelpAssetsLoader(
          set: HelpAssetsRepository.aiAutoTags,
          builder: (context, urls) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            const _IntroCard(),
            const SizedBox(height: 24),
            const _SectionHeading('在 App 里整理标签'),
            const SizedBox(height: 10),
            _GuideStepCard(
              urls: urls,
              figureIndex: 0,
              title: '标签与归类一览',
              desc:
                  '在「我的收藏」进入归类标签：顶部是未归类的标签，'
                  '下方是你建好的归类；点右上角 + 新建归类，点归类或标签可查看对应内容。',
            ),
            const SizedBox(height: 12),
            _GuideStepCard(
              urls: urls,
              figureIndex: 1,
              title: '创建归类',
              desc:
                  '归类名由你来定。归类旁的 ··· 可改名、往归类里加标签，或删除整个归类。',
            ),
            const SizedBox(height: 12),
            _GuideStepCard(
              urls: urls,
              figureIndex: 2,
              title: '拖动整理',
              desc: '长按标签拖到目标归类即可整理。',
            ),
            const SizedBox(height: 24),
            const _SectionHeading('解析后自动打标签'),
            const SizedBox(height: 10),
            const _ProCard(
              child: Text(
                '太子Pro / 帝王Pro：粘贴链接解析完成后，文章会自动打标签；'
                '视频在转写成功后同样自动打标；图集不自动打标。'
                '打标后不会自动归类；可在收藏页新建归类并拖动标签。'
                '点进内容可在上方看到标签。',
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
              'AI自动标签 · 功能指引',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: _muted),
            ),
          ],
        ),
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
            '一篇好内容常有多个突出点，不宜只塞进一个死文件夹。'
            '奏折用「标签」标记内容，再用你自建的「归类」把标签分格摆放；'
            '太子+ 解析/转写后会自动打标签；可在收藏页新建归类，并把标签拖进去。',
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
                '夏天去青岛赶海的游记，内容里有海边与美食，可以打标签为',
          ),
          AiAutoTagsHelpPage._tag('青岛'),
          const TextSpan(text: '、'),
          AiAutoTagsHelpPage._tag('海边'),
          const TextSpan(text: '、'),
          AiAutoTagsHelpPage._tag('赶海'),
          const TextSpan(text: '、'),
          AiAutoTagsHelpPage._tag('美食'),
          const TextSpan(text: '。\n\n你先建归类「旅游」「生活」，再把'),
          AiAutoTagsHelpPage._tag('青岛'),
          const TextSpan(text: '、'),
          AiAutoTagsHelpPage._tag('海边'),
          const TextSpan(text: '、'),
          AiAutoTagsHelpPage._tag('赶海'),
          const TextSpan(text: '放进旅游，'),
          AiAutoTagsHelpPage._tag('美食'),
          const TextSpan(text: '放进生活。\n\n'),
          const TextSpan(
            text: '尚未归类的标签会留在上方未归类区，对不上的可先放着。',
          ),
        ],
      ),
    );
  }
}

class _GuideStepCard extends StatelessWidget {
  const _GuideStepCard({
    required this.urls,
    required this.figureIndex,
    required this.title,
    required this.desc,
  });

  final List<String> urls;
  final int figureIndex;
  final String title;
  final String desc;

  @override
  Widget build(BuildContext context) {
    final url = urls[figureIndex.clamp(0, urls.length - 1)];
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
          HelpNetworkImage(
            url: url,
            width: 118,
            onTap: () => showNetworkImagePreview(
              context,
              urls: urls,
              initialIndex: figureIndex,
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
