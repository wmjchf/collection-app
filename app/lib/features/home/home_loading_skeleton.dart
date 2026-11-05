import 'package:flutter/material.dart';

/// 首页首屏骨架：整库瀑布 / 未读+漫游。
class HomeLibraryLoadingSkeleton extends StatelessWidget {
  const HomeLibraryLoadingSkeleton({super.key});

  static const _soft = Color(0xFFEEF0F4);
  static const _bar = Color(0xFFE1E4EA);

  @override
  Widget build(BuildContext context) {
    return _Pulse(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                for (var i = 0; i < 4; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  _Pill(width: i == 0 ? 44 : 48, height: 28),
                ],
              ],
            ),
            const SizedBox(height: 14),
            const _Bone(width: 72, height: 12),
            const SizedBox(height: 14),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      children: const [
                        _CoverCard(flex: 5),
                        SizedBox(height: 4),
                        _CoverCard(flex: 4),
                        SizedBox(height: 4),
                        _CoverCard(flex: 3),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      children: const [
                        _CoverCard(flex: 4),
                        SizedBox(height: 4),
                        _CoverCard(flex: 5),
                        SizedBox(height: 4),
                        _CoverCard(flex: 3),
                      ],
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
}

class HomeUnreadRoamLoadingSkeleton extends StatelessWidget {
  const HomeUnreadRoamLoadingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final bottom = 12.0 + MediaQuery.paddingOf(context).bottom;
    return _Pulse(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                _Bone(width: 40, height: 14),
                Spacer(),
                _Bone(width: 56, height: 12),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE6E8ED)),
              ),
              child: const Column(
                children: [
                  _ListRow(),
                  SizedBox(height: 10),
                  _ListRow(),
                  SizedBox(height: 10),
                  _ListRow(),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Row(
              children: [
                _Bone(width: 40, height: 14),
                Spacer(),
                _Bone(width: 56, height: 12),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Stack(
                children: [
                  Positioned(
                    left: 10,
                    right: 10,
                    top: 14,
                    bottom: 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF0F4),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE6E8ED)),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 5,
                    right: 5,
                    top: 7,
                    bottom: 6,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8EBF0),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE6E8ED)),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    bottom: 12,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE6E8ED)),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: _Bone(width: 48, height: 10),
                          ),
                          SizedBox(height: 14),
                          _Bone(width: null, height: 12),
                          SizedBox(height: 8),
                          _Bone(width: null, height: 12),
                          SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: _Bone(width: 160, height: 12),
                          ),
                        ],
                      ),
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
}

class _Pulse extends StatefulWidget {
  const _Pulse({required this.child});

  final Widget child;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_c.value);
        return Opacity(opacity: 0.55 + 0.45 * t, child: child);
      },
      child: widget.child,
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: HomeLibraryLoadingSkeleton._soft,
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }
}

class _Bone extends StatelessWidget {
  const _Bone({required this.width, required this.height});

  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: HomeLibraryLoadingSkeleton._bar,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

class _CoverCard extends StatelessWidget {
  const _CoverCard({required this.flex});

  final int flex;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFE6E8ED)),
        ),
        padding: const EdgeInsets.all(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: HomeLibraryLoadingSkeleton._soft,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const _Bone(width: null, height: 10),
            const SizedBox(height: 6),
            const Align(
              alignment: Alignment.centerLeft,
              child: _Bone(width: 64, height: 8),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListRow extends StatelessWidget {
  const _ListRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        SizedBox(
          width: 48,
          height: 48,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: HomeLibraryLoadingSkeleton._soft,
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Bone(width: null, height: 12),
              SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: _Bone(width: 96, height: 10),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
