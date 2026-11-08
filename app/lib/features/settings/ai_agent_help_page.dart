import 'package:flutter/material.dart';
import 'package:super_collection/core/analytics/screen_dwell_tracker.dart';
import 'package:super_collection/features/items/item_image_gallery.dart';
import 'package:super_collection/features/settings/help_assets_loader.dart';
import 'package:super_collection/features/settings/help_assets_repository.dart';
import 'package:super_collection/features/settings/settings_modal.dart';

/// 设置 → 使用帮助 → AI助手（文案本地写死，配图 OSS help/）
class AiAgentHelpPage extends StatelessWidget {
  const AiAgentHelpPage({super.key});

  static const _bg = Color(0xFFF7F7FA);
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _blue = Color(0xFF2F6FED);
  static const _tint = Color(0xFFEAF1FE);
  static const _illustrationBg = Color(0xFFF0F2F5);

  @override
  Widget build(BuildContext context) {
    return ScreenDwellScope(
      screen: AnalyticsScreens.aiAgentHelp,
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
            'AI助手',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: _text,
            ),
          ),
        ),
        body: HelpAssetsLoader(
          set: HelpAssetsRepository.aiAgent,
          builder: (context, urls) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              const _IntroCard(),
              const SizedBox(height: 16),
              _ScreenshotCard(urls: urls),
              const SizedBox(height: 24),
              const _SectionHeading('能做什么'),
              const SizedBox(height: 10),
              const _CapabilityCard(
                title: '意图搜索',
                desc:
                    '按你的意思在库里找，不只关键词硬匹配。例如「类似这篇文章的」「关于××的有哪些」。',
              ),
              const SizedBox(height: 12),
              const _CapabilityCard(
                title: '对照内容',
                desc: '勾选或点名几篇，让助手比较异同、梳理要点。',
              ),
              const SizedBox(height: 12),
              const _CapabilityCard(
                title: '深挖原文',
                desc: '从阅读页打开助手后，围绕当前篇追问观点、原话或细节。全局助手不做深挖。',
              ),
              const SizedBox(height: 12),
              const _CapabilityCard(
                title: '转写写文章',
                desc:
                    '从阅读页打开已转写视频，说「根据转写写一篇文章」：整理成可读长文。暂不支持用正文生成，也不做图文创作。',
              ),
              const SizedBox(height: 24),
              const _SectionHeading('从哪里打开'),
              const SizedBox(height: 10),
              const _WhiteCard(
                child: Text(
                  '手机：首页、收藏顶栏或阅读页底栏全屏打开；'
                  'iPad：列表|阅读时从列表右缘顶入；收藏枢纽则把主区压一半。'
                  '只基于你自己的收藏库回答，不联网搜库外网页。',
                  style: TextStyle(fontSize: 15, color: _text, height: 1.55),
                ),
              ),
              const SizedBox(height: 24),
              const _SectionHeading('订阅与额度'),
              const SizedBox(height: 10),
              const _ProCard(
                child: Text(
                  '需开通太子Pro / 帝王Pro。对话消耗本月 AI助手额度；'
                  '解析后/转写后的自动打标签不占用该额度。'
                  '帝王Pro 提供更高月额度。音视频转写是另一项核心能力，在阅读页「更多」里发起。',
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.white,
                    height: 1.55,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const _SectionHeading('小技巧'),
              const SizedBox(height: 10),
              const _TipCard(
                '点名标题，或先勾选出处再提问，指代更清楚。',
              ),
              const SizedBox(height: 12),
              const _TipCard(
                '添加或删除标签请到阅读页；归类请到收藏页手建与拖动。',
              ),
              const SizedBox(height: 12),
              const _TipCard(
                '划选助手回复可复制，或做成分享海报。',
              ),
              const SizedBox(height: 20),
              const Text(
                'AI助手 · 功能指引',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: _muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScreenshotCard extends StatelessWidget {
  const _ScreenshotCard({required this.urls});

  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    final url = urls.first;
    return _WhiteCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 4, 4, 0),
            child: Text(
              '界面一览',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AiAgentHelpPage._text,
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '可按意图搜索与对照；从阅读页打开后还可深挖。',
              style: TextStyle(
                fontSize: 13,
                color: AiAgentHelpPage._muted,
                height: 1.45,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AiAgentHelpPage._illustrationBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: HelpNetworkImage(
              url: url,
              width: double.infinity,
              borderRadius: 8,
              onTap: () => showNetworkImagePreview(
                context,
                urls: urls,
                initialIndex: 0,
              ),
            ),
          ),
        ],
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
        color: AiAgentHelpPage._muted,
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
            '太子Pro 的核心能力之一：在你的收藏库里做意图搜索与对照；'
            '从阅读页打开还可深挖当前篇、根据已转写视频写文章。'
            '另一核心能力是音视频转写。标签请到阅读页添加或删除；归类请到收藏页手建。',
            style: TextStyle(
              fontSize: 15,
              color: AiAgentHelpPage._text,
              height: 1.55,
            ),
          ),
          SizedBox(height: 14),
          _HighlightStrip(),
        ],
      ),
    );
  }
}

class _HighlightStrip extends StatelessWidget {
  const _HighlightStrip();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AiAgentHelpPage._tint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text(
        '不是全网搜索，而是按意图翻你自己存过的内容——找得到、对得上、用得上。',
        style: TextStyle(
          fontSize: 14,
          color: AiAgentHelpPage._text,
          height: 1.5,
        ),
      ),
    );
  }
}

class _CapabilityCard extends StatelessWidget {
  const _CapabilityCard({
    required this.title,
    required this.desc,
  });

  final String title;
  final String desc;

  @override
  Widget build(BuildContext context) {
    return _WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AiAgentHelpPage._text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            desc,
            style: const TextStyle(
              fontSize: 14,
              color: AiAgentHelpPage._muted,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _TipCard extends StatelessWidget {
  const _TipCard(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return _WhiteCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(
              Icons.check_circle_outline_rounded,
              size: 18,
              color: AiAgentHelpPage._blue,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                color: AiAgentHelpPage._text,
                height: 1.5,
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
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
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
        color: AiAgentHelpPage._blue,
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
