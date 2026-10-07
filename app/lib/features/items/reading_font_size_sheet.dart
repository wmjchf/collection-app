import 'package:flutter/material.dart';
import 'package:super_collection/features/items/reading_font_prefs.dart';

/// 阅读页正文字号：A− / A+ 连续加减。
Future<void> showReadingFontSizeSheet(
  BuildContext context, {
  required double fontSize,
  required ValueChanged<double> onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x66000000),
    useSafeArea: false,
    isScrollControlled: true,
    builder: (context) => _ReadingFontSizeSheet(
      fontSize: fontSize,
      onChanged: onChanged,
    ),
  );
}

class _ReadingFontSizeSheet extends StatefulWidget {
  const _ReadingFontSizeSheet({
    required this.fontSize,
    required this.onChanged,
  });

  final double fontSize;
  final ValueChanged<double> onChanged;

  @override
  State<_ReadingFontSizeSheet> createState() => _ReadingFontSizeSheetState();
}

class _ReadingFontSizeSheetState extends State<_ReadingFontSizeSheet> {
  static const _text = Color(0xFF1F242E);
  static const _blue = Color(0xFF2F6FED);
  static const _handle = Color(0xFFD9DBE0);
  static const _chipBg = Color(0xFFF5F7FA);

  late double _size;

  @override
  void initState() {
    super.initState();
    _size = ReadingFontPrefs.clamp(widget.fontSize);
  }

  void _step(double delta) {
    final next = ReadingFontPrefs.clamp(_size + delta);
    if (next == _size) return;
    setState(() => _size = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final canDecrease = _size > ReadingFontPrefs.min;
    final canIncrease = _size < ReadingFontPrefs.max;

    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: _handle,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '文字大小',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _text,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _StepButton(
                      label: 'A−',
                      fontSize: 18,
                      enabled: canDecrease,
                      onTap: () => _step(-ReadingFontPrefs.step),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Container(
                      width: 56,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _chipBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_size.round()}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _blue,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: _StepButton(
                      label: 'A+',
                      fontSize: 22,
                      enabled: canIncrease,
                      onTap: () => _step(ReadingFontPrefs.step),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.label,
    required this.fontSize,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final double fontSize;
  final bool enabled;
  final VoidCallback onTap;

  static const _text = Color(0xFF1F242E);
  static const _chipBg = Color(0xFFF5F7FA);

  @override
  Widget build(BuildContext context) {
    final color = enabled ? _text : _text.withValues(alpha: 0.35);
    return Material(
      color: _chipBg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 48,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                color: color,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
