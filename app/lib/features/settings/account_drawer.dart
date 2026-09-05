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

  final _usageRepo = UsageRepository();
  bool _isPaid = false;
  String _planLabel = '普通';
  bool _planLoaded = false;

  @override
  void initState() {
    super.initState();
    UsageRefresh.version.addListener(_onUsageRefresh);
    _loadPlan();
  }

  @override
  void dispose() {
    UsageRefresh.version.removeListener(_onUsageRefresh);
    super.dispose();
  }

  void _onUsageRefresh() => _loadPlan();

  Future<void> _loadPlan() async {
    try {
      final usage = await _usageRepo.fetchUsage();
      if (!mounted) return;
      setState(() {
        _isPaid = usage.isPrince;
        _planLabel = usage.displayPlan;
        _planLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isPaid = false;
        _planLabel = '普通';
        _planLoaded = true;
      });
    }
  }

  void _openUpgrade() {
    Navigator.of(context).push(
      MaterialPageRoute<bool?>(
        builder: (_) => const UpgradeProPage(from: 'settings'),
      ),
    );
  }

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
                onUpgrade: _openUpgrade,
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
    required this.onUpgrade,
    required this.onOpenAccount,
  });

  final bool loaded;
  final String planLabel;
  final bool isPaid;
  final VoidCallback onUpgrade;
  final VoidCallback onOpenAccount;

  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _blue = Color(0xFF2F6FED);
  static const _blueSoft = Color(0xFFE8F0FF);
  static const _divider = Color(0xFFECEEF2);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!loaded)
            const SizedBox(
              height: 64,
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (isPaid)
            ColoredBox(
              color: _blueSoft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            planLabel,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: _blue,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            '当前方案 · 会员权益已生效',
                            style: TextStyle(
                              fontSize: 12,
                              color: _muted,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.verified_rounded, color: _blue, size: 24),
                  ],
                ),
              ),
            )
          else
            InkWell(
              onTap: onUpgrade,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '普通',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: _text,
                              height: 1.2,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            '免费额度 · 收藏有上限',
                            style: TextStyle(
                              fontSize: 12,
                              color: _muted,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _blueSoft,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '订阅会员',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _blue,
                            ),
                          ),
                          SizedBox(width: 2),
                          Icon(Icons.chevron_right, size: 22, color: _blue),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (loaded) ...[
            const Divider(height: 1, thickness: 1, color: _divider),
            InkWell(
              onTap: onOpenAccount,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
        ],
      ),
    );
  }
}
