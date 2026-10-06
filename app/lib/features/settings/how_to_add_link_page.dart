import 'package:flutter/material.dart';
import 'package:super_collection/core/theme/app_colors.dart';
import 'package:super_collection/core/analytics/screen_dwell_tracker.dart';
import 'package:super_collection/core/config/app_brand.dart';
import 'package:super_collection/features/items/item_image_gallery.dart';
import 'package:super_collection/features/settings/help_assets_loader.dart';
import 'package:super_collection/features/settings/help_assets_repository.dart';

/// 如何添加链接（文案本地写死，配图 OSS help/）
class HowToAddLinkPage extends StatelessWidget {
  const HowToAddLinkPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return ScreenDwellScope(
      screen: AnalyticsScreens.howToAddLink,
      child: Scaffold(
        backgroundColor: colors.pageBg,
        appBar: AppBar(
          centerTitle: true,
          leadingWidth: 80,
          leading: TextButton.icon(
            onPressed: () => Navigator.of(context).maybePop(),
            style: TextButton.styleFrom(
              foregroundColor: colors.ink,
              padding: const EdgeInsets.only(left: 8),
            ),
            icon: const Icon(Icons.chevron_left, size: 30),
            label: const Text('返回', style: TextStyle(fontSize: 15)),
          ),
          title: Text(
            '如何添加链接',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: colors.ink,
            ),
          ),
        ),
        body: HelpAssetsLoader(
          set: HelpAssetsRepository.howToAddLink,
          builder: (context, urls) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Text(
              '任选一种方式即可把链接存进 ${AppBrand.name}。',
              style: TextStyle(fontSize: 14, color: colors.muted, height: 1.5),
            ),
            const SizedBox(height: 16),
            _MethodCard(
              urls: urls,
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
              urls: urls,
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
              urls: urls,
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
              style: TextStyle(fontSize: 12, color: colors.muted),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

class _MethodCard extends StatelessWidget {
  const _MethodCard({
    required this.urls,
    required this.number,
    required this.title,
    required this.desc,
    required this.figureIndex,
    this.captionAbove,
    this.captionBelow,
  });

  final List<String> urls;
  final int number;
  final String title;
  final String desc;
  final int figureIndex;
  final String? captionAbove;
  final String? captionBelow;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final url = urls[figureIndex.clamp(0, urls.length - 1)];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
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
                decoration: BoxDecoration(
                  color: colors.brand,
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
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: colors.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            desc,
            style: TextStyle(
              fontSize: 14,
              color: colors.muted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
            decoration: BoxDecoration(
              color: colors.inputBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (captionAbove != null) ...[
                  Text(
                    captionAbove!,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.muted,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                HelpNetworkImage(
                  url: url,
                  width: double.infinity,
                  borderRadius: 8,
                  onTap: () => showNetworkImagePreview(
                    context,
                    urls: urls,
                    initialIndex: figureIndex,
                  ),
                ),
                if (captionBelow != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    captionBelow!,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.muted,
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
