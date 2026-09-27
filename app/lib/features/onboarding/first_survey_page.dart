import 'package:flutter/material.dart';
import 'package:super_collection/core/analytics/analytics.dart';
import 'package:super_collection/core/config/app_brand.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/features/onboarding/onboarding_flow.dart';
import 'package:super_collection/features/onboarding/onboarding_survey_repository.dart';
import 'package:super_collection/features/onboarding/survey_catalog.dart';
import 'package:super_collection/features/onboarding/survey_prefs.dart';

/// 首次问卷：三页各一题（年龄 / 来源 / 兴趣类），可跳过
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
  static const _stepCount = 3;

  final _repo = OnboardingSurveyRepository();
  final _pageController = PageController();

  int _step = 0;
  String? _ageRange;
  String? _source;
  final Set<String> _interests = {};
  bool _busy = false;

  bool get _canAdvance {
    switch (_step) {
      case 0:
        return _ageRange != null;
      case 1:
        return _source != null;
      case 2:
        return _interests.isNotEmpty;
      default:
        return false;
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finishAndContinue() async {
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
      await _finishAndContinue();
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

  Future<void> _onPrimary() async {
    if (_busy || !_canAdvance) return;
    if (_step < _stepCount - 1) {
      await _pageController.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
      return;
    }

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
      await _finishAndContinue();
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

  void _goBack() {
    if (_busy || _step == 0) return;
    _pageController.previousPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
              child: Row(
                children: [
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: _step > 0
                        ? IconButton(
                            onPressed: _busy ? null : _goBack,
                            icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                            color: _text,
                          )
                        : null,
                  ),
                  Expanded(child: _StepDots(step: _step, count: _stepCount)),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _step = i),
                children: [
                  _SurveyStep(
                    brand: AppBrand.name,
                    subtitle: '先了解一下你，方便预置更贴合的标签分类',
                    title: '你的年龄段',
                    child: _wrapChips(
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
                  ),
                  _SurveyStep(
                    title: '你从哪里看到我们的产品？',
                    child: _wrapChips(
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
                  ),
                  _SurveyStep(
                    title: '感兴趣的内容方向（可多选）',
                    hint: '只选类别；确认后会预置对应归类与标签',
                    child: _wrapChips(
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
                      onPressed: _busy || !_canAdvance ? null : _onPrimary,
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
                          : Text(
                              _step == _stepCount - 1 ? '继续' : '下一步',
                              style: const TextStyle(
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

  Widget _wrapChips({required List<Widget> children}) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: children,
    );
  }
}

class _StepDots extends StatelessWidget {
  const _StepDots({required this.step, required this.count});

  final int step;
  final int count;

  static const _blue = Color(0xFF2F6FED);
  static const _idle = Color(0xFFE6E8EB);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: i == step ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i <= step ? _blue : _idle,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ],
      ],
    );
  }
}

class _SurveyStep extends StatelessWidget {
  const _SurveyStep({
    required this.title,
    required this.child,
    this.brand,
    this.subtitle,
    this.hint,
  });

  final String? brand;
  final String? subtitle;
  final String title;
  final String? hint;
  final Widget child;

  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      children: [
        if (brand != null) ...[
          Text(
            brand!,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: _text,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              style: const TextStyle(
                fontSize: 15,
                color: _muted,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 28),
        ] else
          const SizedBox(height: 12),
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: _text,
            height: 1.3,
          ),
        ),
        if (hint != null) ...[
          const SizedBox(height: 6),
          Text(
            hint!,
            style: const TextStyle(fontSize: 13, color: _muted, height: 1.35),
          ),
        ],
        const SizedBox(height: 16),
        child,
      ],
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
