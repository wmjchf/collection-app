import 'package:flutter/material.dart';
import 'package:super_collection/features/settings/account_page.dart';
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
  static const _bg = Color(0xFFF7F7FA);
  static const _text = Color(0xFF1F242E);

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
    final maxW = MediaQuery.sizeOf(context).width * 0.86;
    return Drawer(
      backgroundColor: _bg,
      width: maxW.clamp(280.0, 340.0),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '账户与设置',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _text,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close_rounded, color: _text),
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

/// 身份卡：方案 + 订阅入口 + 账户和用量，同一白底，无分割线、无双色底。
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

  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _blue = Color(0xFF2F6FED);
  static const _blueSoft = Color(0xFFE8F0FF);

  String get _subtitle {
    if (!isPaid) return '免费额度 · 收藏有上限';
    if (canUpgradeToEmperor) return '可升级帝王 · 脑图与转写';
    return '当前方案 · 会员权益已生效';
  }

  VoidCallback? get _planAction {
    if (!isPaid) return onUpgrade;
    if (canUpgradeToEmperor) return onUpgradeToEmperor;
    return null;
  }

  String? get _actionLabel {
    if (!isPaid) return '订阅会员';
    if (canUpgradeToEmperor) return '升级帝王';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: !loaded
          ? const SizedBox(
              height: 96,
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  onTap: _planAction,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: const BoxDecoration(
                            color: _blueSoft,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isPaid
                                ? Icons.workspace_premium_rounded
                                : Icons.person_rounded,
                            size: 22,
                            color: _blue,
                          ),
                        ),
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
                                  color: isPaid ? _blue : _text,
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _subtitle,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: _muted,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_actionLabel != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _actionLabel!,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _blue,
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right,
                                size: 20,
                                color: _blue,
                              ),
                            ],
                          )
                        else
                          const Icon(
                            Icons.verified_rounded,
                            color: _blue,
                            size: 22,
                          ),
                      ],
                    ),
                  ),
                ),
                InkWell(
                  onTap: onOpenAccount,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 12, 16),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '账户和用量',
                            style: TextStyle(
                              fontSize: 15,
                              color: _text,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          size: 22,
                          color: _muted.withValues(alpha: 0.9),
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
