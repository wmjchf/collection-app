import 'package:flutter/material.dart';
import 'package:super_collection/core/analytics/screen_dwell_tracker.dart';
import 'package:super_collection/features/auth/auth_repository.dart';
import 'package:super_collection/features/settings/upgrade_pro_page.dart';
import 'package:super_collection/features/settings/usage_repository.dart';

/// 账户详情：手机号、收藏容量、本月 AI / 转写用量。
class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> with ScreenDwellMixin {
  static const _bg = Color(0xFFF7F7FA);
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _blue = Color(0xFF2F6FED);

  final _auth = AuthRepository();
  final _usageRepo = UsageRepository();

  AuthSession? _session;
  UsageSummary? _usage;
  bool _loading = true;

  @override
  String get dwellScreen => AnalyticsScreens.account;

  @override
  void initState() {
    super.initState();
    UsageRefresh.version.addListener(_onUsageRefresh);
    _load();
  }

  @override
  void dispose() {
    UsageRefresh.version.removeListener(_onUsageRefresh);
    super.dispose();
  }

  void _onUsageRefresh() => _load();

  Future<void> _load() async {
    final session = await _auth.readSession();
    UsageSummary? usage;
    try {
      usage = await _usageRepo.fetchUsage();
    } catch (_) {
      usage = null;
    }
    if (!mounted) return;
    setState(() {
      _session = session;
      _usage = usage;
      _loading = false;
    });
  }

  String _maskedPhone(String? phone) {
    if (phone == null || phone.isEmpty) return '—';
    final digits = phone.split('').where((c) {
      final code = c.codeUnitAt(0);
      return code >= 48 && code <= 57;
    }).join();
    if (digits.length >= 7) {
      return '${digits.substring(0, 3)}****${digits.substring(digits.length - 4)}';
    }
    return phone;
  }

  String _fmtMinutes(double m) {
    if (m == m.roundToDouble()) return m.toInt().toString();
    return m.toStringAsFixed(1);
  }

  String _planLabel(UsageSummary? usage) {
    if (usage == null) return '—';
    return usage.displayPlan;
  }

  String? _planExpiresLabel(UsageSummary? usage) {
    final raw = usage?.planExpiresAt;
    if (raw == null || raw.isEmpty) return null;
    final dt = DateTime.tryParse(raw);
    if (dt == null) return null;
    final local = dt.toLocal();
    final y = local.year;
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '有效期至 $y-$m-$d';
  }

