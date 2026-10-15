import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:super_collection/features/home/home_mock_data.dart';
import 'package:super_collection/features/items/cover_image.dart';

/// 首页条目叠卡（未读 / 最近阅读）：拖动前卡飞出、后卡顶上；左右循环。
class UnreadStackPreview extends StatefulWidget {
  const UnreadStackPreview({
    super.key,
    required this.items,
    required this.onTap,
  });

  final List<HomeItemPreview> items;
  final ValueChanged<HomeItemPreview> onTap;

  static const coverHeight = 200.0;
  static const peekStep = 14.0;
  static const sideStep = 14.0;
  static const metaHeight = 64.0;
  static const cardHeight = coverHeight + metaHeight;
  static const height = cardHeight + peekStep * 2;

  static const _text = Color(0xFF1F242E);
  static const _meta = Color(0xFF9AA0A8);

  @override
  State<UnreadStackPreview> createState() => _UnreadStackPreviewState();
}

class _UnreadStackPreviewState extends State<UnreadStackPreview>
    with SingleTickerProviderStateMixin {
  static const _dismissPx = 120.0;

  int _index = 0;
  double _dx = 0;
  bool _dragging = false;
  bool _settling = false;

  late final AnimationController _anim;
  double _animFrom = 0;
  double _animTo = 0;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this)
      ..addListener(() {
        final t = Curves.easeOutCubic.transform(_anim.value);
        setState(() => _dx = _animFrom + (_animTo - _animFrom) * t);
      });
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant UnreadStackPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final n = widget.items.length;
    if (n == 0) {
      _index = 0;
    } else if (_index >= n) {
      _index = 0;
    }
  }

  HomeItemPreview _at(int offset) {
    final n = widget.items.length;
    return widget.items[(_index + offset) % n];
  }

  double get _progress => (_dx.abs() / _dismissPx).clamp(0.0, 1.0);

  Future<void> _animateTo(
    double target, {
    required VoidCallback onDone,
    Duration duration = const Duration(milliseconds: 260),
  }) async {
    _settling = true;
    _animFrom = _dx;
    _animTo = target;
    _anim.duration = duration;
    await _anim.forward(from: 0);
    if (!mounted) return;
    _settling = false;
    onDone();
  }

  void _snapBack() {
    unawaited(_animateTo(
      0,
      duration: const Duration(milliseconds: 200),
      onDone: () {
        if (mounted) setState(() => _dx = 0);
      },
    ));
  }

  void _commitDismiss({required bool toLeft}) {
    final w = MediaQuery.sizeOf(context).width;
    final target = toLeft ? -(w + 100) : (w + 100);
    unawaited(_animateTo(
      target,
      onDone: () {
        if (!mounted) return;
        final n = widget.items.length;
        setState(() {
          _dx = 0;
          _index = toLeft ? (_index + 1) % n : (_index - 1 + n) % n;
        });
      },
    ));
  }

  void _onPanStart(DragStartDetails _) {
    if (_settling || widget.items.length < 2) return;
    _dragging = true;
    _anim.stop();
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (!_dragging || _settling) return;
    setState(() => _dx += d.delta.dx);
  }

  void _onPanEnd(DragEndDetails d) {
    if (!_dragging || _settling) return;
    _dragging = false;
    if (widget.items.length < 2) {
      _snapBack();
      return;
    }
    final v = d.velocity.pixelsPerSecond.dx;
    final shouldDismiss = _dx.abs() > _dismissPx * 0.42 || v.abs() > 650;
    if (!shouldDismiss) {
      _snapBack();
      return;
    }
    final toLeft = v.abs() > 400 ? v < 0 : _dx < 0;
    _commitDismiss(toLeft: toLeft);
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items.isEmpty) {
      return const SizedBox(height: UnreadStackPreview.height);
    }

    final n = items.length;
    final peekCount = (n - 1).clamp(0, 2);
    final p = _progress;
    final front = _at(0);
    final angle = (_dx / 320) * (math.pi / 28);

    // 后卡随进度顶上来：顶边、侧边、透明度、阴影
    final nextTop =
        UnreadStackPreview.peekStep * (1 - p);
    final nextSide =
        UnreadStackPreview.sideStep * (1 - p);
    final nextDim = 0.28 * (1 - p);
    final nextElev = 8.0 * p;

    final deepTop = UnreadStackPreview.peekStep +
        UnreadStackPreview.peekStep * (1 - p);
    final deepSide = UnreadStackPreview.sideStep +
        UnreadStackPreview.sideStep * (1 - p);
    final deepDim = 0.28 + 0.27 * (1 - p);

    return SizedBox(
      height: UnreadStackPreview.cardHeight +
          peekCount * UnreadStackPreview.peekStep,
      width: double.infinity,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (n >= 3)
            Positioned(
              top: deepTop,
              left: deepSide,
              right: deepSide,
              height: UnreadStackPreview.cardHeight,
              child: IgnorePointer(
                child: _StackCard(
                  item: _at(2),
                  dim: deepDim.clamp(0.28, 0.55),
                  showMeta: false,
                ),
              ),
            ),
          if (n >= 2)
            Positioned(
              top: nextTop,
              left: nextSide,
              right: nextSide,
              height: UnreadStackPreview.cardHeight,
              child: IgnorePointer(
                child: _StackCard(
                  item: _at(1),
                  dim: nextDim,
                  showMeta: p > 0.55,
                  elevation: nextElev,
                ),
              ),
            ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: UnreadStackPreview.cardHeight,
            child: GestureDetector(
              onTap: _dx.abs() < 8 && !_settling
                  ? () => widget.onTap(front)
                  : null,
              onPanStart: _onPanStart,
              onPanUpdate: _onPanUpdate,
              onPanEnd: _onPanEnd,
              child: Transform.translate(
                offset: Offset(_dx, -_dx.abs() * 0.04),
                child: Transform.rotate(
                  angle: angle,
                  child: _StackCard(
                    item: front,
                    dim: 0,
                    showMeta: true,
                    elevation: 10,
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

class _StackCard extends StatelessWidget {
  const _StackCard({
    required this.item,
    required this.dim,
    required this.showMeta,
    this.elevation = 0,
  });

  final HomeItemPreview item;
  final double dim;
  final bool showMeta;
  final double elevation;

  @override
  Widget build(BuildContext context) {
    final card = Material(
      color: Colors.white,
      elevation: elevation,
      shadowColor: const Color(0x33000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE6E8ED)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CoverImage(
            key: ValueKey('unread-stack-cover-${item.id}'),
            url: item.coverImageUrl,
            pageUrl: item.pageUrl,
            borderRadius: 0,
            width: double.infinity,
            height: UnreadStackPreview.coverHeight,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: showMeta
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            height: 1.25,
                            color: UnreadStackPreview._text,
                          ),
                        ),
                        if (item.subtitle.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            item.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              height: 1.2,
                              color: UnreadStackPreview._meta,
                            ),
                          ),
                        ],
                      ],
                    )
                  : const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );

    if (dim <= 0) return card;
    return Opacity(opacity: 1 - dim, child: card);
  }
}
