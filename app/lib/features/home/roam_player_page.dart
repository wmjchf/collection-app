import 'dart:async';

import 'package:flutter/material.dart';
import 'package:super_collection/core/analytics/screen_dwell_tracker.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_bottom_sheet.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/features/home/roam_models.dart';
import 'package:super_collection/features/home/roam_stats.dart';
import 'package:super_collection/features/home/widgets/roam_quote_card.dart';
import 'package:super_collection/features/items/item_reading_page.dart';
import 'package:super_collection/features/items/items_repository.dart';

Future<void> showRoamPlayer(
  BuildContext context, {
  required List<RoamSnippet> snippets,
}) {
  if (snippets.isEmpty) return Future.value();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭漫游',
    barrierColor: Colors.transparent,
    pageBuilder: (ctx, _, _) => RoamPlayerPage(snippets: snippets),
    transitionBuilder: (ctx, animation, _, child) {
      return FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.04),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          )),
          child: child,
        ),
      );
    },
  );
}

class RoamPlayerPage extends StatefulWidget {
  const RoamPlayerPage({super.key, required this.snippets});

  final List<RoamSnippet> snippets;

  @override
  State<RoamPlayerPage> createState() => _RoamPlayerPageState();
}

class _RoamPlayerPageState extends State<RoamPlayerPage>
    with ScreenDwellMixin {
  final _items = ItemsRepository();
  int _index = 0;
  bool _recorded = false;
  int _uniqueCount = 0;
  int _sessionCount = 0;

  List<RoamSnippet> get _snips => widget.snippets;

  /// 摘录 + 最后一张「继续漫游」
  int get _deckLength => _snips.length + 1;

  bool get _onDoneCard => _index >= _snips.length;

  @override
  String get dwellScreen => AnalyticsScreens.roamPlayer;

  @override
  void initState() {
    super.initState();
    unawaited(_loadStats());
  }

  Future<void> _loadStats() async {
    final snap = await RoamStats.snapshot();
    if (!mounted) return;
    setState(() {
      _uniqueCount = snap.uniqueCount;
      _sessionCount = snap.sessionCount;
    });
  }

  Future<void> _advance() async {
    if (_index >= _deckLength - 1) return;
    setState(() => _index += 1);
    if (!_onDoneCard || _recorded) return;
    _recorded = true;
    final snap = await RoamStats.recordSession(_snips.map((e) => e.id));
    if (!mounted) return;
    setState(() {
      _uniqueCount = snap.uniqueCount;
      _sessionCount = snap.sessionCount;
    });
  }

  Future<void> _openSource(RoamSnippet snippet) async {
    try {
      final item = await _items.getItem(snippet.itemId);
      if (!mounted) return;
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => ItemReadingPage(
            itemId: item.id,
            initialItem: item,
            openEntry: 'roam',
            focusAnnotationId: snippet.annotationId,
            openNoteOnLaunch: snippet.isThought,
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      AppToast.show(context, e.message);
    } catch (_) {
      if (!mounted) return;
      AppToast.show(context, '打开失败');
    }
  }

  void _continue() {
    setState(() {
      _index = 0;
      _recorded = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.expand,
        // 溢出由屏幕裁切，不在弹层内容盒内裁切
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).maybePop(),
              child: const ColoredBox(color: kAppBottomSheetBarrierColor),
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                pad.top + 28,
                20,
                pad.bottom + 28,
              ),
              child: _RoamSwipeDeck(
                snippets: _snips,
                index: _index,
                uniqueCount: _uniqueCount,
                sessionCount: _sessionCount,
                onDismissed: () => unawaited(_advance()),
                onOpen: (s) => unawaited(_openSource(s)),
                onFinish: () => Navigator.of(context).maybePop(),
                onContinue: _continue,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoamSwipeDeck extends StatefulWidget {
  const _RoamSwipeDeck({
    required this.snippets,
    required this.index,
    required this.uniqueCount,
    required this.sessionCount,
    required this.onDismissed,
    required this.onOpen,
    required this.onFinish,
    required this.onContinue,
  });

  final List<RoamSnippet> snippets;
  final int index;
  final int uniqueCount;
  final int sessionCount;
  final VoidCallback onDismissed;
  final ValueChanged<RoamSnippet> onOpen;
  final VoidCallback onFinish;
  final VoidCallback onContinue;

  @override
  State<_RoamSwipeDeck> createState() => _RoamSwipeDeckState();
}

class _RoamSwipeDeckState extends State<_RoamSwipeDeck> {
  double _progress = 0;

  int get _deckLength => widget.snippets.length + 1;

  @override
  void didUpdateWidget(_RoamSwipeDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      _progress = 0;
    }
  }

  Widget _cardAt(int absoluteIndex, {required double elevation, Color? color}) {
    final snips = widget.snippets;
    if (absoluteIndex < snips.length) {
      return RoamQuoteCard(
        snippet: snips[absoluteIndex],
        maxLines: 12,
        showMeta: true,
        elevation: elevation,
        color: color ?? Colors.white,
      );
    }
    return _RoamDoneCard(
      finished: snips.length,
      uniqueCount: widget.uniqueCount,
      sessionCount: widget.sessionCount,
      onFinish: widget.onFinish,
      onContinue: widget.onContinue,
    );
  }

  @override
  Widget build(BuildContext context) {
    final index = widget.index;
    final remaining = _deckLength - index;
    if (remaining <= 0) return const SizedBox.shrink();
    final p = _progress.clamp(0.0, 1.0);
    final onDone = index >= widget.snippets.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        // 卡宽始终 = fullW，只用 Transform.scale 做层级感，避免改 inset 导致换行跳动
        const peekStep = 10.0;
        const sideStep = 12.0;
        final hasNext = remaining > 1;
        // 始终预留顶边，最后一张也不改 frontH，避免高度跳导致行数变
        const topReserve = peekStep;
        final frontH =
            (constraints.maxHeight - topReserve - 8).clamp(200.0, 10000.0);
        final fullW = constraints.maxWidth;
        final nextScale = hasNext ? (0.94 + 0.06 * p) : 1.0;

        final front = SizedBox(
          width: fullW,
          height: frontH,
          child: _cardAt(index, elevation: 12),
        );

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // 完成卡也保留顶边空壳，避免滑到最后一张时层级突然消失
            Positioned(
              left: sideStep,
              right: sideStep,
              top: 0,
              height: frontH,
              child: const IgnorePointer(
                child: Material(
                  color: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(16)),
                    side: BorderSide(color: Color(0xFFE6E8ED)),
                  ),
                ),
              ),
            ),
            if (hasNext)
              Positioned(
                left: 0,
                right: 0,
                top: topReserve,
                height: frontH,
                child: IgnorePointer(
                  child: Transform.scale(
                    scale: nextScale,
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: fullW,
                      height: frontH,
                      child: _cardAt(index + 1, elevation: 0),
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              top: topReserve,
              height: frontH,
              child: onDone
                  ? front
                  : _SwipeCard(
                      key: ValueKey('roam-$index'),
                      onTap: () => widget.onOpen(widget.snippets[index]),
                      onProgress: (value) {
                        if (_progress == value) return;
                        setState(() => _progress = value);
                      },
                      onDismissed: widget.onDismissed,
                      child: front,
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _SwipeCard extends StatefulWidget {
  const _SwipeCard({
    super.key,
    required this.child,
    required this.onDismissed,
    required this.onProgress,
    this.onTap,
  });

  final Widget child;
  final VoidCallback onDismissed;
  final ValueChanged<double> onProgress;
  final VoidCallback? onTap;

  @override
  State<_SwipeCard> createState() => _SwipeCardState();
}

class _SwipeCardState extends State<_SwipeCard>
    with SingleTickerProviderStateMixin {
  Offset _offset = Offset.zero;
  late final AnimationController _anim;
  Offset _from = Offset.zero;
  Offset _to = Offset.zero;
  bool _settling = false;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(_onAnim);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  double get _angle => (_offset.dx / 420) * 0.28;

  double _progressFor(Offset offset) {
    final w = MediaQuery.sizeOf(context).width;
    return (offset.dx.abs() / (w * 0.42)).clamp(0.0, 1.0);
  }

  void _emit() => widget.onProgress(_progressFor(_offset));

  void _onAnim() {
    setState(() {
      _offset = Offset.lerp(_from, _to, _anim.value)!;
    });
    _emit();
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_settling) return;
    setState(() => _offset += d.delta);
    _emit();
  }

  void _onPanEnd(DragEndDetails d) {
    if (_settling) return;
    final w = MediaQuery.sizeOf(context).width;
    final vx = d.velocity.pixelsPerSecond.dx;
    final pass = _offset.dx.abs() > w * 0.22 || vx.abs() > 900;
    _settling = true;
    _from = _offset;
    if (!pass) {
      _to = Offset.zero;
      _anim.duration = const Duration(milliseconds: 200);
      _anim.forward(from: 0).whenComplete(() {
        if (!mounted) return;
        _settling = false;
        _emit();
      });
      return;
    }
    final dir = (_offset.dx == 0 ? vx : _offset.dx) >= 0 ? 1.0 : -1.0;
    _to = Offset(dir * (w + 80), _offset.dy * 0.4);
    _anim.duration = const Duration(milliseconds: 220);
    _anim.forward(from: 0).whenComplete(() {
      if (mounted) widget.onDismissed();
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _offset.distance < 8 && !_settling ? widget.onTap : null,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      child: Transform.translate(
        offset: _offset,
        child: Transform.rotate(
          angle: _angle,
          child: widget.child,
        ),
      ),
    );
  }
}

class _RoamDoneCard extends StatelessWidget {
  const _RoamDoneCard({
    required this.finished,
    required this.uniqueCount,
    required this.sessionCount,
    required this.onFinish,
    required this.onContinue,
  });

  final int finished;
  final int uniqueCount;
  final int sessionCount;
  final VoidCallback onFinish;
  final VoidCallback onContinue;

  static const _text = Color(0xFF3D2C22);
  static const _muted = Color(0xFF8A7464);

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 10,
      shadowColor: const Color(0x33000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE6E8ED)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFFE4CF),
              Color(0xFFFFF4EA),
              Color(0xFFFFFBF7),
            ],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(22, 28, 22, 20),
        child: Column(
          children: [
            const Spacer(flex: 2),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.7),
              ),
              child: const Icon(
                Icons.check_rounded,
                size: 30,
                color: Color(0xFFE8A25A),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '已完成 $finished 条摘录',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: _text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '已累计漫游 $uniqueCount 条，共 $sessionCount 次',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: _muted),
            ),
            const Spacer(flex: 3),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: onFinish,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(26),
                  ),
                ),
                child: const Text(
                  '完成漫游',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton(
                onPressed: onContinue,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _text,
                  side: BorderSide(
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                  backgroundColor: Colors.white.withValues(alpha: 0.72),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(26),
                  ),
                ),
                child: const Text(
                  '继续漫游',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
