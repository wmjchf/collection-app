import 'package:flutter/material.dart';
import 'package:super_collection/core/analytics/screen_dwell_tracker.dart';
import 'package:super_collection/core/config/app_brand.dart';
import 'package:super_collection/features/items/item_image_gallery.dart';

/// 如何添加链接（设置 → 使用帮助，本地写死）
class HowToAddLinkPage extends StatelessWidget {
  const HowToAddLinkPage({super.key});

  static const _bg = Color(0xFFF7F7FA);
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _blue = Color(0xFF2F6FED);
  static const _illustrationBg = Color(0xFFF0F2F5);

  static const _figures = <String>[
    'assets/how_to_add_link/share_sheet.png',
    'assets/how_to_add_link/paste_dialog.png',
    'assets/how_to_add_link/shortcuts.png',
  ];

  @override
  Widget build(BuildContext context) {
    return ScreenDwellScope(
      screen: AnalyticsScreens.howToAddLink,
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
            '如何添加链接',
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
            Text(
              '任选一种方式即可把链接存进 ${AppBrand.name}。',
              style: const TextStyle(fontSize: 14, color: _muted, height: 1.5),
            ),
            const SizedBox(height: 16),
            _MethodCard(
              number: 1,
              title: '系统分享',
              desc:
                  '在微信、Safari、B站、抖音等 App 里点「分享」，选择「${AppBrand.name}」即可入库。'
                  '图标行可左右滑动；若没有，点「编辑」打开开关。',
              captionAbove: '分享面板的应用一行 · 点「${AppBrand.name}」即可入库',
              figureIndex: 0,
            ),
            const SizedBox(height: 12),
            _MethodCard(
              number: 2,
              title: '复制链接自动保存',
              desc:
                  '先在其他 App 复制可用链接，再打开 ${AppBrand.name}（或从后台切回），'
                  '会自动读取剪贴板并保存。',
              captionBelow: '打开 ${AppBrand.name} 时点「允许粘贴」，即可自动读取并保存链接',
              figureIndex: 1,
            ),
            const SizedBox(height: 12),
            _MethodCard(
              number: 3,
              title: '快捷指令（iOS）',
              desc:
                  '复制链接后，可用主屏幕图标、控制中心或「轻点背面」（互不影响，任选）。'
                  '不必打开 App。设置 → iOS 快捷指令说明里可安装。',
              figureIndex: 2,
            ),
            const SizedBox(height: 20),
            Text(
              '${AppBrand.name} · 如何添加链接',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: _muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _MethodCard extends StatelessWidget {
  const _MethodCard({
    required this.number,
    required this.title,
    required this.desc,
    required this.figureIndex,
    this.captionAbove,
    this.captionBelow,
  });

  final int number;
  final String title;
  final String desc;
  final int figureIndex;
  final String? captionAbove;
  final String? captionBelow;

  @override
  Widget build(BuildContext context) {
    final asset = HowToAddLinkPage._figures[figureIndex];
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
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: HowToAddLinkPage._blue,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$number',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: HowToAddLinkPage._text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            desc,
            style: const TextStyle(
              fontSize: 14,
              color: HowToAddLinkPage._muted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
            decoration: BoxDecoration(
              color: HowToAddLinkPage._illustrationBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (captionAbove != null) ...[
                  Text(
                    captionAbove!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: HowToAddLinkPage._muted,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                GestureDetector(
                  onTap: () => showAssetImagePreview(
                    context,
                    assets: HowToAddLinkPage._figures,
                    initialIndex: figureIndex,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      asset,
                      width: double.infinity,
                      fit: BoxFit.fitWidth,
                    ),
                  ),
                ),
                if (captionBelow != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    captionBelow!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: HowToAddLinkPage._muted,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
