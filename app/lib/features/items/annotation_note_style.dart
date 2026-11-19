import 'package:flutter/material.dart';
import 'package:super_collection/features/items/item_models.dart';

/// 正文批注 / 高亮视觉（对齐阅读页参考稿）。
abstract final class AnnotationNoteStyle {
  static const blue = Color(0xFF2F6FED);
  static const text = Color(0xFF1F242E);
  /// 纯高亮底色（浅蓝，圆角由 Stack 按行盒绘制）
  static const highlight = Color(0xFFD6E4FF);

  static bool hasNote(ItemAnnotation ann) =>
      (ann.note ?? '').trim().isNotEmpty;

  static bool isHighlightOnly(ItemAnnotation ann) => !hasNote(ann);

  /// 按测量到的文字盒画圆角高亮底。
  static Widget highlightChip(Rect rect) {
    const padX = 1.5;
    return Positioned(
      left: rect.left - padX,
      top: rect.top,
      width: rect.width + padX * 2,
      height: rect.height,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: highlight,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }

  /// 按正文出现顺序编号（1-based），仅含有笔记正文的标注。
  static Map<int, int> noteIndexById(
    Iterable<({int start, int end, ItemAnnotation ann})> ranges,
  ) {
    final withNotes = [
      for (final r in ranges)
        if (hasNote(r.ann)) r,
    ]..sort((a, b) {
        final c = a.start.compareTo(b.start);
        return c != 0 ? c : a.ann.id.compareTo(b.ann.id);
      });
    final map = <int, int>{};
    for (var i = 0; i < withNotes.length; i++) {
      map[withNotes[i].ann.id] = i + 1;
    }
    return map;
  }

  static TextStyle underlineStyle({Color color = text}) => TextStyle(
        color: color,
        decoration: TextDecoration.underline,
        decorationStyle: TextDecorationStyle.dotted,
        decorationColor: blue,
        decorationThickness: 1.6,
      );
}

/// 批注角标：蓝色圆底白字序号。
class AnnotationNoteBadge extends StatelessWidget {
  const AnnotationNoteBadge({super.key, required this.index});

  final int index;

  static const double size = 14;

  @override
  Widget build(BuildContext context) {
    final label = index > 99 ? '99+' : '$index';
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AnnotationNoteStyle.blue,
        shape: BoxShape.circle,
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: index > 9 ? 8 : 9,
          fontWeight: FontWeight.w700,
          height: 1,
          letterSpacing: -0.2,
        ),
      ),
    );
  }
}
