import 'package:flutter/material.dart';

/// 顶栏「✦ AI助手」：✦ 轻呼吸，不抢戏。
class AgentSparkLabel extends StatefulWidget {
  const AgentSparkLabel({
    super.key,
    this.fontSize = 13,
    this.fontWeight = FontWeight.w600,
  });

  final double fontSize;
  final FontWeight fontWeight;

  @override
  State<AgentSparkLabel> createState() => _AgentSparkLabelState();
}

class _AgentSparkLabelState extends State<AgentSparkLabel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _twinkle;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _twinkle = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = TextStyle(
      fontSize: widget.fontSize,
      fontWeight: widget.fontWeight,
      height: 1.1,
    );
    final sparkStyle = textStyle.copyWith(
      fontSize: widget.fontSize * 1.18,
      height: 1,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        AnimatedBuilder(
          animation: _twinkle,
          builder: (context, child) {
            final t = _twinkle.value;
            final opacity = 0.55 + 0.45 * t;
            final scale = 0.92 + 0.08 * t;
            return Opacity(
              opacity: opacity,
              child: Transform.scale(
                scale: scale,
                child: child,
              ),
            );
          },
          child: Text('✦', style: sparkStyle),
        ),
        Text(' AI助手', style: textStyle),
      ],
    );
  }
}
