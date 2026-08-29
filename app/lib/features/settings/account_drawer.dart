import 'package:flutter/material.dart';
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
  bool _isPro = false;
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
        _isPro = usage.isPro;
        _planLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isPro = false;
        _planLoaded = true;
      });
    }
  }

  void _openUpgrade() {
    Navigator.of(context).push(
      MaterialPageRoute<bool?>(builder: (_) => const UpgradeProPage()),
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
              child: _PlanBanner(
                loaded: _planLoaded,
                isPro: _isPro,
                onUpgrade: _openUpgrade,
              ),
            ),
            const Expanded(child: SettingsPanel()),
          ],
        ),
      ),
    );
  }
}

class _PlanBanner extends StatelessWidget {
  const _PlanBanner({
    required this.loaded,
    required this.isPro,
    required this.onUpgrade,
  });

  final bool loaded;
  final bool isPro;
  final VoidCallback onUpgrade;

  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _blue = Color(0xFF2F6FED);
  static const _blueSoft = Color(0xFFE8F0FF);

  @override
  Widget build(BuildContext context) {
    if (!loaded) {
      return Container(
        height: 64,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (isPro) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: _blueSoft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pro',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _blue,
                      height: 1.2,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    '当前方案 · 更高月额度',
                    style: TextStyle(
                      fontSize: 12,
                      color: _muted,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.verified_rounded, color: _blue, size: 22),
          ],
        ),
      );
    }

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
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
                      '免费额度 · 解析不限次',
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _blueSoft,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '升级 Pro',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _blue,
                      ),
                    ),
                    SizedBox(width: 2),
                    Icon(Icons.chevron_right, size: 18, color: _blue),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
