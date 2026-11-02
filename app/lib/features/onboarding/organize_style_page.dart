import 'package:flutter/material.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_form_width.dart';
import 'package:super_collection/core/ui/app_subpage_app_bar.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/features/collection/collection_tag_modules_section.dart';
import 'package:super_collection/features/onboarding/onboarding_survey_repository.dart';
import 'package:super_collection/features/onboarding/survey_catalog.dart';

typedef _QuizSet = ({
  String title,
  List<String> sampleTags,
  List<
      ({
        String id,
        List<({String name, List<String> tags})> shelves,
      })> options,
});

/// 归类习惯小测：按兴趣出题；UI 做成「对照三种归类」而非问卷单选卡。
class OrganizeStylePage extends StatefulWidget {
  const OrganizeStylePage({
    super.key,
    this.initialStyle,
    this.interestIds = const [],
    this.embedded = false,
    this.onSelected,
  });

  final String? initialStyle;
  final List<String> interestIds;
  final bool embedded;
  final ValueChanged<String>? onSelected;

  @override
  State<OrganizeStylePage> createState() => _OrganizeStylePageState();
}

class _OrganizeStylePageState extends State<OrganizeStylePage> {
  // 与问卷其它步一致的主题蓝
  static const _ink = Color(0xFF1F242E);
  static const _muted = Color(0xFF8B929C);
  static const _brand = Color(0xFF2F6FED);

  final _repo = OnboardingSurveyRepository();
  late List<_QuizSet> _quizSets;
  late List<String?> _answers;
  int _setIndex = 0;
  bool _busy = false;
  bool _loading = false;

  int get _setCount => _quizSets.length;

  bool get _quizDone =>
      _answers.length == _setCount &&
      _setCount > 0 &&
      _answers.every((e) => e != null);

  String? get _finalStyle => _quizDone
      ? SurveyCatalog.majorityOrganizeStyle(_answers.cast<String>())
      : null;

