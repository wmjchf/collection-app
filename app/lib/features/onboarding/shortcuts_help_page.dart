import 'package:flutter/material.dart';
import 'package:super_collection/core/analytics/screen_dwell_tracker.dart';
import 'package:super_collection/core/config/app_brand.dart';
import 'package:super_collection/features/items/item_image_gallery.dart';
import 'package:super_collection/features/shortcuts/shortcut_config.dart';
import 'package:super_collection/features/shortcuts/shortcut_install.dart';

/// iOS 快捷指令说明（本地写死，排版对齐功能指引）
class ShortcutsHelpPage extends StatelessWidget {
  const ShortcutsHelpPage({super.key});

  static const _bg = Color(0xFFF7F7FA);
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _blue = Color(0xFF2F6FED);
  static const _tint = Color(0xFFEAF1FE);

  static const _figures = <String>[
    'assets/shortcuts/fig1.png',
    'assets/shortcuts/fig2.png',
    'assets/shortcuts/fig3.png',
    'assets/shortcuts/fig4.png',
    'assets/shortcuts/fig5.png',
    'assets/shortcuts/fig6.png',
  ];

  @override
  Widget build(BuildContext context) {
    final hasOneTap = ShortcutConfig.installIcloudUrl.trim().isNotEmpty;
    final name = AppBrand.shortcutInstallName;

    return ScreenDwellScope(
      screen: AnalyticsScreens.shortcutsHelp,
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
            '快捷指令',
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
            _InstallCard(hasOneTap: hasOneTap),
            const SizedBox(height: 24),
            const _SectionHeading('安装步骤'),
            const SizedBox(height: 10),
            const _GuideStepCard(
              figureIndex: 0,
              title: '添加快捷指令',
              desc: '在指令详情页点底部「添加快捷指令」，提示添加成功即可。',
            ),
            const SizedBox(height: 12),
            _GuideStepCard(
              figureIndex: 1,
              title: '找到指令',
              desc: '打开「快捷指令」App，在所有快捷指令里找到「$name」，点开这张卡片。',
            ),
            const SizedBox(height: 24),
            Text(
              '装好后，主屏幕、控制中心、轻点背面三种入口互不影响，任选其一或一起开。',
              style: const TextStyle(fontSize: 14, color: _muted, height: 1.5),
            ),
            const SizedBox(height: 24),
            const _SectionHeading('加到主屏幕'),
            const SizedBox(height: 10),
            const _GuideStepCard(
              figureIndex: 2,
              title: '点分享按钮',
              desc: '在指令详情页点底部分享按钮，打开分享面板。',
            ),
            const SizedBox(height: 12),
            const _GuideStepCard(
              figureIndex: 3,
              title: '添加到主屏幕',
              desc: '在分享面板里选「添加到主屏幕」，按提示完成添加。',
            ),
            const SizedBox(height: 10),
            _UsageTip('之后：复制链接 → 点主屏幕上的「$name」图标。'),
            const SizedBox(height: 24),
            const _SectionHeading('加到控制中心'),
            const SizedBox(height: 10),
            _TextGuideCard(
              body:
                  'iOS 18 及更新：打开控制中心 → 点左上角「+」→「添加控件」'
                  '→ 搜「快捷指令」→ 选「$name」。\n\n'
                  '之后：复制链接 → 从右上角下滑控制中心，点该控件。',
            ),
            const SizedBox(height: 24),
            const _SectionHeading('轻点背面'),
            const SizedBox(height: 10),
            const _TextGuideCard(
              body:
                  'iPhone 8 及更新：设置 → 辅助功能 → 触控 → 轻点背面 → 轻点两下。',
            ),
            const SizedBox(height: 12),
            const _GuideStepCard(
              figureIndex: 4,
              title: '搜索「轻点两下」',
              desc: '打开「设置」，搜索「轻点」，找到「轻点两下」并进入。',
            ),
            const SizedBox(height: 12),
            _GuideStepCard(
              figureIndex: 5,
              title: '勾选指令',
              desc:
                  '在快捷指令列表往下滑，找到并勾选「$name」。'
                  '之后复制链接，在手机背面连点两下即可自动保存。',
            ),
            const SizedBox(height: 10),
            _UsageTip('之后：复制链接 → 在手机背面连点两下。'),
            const SizedBox(height: 20),
            const Text(
              '快捷指令设置指引 · 功能指引',
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
        color: ShortcutsHelpPage._muted,
      ),
    );
  }
}

class _InstallCard extends StatelessWidget {
  const _InstallCard({required this.hasOneTap});

  final bool hasOneTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hasOneTap
                ? '复制链接后，通过快捷指令一键保存到 ${AppBrand.name}。'
                '只需安装一次，之后任选下面一种方式触发即可。'
                : '预置安装链接配置后，点下方按钮即可一键添加，无需自己搜索拼接。',
            style: const TextStyle(
              fontSize: 15,
              color: ShortcutsHelpPage._text,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '只需一次，点击按钮添加快捷指令',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: ShortcutsHelpPage._blue,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: hasOneTap ? () => openShortcutInstall(context) : null,
              style: FilledButton.styleFrom(
                backgroundColor: ShortcutsHelpPage._blue,
                disabledBackgroundColor: const Color(0xFFB8C4D9),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                '添加快捷指令',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          if (!hasOneTap) ...[
            const SizedBox(height: 8),
            const Text(
              '开发者尚未配置 iCloud 预置链接，按钮暂不可用。',
              style: TextStyle(
                fontSize: 12,
                color: ShortcutsHelpPage._muted,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _UsageTip extends StatelessWidget {
  const _UsageTip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: ShortcutsHelpPage._tint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          color: ShortcutsHelpPage._text,
          height: 1.45,
        ),
      ),
    );
  }
}

class _TextGuideCard extends StatelessWidget {
  const _TextGuideCard({required this.body});

  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        body,
        style: const TextStyle(
          fontSize: 14,
          color: ShortcutsHelpPage._muted,
          height: 1.5,
        ),
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
    final asset = ShortcutsHelpPage._figures[figureIndex];
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
              assets: ShortcutsHelpPage._figures,
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
                      color: ShortcutsHelpPage._text,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    desc,
                    style: const TextStyle(
                      fontSize: 13,
                      color: ShortcutsHelpPage._muted,
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
