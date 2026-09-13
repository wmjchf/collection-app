import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_collection/features/settings/usage_repository.dart';
import 'package:url_launcher/url_launcher.dart';

/// 试用即将结束站内条（首页 / 账户页）
class TrialExpiryBanner extends StatefulWidget {
  const TrialExpiryBanner({
    super.key,
    required this.reminder,
    this.margin = EdgeInsets.zero,
  });

  final TrialReminder reminder;
  final EdgeInsetsGeometry margin;

  static Future<bool> isDismissed(String endsAt) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_dismissKey(endsAt)) == true;
  }

  static Future<void> dismiss(String endsAt) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dismissKey(endsAt), true);
  }

  static String _dismissKey(String endsAt) => 'trial_reminder_dismissed_$endsAt';

  @override
  State<TrialExpiryBanner> createState() => _TrialExpiryBannerState();
}

class _TrialExpiryBannerState extends State<TrialExpiryBanner> {
  static const _accent = Color(0xFF2A6B52);
  static const _bg = Color(0xFFE8F3EE);
  static const _border = Color(0xFFD0E4DA);
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF5A6B63);

  bool _hidden = false;

  Future<void> _openManageSubscriptions() async {
    final uri = Uri.parse('https://apps.apple.com/account/subscriptions');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _dismiss() async {
    await TrialExpiryBanner.dismiss(widget.reminder.endsAt);
    if (!mounted) return;
    setState(() => _hidden = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden) return const SizedBox.shrink();

    return Padding(
      padding: widget.margin,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _border),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.schedule_rounded,
                  size: 20,
                  color: _accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.reminder.bodyText,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: _text,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (!kIsWeb && Platform.isIOS) ...[
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: _openManageSubscriptions,
                        child: const Text(
                          '管理订阅',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _accent,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: '关闭',
                onPressed: _dismiss,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: const Icon(Icons.close_rounded, size: 18, color: _muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 拉取用量后按 dismiss 状态决定是否展示试用条
class TrialExpiryBannerHost extends StatefulWidget {
  const TrialExpiryBannerHost({
    super.key,
    this.margin = EdgeInsets.zero,
    this.refreshTick = 0,
  });

  final EdgeInsetsGeometry margin;
  final int refreshTick;

  @override
  State<TrialExpiryBannerHost> createState() => _TrialExpiryBannerHostState();
}

class _TrialExpiryBannerHostState extends State<TrialExpiryBannerHost> {
  final _repo = UsageRepository();
  TrialReminder? _reminder;

  @override
  void initState() {
    super.initState();
    UsageRefresh.version.addListener(_reload);
    _reload();
  }

  @override
  void didUpdateWidget(covariant TrialExpiryBannerHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshTick != oldWidget.refreshTick) {
      _reload();
    }
  }

  @override
  void dispose() {
    UsageRefresh.version.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final usage = await _repo.fetchUsage();
      final reminder = usage.trialReminder;
      if (reminder == null) {
        if (mounted) setState(() => _reminder = null);
        return;
      }
      final dismissed = await TrialExpiryBanner.isDismissed(reminder.endsAt);
      if (!mounted) return;
      setState(() => _reminder = dismissed ? null : reminder);
    } catch (_) {
      if (mounted) setState(() => _reminder = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reminder = _reminder;
    if (reminder == null) return const SizedBox.shrink();
    return TrialExpiryBanner(reminder: reminder, margin: widget.margin);
  }
}
