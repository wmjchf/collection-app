import 'package:flutter/material.dart';
import 'package:super_collection/core/theme/app_colors.dart';
import 'package:super_collection/features/settings/account_page.dart';
import 'package:super_collection/features/settings/settings_list.dart';
import 'package:super_collection/features/settings/settings_panel.dart';
import 'package:super_collection/features/settings/upgrade_pro_page.dart';
import 'package:super_collection/features/settings/usage_repository.dart';

/// 左侧账户抽屉（原设置页内容）
class AccountDrawer extends StatefulWidget {
  const AccountDrawer({super.key});

  @override
  State<AccountDrawer> createState() => _AccountDrawerState();
}

class _AccountDrawerState extends State<AccountDrawer> {
  bool _isPaid = false;
  bool _canUpgradeToEmperor = false;
  String _planLabel = '普通';
  bool _planLoaded = false;

  @override
  void initState() {
    super.initState();
    UsageRefresh.version.addListener(_onUsageRefresh);
    final cached = UsageRefresh.snapshot;
    if (cached != null) {
      _apply(cached);
    }
    _loadPlan();
  }

  @override
  void dispose() {
    UsageRefresh.version.removeListener(_onUsageRefresh);
    super.dispose();
  }

  void _onUsageRefresh() => _loadPlan();

  void _apply(UsageSummary usage) {
    _isPaid = usage.isPrince;
    _canUpgradeToEmperor = usage.isPrince && !usage.isEmperor;
    _planLabel = usage.displayPlan;
    _planLoaded = true;
  }

  Future<void> _loadPlan() async {
    try {
      final usage = await UsageRefresh.ensure();
      if (!mounted) return;
      setState(() => _apply(usage));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isPaid = false;
        _canUpgradeToEmperor = false;
        _planLabel = '普通';
        _planLoaded = true;
      });
    }
  }

  void _openUpgrade({String? initialTier}) {
    Navigator.of(context).push(
      MaterialPageRoute<bool?>(
        builder: (_) => UpgradeProPage(
          from: 'settings',
          initialTier: initialTier,
        ),
      ),
    );
  }

  void _openUpgradeToEmperor() => _openUpgrade(initialTier: UsagePlan.emperor);

  void _openAccount() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AccountPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final maxW = MediaQuery.sizeOf(context).width * 0.86;
    return Drawer(
      backgroundColor: colors.pageBg,
      width: maxW.clamp(280.0, 340.0),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '账户与设置',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: colors.ink,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(Icons.close_rounded, color: colors.ink),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: _AccountPlanCard(
                loaded: _planLoaded,
                planLabel: _planLabel,
                isPaid: _isPaid,
                canUpgradeToEmperor: _canUpgradeToEmperor,
                onUpgrade: _openUpgrade,
                onUpgradeToEmperor: _openUpgradeToEmperor,
                onOpenAccount: _openAccount,
              ),
            ),
            const Expanded(child: SettingsPanel(showAccountEntry: false)),
          ],
        ),
      ),
    );
  }
}

class _AccountPlanCard extends StatelessWidget {
  const _AccountPlanCard({
    required this.loaded,
    required this.planLabel,
    required this.isPaid,
    required this.canUpgradeToEmperor,
    required this.onUpgrade,
    required this.onUpgradeToEmperor,
    required this.onOpenAccount,
  });

  final bool loaded;
  final String planLabel;
  final bool isPaid;
  final bool canUpgradeToEmperor;
  final VoidCallback onUpgrade;
  final VoidCallback onUpgradeToEmperor;
  final VoidCallback onOpenAccount;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: !loaded
          ? const SizedBox(
              height: 88,
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          : Column(
              children: [
                InkWell(
                  onTap: isPaid
                      ? (canUpgradeToEmperor ? onUpgradeToEmperor : null)
                      : onUpgrade,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
                    child: Row(
                      children: [
                        _PlanGlyph(isPaid: isPaid),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isPaid ? planLabel : '普通',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: isPaid ? colors.brand : colors.ink,
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                isPaid
                                    ? (canUpgradeToEmperor
                                        ? '可升级帝王 · 脑图与转写'
                                        : '会员权益已生效')
                                    : '免费额度 · 收藏有上限',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.muted,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!isPaid)
                          const _TextAction(label: '订阅会员')
                        else if (canUpgradeToEmperor)
                          const _TextAction(label: '升级帝王'),
                      ],
                    ),
                  ),
                ),
                SettingsInfoRow(
                  title: '账户和用量',
                  showChevron: true,
                  onTap: onOpenAccount,
                ),
              ],
            ),
    );
  }
}

class _PlanGlyph extends StatelessWidget {
  const _PlanGlyph({required this.isPaid});

  final bool isPaid;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: isPaid ? colors.brandSoft : colors.inputBg,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(
        isPaid ? Icons.workspace_premium_rounded : Icons.person_rounded,
        size: 22,
        color: isPaid ? colors.brand : colors.muted,
      ),
    );
  }
}

class _TextAction extends StatelessWidget {
  const _TextAction({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: colors.brand,
          ),
        ),
        Icon(Icons.chevron_right, size: 20, color: colors.brand),
      ],
    );
  }
}
