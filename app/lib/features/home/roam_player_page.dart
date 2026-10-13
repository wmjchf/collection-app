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
  bool get _done => _index >= _snips.length;

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
    if (_done) return;
    setState(() => _index += 1);
    if (!_done || _recorded) return;
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
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).maybePop(),
              child: const ColoredBox(color: kAppBottomSheetBarrierColor),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            top: pad.top + 12,
            bottom: pad.bottom + 12,
            child: GestureDetector(
              onTap: () {},
              child: _done
                  ? Material(
                      color: const Color(0xFFFFF4EA),
                      elevation: 12,
                      shadowColor: const Color(0x33000000),
                      borderRadius: BorderRadius.circular(24),
                      clipBehavior: Clip.antiAlias,
                      child: _RoamDonePage(
                        finished: _snips.length,
                        uniqueCount: _uniqueCount,
                        sessionCount: _sessionCount,
                        lastSnippet: _snips.isEmpty ? null : _snips.last,
                        onFinish: () => Navigator.of(context).maybePop(),
                        onContinue: _continue,
                      ),
                    )
                  : Column(
                      children: [
                        Expanded(
                          child: _RoamSwipeDeck(
                            snippets: _snips,
                            index: _index,
                            onDismissed: () => unawaited(_advance()),
                            onOpen: (s) => unawaited(_openSource(s)),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          '${_index + 1} / ${_snips.length}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '左右滑过',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.72),
                          ),
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

class _RoamSwipeDeck extends StatelessWidget {
  const _RoamSwipeDeck({
    required this.snippets,
    required this.index,
    required this.onDismissed,
    required this.onOpen,
  });

  final List<RoamSnippet> snippets;
  final int index;
  final VoidCallback onDismissed;
  final ValueChanged<RoamSnippet> onOpen;

  @override
  Widget build(BuildContext context) {
    final remaining = snippets.length - index;
    if (remaining <= 0) return const SizedBox.shrink();

    Widget layer({
      required int depth,
      required Widget child,
    }) {
      return Positioned(
        left: 16.0 * depth,
        right: 16.0 * depth,
        top: 14.0 * depth,
        bottom: 18.0 - 6.0 * depth,
        child: child,
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        layer(
          depth: 2,
          child: remaining > 2
              ? IgnorePointer(
                  child: RoamQuoteCard(
                    snippet: snippets[index + 2],
                    maxLines: 8,
                    showMeta: false,
                    elevation: 2,
                  ),
                )
              : const _DeckBackplate(elevation: 2),
        ),
        layer(
          depth: 1,
          child: remaining > 1
              ? IgnorePointer(
                  child: RoamQuoteCard(
                    snippet: snippets[index + 1],
                    maxLines: 8,
                    showMeta: false,
                    elevation: 6,
                  ),
                )
              : const _DeckBackplate(elevation: 6),
        ),
        layer(
          depth: 0,
          child: _SwipeCard(
            key: ValueKey(snippets[index].id),
            onTap: () => onOpen(snippets[index]),
            onDismissed: onDismissed,
            child: RoamQuoteCard(
              snippet: snippets[index],
              maxLines: 12,
              elevation: 14,
            ),
          ),
        ),
      ],
    );
  }
}

class _DeckBackplate extends StatelessWidget {
  const _DeckBackplate({required this.elevation});

  final double elevation;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: elevation,
      shadowColor: const Color(0x33000000),
      borderRadius: BorderRadius.circular(16),
    );
  }
}

class _SwipeCard extends StatefulWidget {
  const _SwipeCard({
    super.key,
    required this.child,
    required this.onDismissed,
    this.onTap,
  });

  final Widget child;
  final VoidCallback onDismissed;
  final VoidCallback? onTap;

  @override
  State<_SwipeCard> createState() => _SwipeCardState();
}

class _SwipeCardState extends State<_SwipeCard>
    with SingleTickerProviderStateMixin {
  Offset _offset = Offset.zero;
  late final AnimationController _fly;
  Offset _flyTo = Offset.zero;
  bool _settling = false;

  @override
  void initState() {
    super.initState();
    _fly = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() {
        setState(() {
          _offset = Offset.lerp(Offset.zero, _flyTo, _fly.value)!;
        });
      });
  }

  @override
  void dispose() {
    _fly.dispose();
    super.dispose();
  }

  double get _angle => (_offset.dx / 420) * 0.28;

  void _onPanUpdate(DragUpdateDetails d) {
    if (_settling) return;
    setState(() => _offset += d.delta);
  }

  void _onPanEnd(DragEndDetails d) {
    if (_settling) return;
    final w = MediaQuery.sizeOf(context).width;
    final vx = d.velocity.pixelsPerSecond.dx;
    final pass = _offset.dx.abs() > w * 0.22 || vx.abs() > 900;
    if (!pass) {
      setState(() => _offset = Offset.zero);
      return;
    }
    final dir = (_offset.dx == 0 ? vx : _offset.dx) >= 0 ? 1.0 : -1.0;
    _settling = true;
    _flyTo = Offset(dir * (w + 80), _offset.dy * 0.4);
    _fly.forward(from: 0).whenComplete(() {
      if (mounted) widget.onDismissed();
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _offset.distance < 8 ? widget.onTap : null,
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

class _RoamDonePage extends StatelessWidget {
  const _RoamDonePage({
    required this.finished,
    required this.uniqueCount,
    required this.sessionCount,
    this.lastSnippet,
    required this.onFinish,
    required this.onContinue,
  });

  final int finished;
  final int uniqueCount;
  final int sessionCount;
  final RoamSnippet? lastSnippet;
  final VoidCallback onFinish;
  final VoidCallback onContinue;

  static const _text = Color(0xFF3D2C22);
  static const _muted = Color(0xFF8A7464);

  @override
  Widget build(BuildContext context) {
    return Container(
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
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
      child: Column(
        children: [
          const Spacer(flex: 3),
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
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: _text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '已累计漫游 $uniqueCount 条，共 $sessionCount 次',
            style: const TextStyle(fontSize: 14, color: _muted),
          ),
          if (lastSnippet != null) ...[
            const SizedBox(height: 28),
            IgnorePointer(
              child: RoamQuoteCard(
                snippet: lastSnippet!,
                maxLines: 5,
                showMeta: false,
              ),
            ),
          ],
          const Spacer(flex: 2),
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
                side: const BorderSide(color: Color(0x33FFFFFF)),
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
    );
  }
}
