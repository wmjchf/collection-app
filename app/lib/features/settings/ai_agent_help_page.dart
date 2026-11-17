import 'package:flutter/material.dart';
import 'package:super_collection/core/analytics/screen_dwell_tracker.dart';
import 'package:super_collection/features/settings/settings_modal.dart';

/// 设置 → 使用帮助 → AI Agent（文案本地写死）
class AiAgentHelpPage extends StatelessWidget {
  const AiAgentHelpPage({super.key});

  static const _bg = Color(0xFFF7F7FA);
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _blue = Color(0xFF2F6FED);

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
            'AI Agent',
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
            const _SectionHeading('能做什么'),
            const SizedBox(height: 10),
            const _CapabilityCard(
              title: '意图检索',
              desc:
                  '摆脱机械的关键词硬匹配。通过自然语言理解你的真实意图，精准定位库中相关内容'
                  '（如「找找类似这篇的文章」或「关于某主题的合集」）。',
            ),
            const SizedBox(height: 12),
            const _CapabilityCard(
              title: '深度研读',
              desc:
                  '在精读模式下随时唤醒，围绕当前文章深入追问核心观点、关键原话或细节逻辑，'
                  '实现单篇内容的穿透式理解。',
            ),
            const SizedBox(height: 12),
            const _CapabilityCard(
              title: '智能归类',
              desc:
                  '智能分析并提取标签，自动规划归类路径。支持全链路预览与二次微调，'
                  '确保每一次写入都完美契合你的知识体系。',
            ),
            const SizedBox(height: 12),
            const _CapabilityCard(
              title: '视频转写',
              desc:
                  '一键将播客、视频等非文本介质转化为结构清晰的可读文稿，'
                  '为深度信息提炼与知识重构奠定基础。',
            ),
            const SizedBox(height: 12),
            const _CapabilityCard(
              title: '图文重构',
              desc:
                  '将已转写的视听文稿或知识类长图一键提炼，重构为逻辑严密、排版干净的深度文章。'
                  '专注于私域知识消化，不涉足无源的图文创作。',
            ),
            const SizedBox(height: 24),
            const _SectionHeading('从哪里打开'),
            const SizedBox(height: 10),
            const _WhiteCard(
              child: Text(
                '手机：首页、收藏顶栏或阅读页底栏全屏打开；'
                'iPad：列表|阅读时从列表右缘顶入；收藏枢纽则把主区压一半。'
                '不联网搜库外网页。',
                style: TextStyle(fontSize: 15, color: _text, height: 1.55),
              ),
            ),
            const SizedBox(height: 24),
            const _SectionHeading('订阅与额度'),
            const SizedBox(height: 10),
            const _ProCard(
              child: Text(
                '需开通太子Pro / 帝王Pro。对话与整理成文章（含根据图片）消耗本月 AI Agent 额度；'
                '帝王Pro 提供更高月额度。生成文稿按分钟单独计量，常作为视频成文的前一步。',
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
              '打标签请在阅读页打开助手；整理归类请用首页/收藏顶栏的全局助手。',
            ),
            const SizedBox(height: 12),
            const _TipCard(
              '划选助手回复可复制，或做成分享海报。',
            ),
            const SizedBox(height: 20),
            const Text(
              'AI Agent · 功能指引',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: _muted),
            ),
          ],
        ),
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
            '太子Pro 核心能力 · 专属私有知识库的智能中枢',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AiAgentHelpPage._text,
              height: 1.45,
            ),
          ),
          SizedBox(height: 10),
          Text(
            '依托 Agentic Search 理解意图，在个人收藏库中检索；也可深度研读单篇、整理归类；'
            '音视频、知识类图片也可整理成文章，沉淀为你的个人资产。',
            style: TextStyle(
              fontSize: 14,
              color: AiAgentHelpPage._muted,
              height: 1.55,
            ),
          ),
        ],
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