  void _openUpgrade() {
    Navigator.of(context).push(
      MaterialPageRoute<bool?>(
        builder: (_) => const UpgradeProPage(from: 'account'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
          '账户和用量',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: _text,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
              children: [
                const _SectionLabel('账号信息'),
                const SizedBox(height: 8),
                _CardGroup(
                  children: [
                    _InfoRow(
                      title: '手机号',
                      trailing: Text(
                        _maskedPhone(_session?.phone),
                        style: const TextStyle(fontSize: 14, color: _muted),
                      ),
                    ),
                    if (_session?.nickname.isNotEmpty == true)
                      _InfoRow(
                        title: '昵称',
                        trailing: Text(
                          _session!.nickname,
                          style: const TextStyle(fontSize: 14, color: _muted),
                        ),
                      ),
                    _InfoRow(
                      title: '当前方案',
                      trailing: Text(
                        _planLabel(_usage),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _usage!.isPrince ? _blue : _muted,
                        ),
                      ),
                    ),
                    if (_planExpiresLabel(_usage) != null)
                      _InfoRow(
                        title: '订阅',
                        trailing: Text(
                          _planExpiresLabel(_usage)!,
                          style: const TextStyle(fontSize: 14, color: _muted),
                        ),
                      ),
                  ],
                ),
                if (_usage != null && !_usage!.isPrince) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: TextButton(
                      onPressed: _openUpgrade,
                      style: TextButton.styleFrom(
                        backgroundColor: const Color(0xFFE8F0FF),
                        foregroundColor: _blue,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        '订阅会员',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                const _SectionLabel('使用容量'),
                const SizedBox(height: 8),
                _CardGroup(
                  children: [
                    if (_usage != null)
                      _UsageRow(
                        title: '收藏条目',
                        usedLabel: '${_usage!.itemCount} 条',
                        limitLabel: _usage!.itemLimit != null
                            ? '${_usage!.itemLimit} 条'
                            : '不限',
                        progress: _usage!.itemLimit != null &&
                                _usage!.itemLimit! > 0
                            ? (_usage!.itemCount / _usage!.itemLimit!)
                                .clamp(0.0, 1.0)
                            : 0,
                        showProgress: _usage!.itemLimit != null,
                      )
                    else
                      const _InfoRow(
                        title: '收藏条目',
                        trailing: Text(
                          '—',
                          style: TextStyle(fontSize: 14, color: _muted),
                        ),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                  child: Text(
                    _usage?.itemLimit != null
                        ? '统计当前在库收藏（不含已删除）；免费账户上限 ${_usage!.itemLimit} 条。'
                        : '统计当前在库收藏（不含已删除）；会员不限条数。',
                    style: const TextStyle(
                      fontSize: 12,
                      color: _muted,
                      height: 1.45,
                    ),
                  ),
                ),
                if (_usage != null) ...[
                  const SizedBox(height: 16),
                  _SectionLabel(
                    _usage!.yearMonth.isEmpty
                        ? '本月用量'
                        : '本月用量（${_usage!.yearMonth}）',
                  ),
                  const SizedBox(height: 8),
                  _CardGroup(
                    children: [
                      _UsageRow(
                        title: '转写',
                        usedLabel:
                            '${_fmtMinutes(_usage!.transcriptUsedMinutes)} 分钟',
                        limitLabel: _usage!.features.transcript
                            ? '${_fmtMinutes(_usage!.transcriptLimitMinutes)} 分钟'
                            : '—',
                        progress: _usage!.features.transcript &&
                                _usage!.transcriptLimitMinutes > 0
                            ? (_usage!.transcriptUsedMinutes /
                                    _usage!.transcriptLimitMinutes)
                                .clamp(0.0, 1.0)
                            : 0,
                        showProgress: _usage!.features.transcript &&
                            _usage!.transcriptLimitMinutes > 0,
                      ),
                      _UsageRow(
                        title: 'AI',
                        usedLabel:
                            '${formatAiCredits(_usage!.aiUsedTokens)} 积分',
                        limitLabel: _usage!.features.aiTags
                            ? '${formatAiCredits(_usage!.aiLimitTokens)} 积分'
                            : '—',
                        progress: _usage!.features.aiTags &&
                                _usage!.aiLimitTokens > 0
                            ? (_usage!.aiUsedTokens / _usage!.aiLimitTokens)
                                .clamp(0.0, 1.0)
                            : 0,
                        showProgress:
                            _usage!.features.aiTags && _usage!.aiLimitTokens > 0,
                      ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: Color(0xFF737A85),
        ),
      ),
    );
  }
}

class _CardGroup extends StatelessWidget {
  const _CardGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.title,
    this.trailing,
  });

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                color: Color(0xFF1F242E),
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _UsageRow extends StatelessWidget {
  const _UsageRow({
    required this.title,
    required this.usedLabel,
    required this.limitLabel,
    required this.progress,
    this.showProgress = true,
  });

  final String title;
  final String usedLabel;
  final String limitLabel;
  final double progress;
  final bool showProgress;

  static const _muted = Color(0xFF737A85);
  static const _track = Color(0xFFECEEF2);
  static const _fill = Color(0xFF2F6FED);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Color(0xFF1F242E),
                  ),
                ),
              ),
              Text(
                '$usedLabel / $limitLabel',
                style: const TextStyle(fontSize: 14, color: _muted),
              ),
            ],
          ),
          if (showProgress) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: _track,
                color: _fill,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
