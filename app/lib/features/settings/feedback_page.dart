import 'package:flutter/material.dart';
import 'package:super_collection/core/theme/app_colors.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:super_collection/core/analytics/screen_dwell_tracker.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/features/settings/feedback_repository.dart';

/// 意见反馈：类型 + 正文 + 可选联系方式。
class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key});

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> with ScreenDwellMixin {
  static const _categories = [
    (id: 'feature', label: '功能建议'),
    (id: 'bug', label: '问题反馈'),
    (id: 'parse', label: '解析异常'),
    (id: 'other', label: '其他'),
  ];

  final _repo = FeedbackRepository();
  final _contentCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();

  String? _category;
  bool _busy = false;

  @override
  String get dwellScreen => AnalyticsScreens.feedback;

  @override
  void dispose() {
    _contentCtrl.dispose();
    _contactCtrl.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    final content = _contentCtrl.text.trim();
    return !_busy &&
        _category != null &&
        content.length >= 5 &&
        content.length <= 2000;
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    final category = _category!;
    final content = _contentCtrl.text.trim();
    final contact = _contactCtrl.text.trim();
    setState(() => _busy = true);
    try {
      String? appVersion;
      try {
        final info = await PackageInfo.fromPlatform();
        appVersion = info.version;
      } catch (_) {}

      final message = await _repo.submit(
        category: category,
        content: content,
        contact: contact.isEmpty ? null : contact,
        appVersion: appVersion,
      );
      if (!mounted) return;
      AppToast.show(context, message);
      Navigator.of(context).maybePop();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      AppToast.show(context, e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      AppToast.show(context, '提交失败，请稍后重试');
    }
  }

  InputDecoration _fieldDecoration(
    AppColors colors, {
    required String hintText,
    bool hideCounter = false,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(fontSize: 14, color: colors.placeholder),
      filled: true,
      fillColor: colors.card,
      counterText: hideCounter ? '' : null,
      contentPadding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.brand, width: 1.2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      backgroundColor: colors.pageBg,
      appBar: AppBar(
        centerTitle: true,
        leadingWidth: 80,
        leading: TextButton.icon(
          onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
          style: TextButton.styleFrom(
            foregroundColor: colors.ink,
            padding: const EdgeInsets.only(left: 8),
          ),
          icon: const Icon(Icons.chevron_left, size: 30),
          label: const Text('返回', style: TextStyle(fontSize: 15)),
        ),
        title: Text(
          '意见反馈',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: colors.ink,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                Text(
                  '告诉我们你的想法或遇到的问题，我们会认真看。',
                  style: TextStyle(fontSize: 14, color: colors.muted, height: 1.45),
                ),
                const SizedBox(height: 20),
                Text(
                  '反馈类型',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.ink,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in _categories)
                      _CategoryChip(
                        label: c.label,
                        selected: _category == c.id,
                        onTap: _busy
                            ? null
                            : () => setState(() => _category = c.id),
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                Text(
                  '反馈内容',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.ink,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _contentCtrl,
                  enabled: !_busy,
                  maxLines: 8,
                  minLines: 5,
                  maxLength: 2000,
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.45,
                    color: colors.ink,
                  ),
                  decoration: _fieldDecoration(
                    colors,
                    hintText: '请具体描述，方便我们定位与改进（至少 5 个字）',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '联系方式（选填）',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.ink,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _contactCtrl,
                  enabled: !_busy,
                  maxLength: 128,
                  keyboardType: TextInputType.emailAddress,
                  style: TextStyle(fontSize: 15, color: colors.ink),
                  decoration: _fieldDecoration(
                    colors,
                    hintText: '微信或邮箱，方便我们回复你',
                    hideCounter: true,
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _canSubmit ? _submit : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.brand,
                    disabledBackgroundColor: colors.brand.withValues(alpha: 0.35),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          '提交',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Material(
      color: selected ? colors.brandSoft : colors.inputBg,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? colors.brand : colors.hairline,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? colors.brand : colors.ink,
            ),
          ),
        ),
      ),
    );
  }
}