  @override
  void initState() {
    super.initState();
    _quizSets = SurveyCatalog.quizSetsForInterests(widget.interestIds);
    _answers = List<String?>.filled(_quizSets.length, null);
    if (!widget.embedded) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final status = await _repo.fetchStatus();
      if (!mounted) return;
      setState(() {
        if (widget.interestIds.isEmpty && status.interests.isNotEmpty) {
          _quizSets = SurveyCatalog.quizSetsForInterests(status.interests);
          _answers = List<String?>.filled(_quizSets.length, null);
          _setIndex = 0;
        }
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _pick(String id) {
    setState(() {
      _answers[_setIndex] = id;
      if (_setIndex < _setCount - 1 && _answers[_setIndex + 1] == null) {
        _setIndex += 1;
      }
    });
    final finalStyle = _finalStyle;
    if (finalStyle != null) widget.onSelected?.call(finalStyle);
  }

  void _goPrevSet() {
    if (_setIndex <= 0 || _busy) return;
    setState(() => _setIndex -= 1);
  }

  Future<void> _save() async {
    final style = _finalStyle;
    if (_busy || style == null) return;
    setState(() => _busy = true);
    try {
      await _repo.updateOrganizeStyle(style);
      if (!mounted) return;
      AppToast.show(context, '已更新归类习惯');
      Navigator.of(context).pop(style);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      AppToast.show(context, e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      AppToast.show(context, '保存失败，请稍后重试');
    }
  }

  Map<String, String> get _labelById => {
        for (final m in SurveyCatalog.organizeStyleMeta) m.id: m.label,
      };

  Map<String, String> get _blurbById => {
        for (final m in SurveyCatalog.organizeStyleMeta) m.id: m.blurb,
      };

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      const loading = Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.4, color: _brand),
        ),
      );
      if (widget.embedded) return loading;
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: _appBar(),
        body: loading,
      );
    }

    if (_quizSets.isEmpty) {
      const empty = Text('暂无可用题目', style: TextStyle(color: _muted));
      if (widget.embedded) return empty;
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: _appBar(),
        body: const Center(child: empty),
      );
    }

    final set = _quizSets[_setIndex];
    final currentPick = _answers[_setIndex];

    final content = <Widget>[
      if (!widget.embedded) ...[
        const Text(
          '对照三种归类',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: _ink,
            height: 1.25,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '题目来自你的兴趣。选出最接近你归类方式的一种，答完后按多数定习惯。',
          style: TextStyle(fontSize: 14, color: _muted, height: 1.45),
        ),
        const SizedBox(height: 20),
      ],
      _SetProgress(
        index: _setIndex,
        count: _setCount,
        title: set.title,
        onPrev: _setIndex > 0 && !_busy ? _goPrevSet : null,
      ),
      const SizedBox(height: 14),
      _TagTray(tags: set.sampleTags),
      const SizedBox(height: 18),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: Column(
          key: ValueKey('set-$_setIndex'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < set.options.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _ShelfOption(
                label: _labelById[set.options[i].id] ?? set.options[i].id,
                blurb: _blurbById[set.options[i].id] ?? '',
                shelves: set.options[i].shelves,
                selected: currentPick == set.options[i].id,
                onTap: _busy ? null : () => _pick(set.options[i].id),
              ),
            ],
          ],
        ),
      ),
      if (_quizDone) ...[
        const SizedBox(height: 16),
        _ResultNote(label: _labelById[_finalStyle] ?? _finalStyle ?? ''),
      ],
    ];

    final body = widget.embedded
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: content,
          )
        : ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            children: content,
          );

    if (widget.embedded) return body;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _appBar(),
      body: SafeArea(
        child: wrapAppFormWidth(
          child: Column(
            children: [
              Expanded(child: body),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: _busy || !_quizDone ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: _brand,
                      disabledBackgroundColor: _brand.withValues(alpha: 0.35),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
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
                            _quizDone ? '保存' : '答完 $_setCount 组后保存',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _appBar() {
    return const AppSubpageAppBar(title: '归类习惯');
  }
}

class _SetProgress extends StatelessWidget {
  const _SetProgress({
    required this.index,
    required this.count,
    required this.title,
    this.onPrev,
  });

  final int index;
  final int count;
  final String title;
  final VoidCallback? onPrev;

  static const _ink = Color(0xFF1F242E);
  static const _muted = Color(0xFF8B929C);
  static const _brand = Color(0xFF2F6FED);
  static const _track = Color(0xFFE6E8EB);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (var i = 0; i < count; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  height: 3,
                  decoration: BoxDecoration(
                    color: i <= index ? _brand : _track,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Text(
              '${index + 1} / $count',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _brand,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _ink,
                ),
              ),
            ),
            if (onPrev != null)
              GestureDetector(
                onTap: onPrev,
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                  child: Text(
                    '上一组',
                    style: TextStyle(fontSize: 12, color: _muted),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _TagTray extends StatelessWidget {
  const _TagTray({required this.tags});

  final List<String> tags;

  static String _hashLabel(String raw) {
    final n = raw.trim();
    if (n.isEmpty) return '';
    return n.startsWith('#') ? n : '#$n';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: CollectionTagModulesSection.brandSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: CollectionTagModulesSection.brand.withValues(alpha: 0.14),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '待归标签',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: CollectionTagModulesSection.brand,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in tags) _PreviewTagChip(label: _hashLabel(t)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ShelfOption extends StatelessWidget {
  const _ShelfOption({
    required this.label,
    required this.blurb,
    required this.shelves,
    required this.selected,
    this.onTap,
  });

  final String label;
  final String blurb;
  final List<({String name, List<String> tags})> shelves;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? CollectionTagModulesSection.brandSoft
          : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? CollectionTagModulesSection.brand.withValues(alpha: 0.45)
                  : CollectionTagModulesSection.hairline,
              width: selected ? 1.2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: selected
                                ? CollectionTagModulesSection.brand
                                : CollectionTagModulesSection.ink,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          blurb,
                          style: const TextStyle(
                            fontSize: 12,
                            color: CollectionTagModulesSection.muted,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 18,
                    height: 18,
                    margin: const EdgeInsets.only(top: 1),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected
                          ? CollectionTagModulesSection.brand
                          : Colors.transparent,
                      border: Border.all(
                        color: selected
                            ? CollectionTagModulesSection.brand
                            : const Color(0xFFC5CAD3),
                        width: 1.4,
                      ),
                    ),
                    child: selected
                        ? const Icon(Icons.check, size: 12, color: Colors.white)
                        : null,
                  ),
                ],
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: selected
                    ? Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Column(
                          children: [
                            for (var i = 0; i < shelves.length; i++) ...[
                              if (i > 0) const SizedBox(height: 10),
                              _CollectionLikeCase(
                                name: shelves[i].name,
                                tags: shelves[i].tags,
                              ),
                            ],
                          ],
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 对齐收藏页 `_ModuleBlock` 匣：白底细边 + 短装订条 + #chip
class _CollectionLikeCase extends StatelessWidget {
  const _CollectionLikeCase({
    required this.name,
    required this.tags,
  });

  final String name;
  final List<String> tags;

  static String _hashLabel(String raw) {
    final n = raw.trim();
    if (n.isEmpty) return '';
    return n.startsWith('#') ? n : '#$n';
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CollectionTagModulesSection.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CollectionTagModulesSection.caseLine),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 12,
              bottom: 12,
              width: 3,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: CollectionTagModulesSection.brand
                      .withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(15, 11, 10, 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                      height: 1.25,
                      color: CollectionTagModulesSection.ink
                          .withValues(alpha: 0.92),
                    ),
                  ),
                  const SizedBox(height: 11),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final t in tags) _PreviewTagChip(label: _hashLabel(t)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewTagChip extends StatelessWidget {
  const _PreviewTagChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 9, 6),
      decoration: BoxDecoration(
        color: CollectionTagModulesSection.chipFill,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 2,
            height: 12,
            decoration: BoxDecoration(
              color: CollectionTagModulesSection.brand.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.25,
              letterSpacing: 0.1,
              color: CollectionTagModulesSection.ink.withValues(alpha: 0.88),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultNote extends StatelessWidget {
  const _ResultNote({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: CollectionTagModulesSection.brandSoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '已答完 · 习惯倾向「$label」',
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: CollectionTagModulesSection.brand,
          height: 1.3,
        ),
      ),
    );
  }
}
