import 'package:flutter/material.dart';
import 'package:super_collection/core/analytics/analytics.dart';
import 'package:super_collection/core/config/app_brand.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/features/onboarding/onboarding_flow.dart';
import 'package:super_collection/features/onboarding/onboarding_survey_repository.dart';
import 'package:super_collection/features/onboarding/survey_catalog.dart';
import 'package:super_collection/features/onboarding/survey_prefs.dart';

/// 首次问卷：年龄 / 来源 / 兴趣类（可跳过）
class FirstSurveyPage extends StatefulWidget {
  const FirstSurveyPage({super.key, required this.userId});

  final int userId;

  @override
  State<FirstSurveyPage> createState() => _FirstSurveyPageState();
}

class _FirstSurveyPageState extends State<FirstSurveyPage> {
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _blue = Color(0xFF2F6FED);

  final _repo = OnboardingSurveyRepository();

  String? _ageRange;
  String? _source;
  final Set<String> _interests = {};
  bool _busy = false;

  bool get _canSubmit =>
      _ageRange != null && _source != null && _interests.isNotEmpty;

  Future<void> _finishAndContinue({required bool skipped}) async {
    await SurveyPrefs.markDone(userId: widget.userId);
    if (!mounted) return;
    final next = await nextAfterSurvey(userId: widget.userId);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => next),
    );
  }

  Future<void> _onSkip() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _repo.skip();
      Analytics.instance.surveySkip();
      await _finishAndContinue(skipped: true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      AppToast.show(context, e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      AppToast.show(context, '请稍后重试');
    }
  }

  Future<void> _onSubmit() async {
    if (_busy || !_canSubmit) return;
    final age = _ageRange!;
    final source = _source!;
    final interests = _interests.toList();
    setState(() => _busy = true);
    try {
      await _repo.submit(
        ageRange: age,
        source: source,
        interests: interests,
      );
      Analytics.instance.surveySubmit(
        source: source,
        interestCount: interests.length,
      );
      await _finishAndContinue(skipped: false);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                children: [
                  const Text(
                    AppBrand.name,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: _text,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '先了解一下你，方便预置更贴合的标签分类',
                    style: TextStyle(
                      fontSize: 15,
                      color: _muted,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 28),
                  _sectionTitle('你的年龄段'),
                  const SizedBox(height: 10),
                  _wrapChips(
                    children: [
                      for (final age in SurveyCatalog.ageRanges)
                        _ChoiceChip(
                          label: age,
                          selected: _ageRange == age,
                          onTap: _busy
                              ? null
                              : () => setState(() => _ageRange = age),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _sectionTitle('你从哪里看到我们的产品？'),
                  const SizedBox(height: 10),
                  _wrapChips(
                    children: [
                      for (final s in SurveyCatalog.sources)
                        _ChoiceChip(
                          label: s.label,
                          selected: _source == s.id,
                          onTap: _busy
                              ? null
                              : () => setState(() => _source = s.id),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _sectionTitle('感兴趣的内容方向（可多选）'),
                  const SizedBox(height: 4),
                  const Text(
                    '只选类别；确认后会预置对应归类与标签',
                    style: TextStyle(fontSize: 12, color: _muted),
                  ),
                  const SizedBox(height: 10),
                  _wrapChips(
                    children: [
                      for (final c in SurveyCatalog.interests)
                        _ChoiceChip(
                          label: c.name,
                          selected: _interests.contains(c.id),
                          onTap: _busy
                              ? null
                              : () => setState(() {
                                    if (_interests.contains(c.id)) {
                                      _interests.remove(c.id);
                                    } else {
                                      _interests.add(c.id);
                                    }
                                  }),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: _busy || !_canSubmit ? null : _onSubmit,
                      style: FilledButton.styleFrom(
                        backgroundColor: _blue,
                        disabledBackgroundColor:
                            _blue.withValues(alpha: 0.35),
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
                              '继续',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _busy ? null : _onSkip,
                    child: const Text(
                      '跳过',
                      style: TextStyle(fontSize: 14, color: _muted),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: _text,
      ),
    );
  }

  Widget _wrapChips({required List<Widget> children}) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: children,
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.selected,
    this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  static const _text = Color(0xFF1F242E);
  static const _blue = Color(0xFF2F6FED);
  static const _chipBg = Color(0xFFF5F7FA);
  static const _chipBorder = Color(0xFFE6E8EB);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFE8F0FF) : _chipBg,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? _blue : _chipBorder,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? _blue : _text,
            ),
          ),
        ),
      ),
    );
  }
}
