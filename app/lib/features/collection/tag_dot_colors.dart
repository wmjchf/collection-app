import 'package:flutter/material.dart';

/// 标签色点：由名称哈希稳定取色，与归类无关。色板偏低饱和，收藏馆气质。
abstract final class TagDotColors {
  static const palette = <Color>[
    Color(0xFF5B7FB8),
    Color(0xFF5A9A90),
    Color(0xFF7A86B8),
    Color(0xFF6A98A8),
    Color(0xFF8A7EAE),
    Color(0xFF5E8A96),
    Color(0xFF7D9474),
    Color(0xFFB49A78),
    Color(0xFFB88490),
    Color(0xFF6A8F7A),
    Color(0xFFA89068),
    Color(0xFF6E8FA8),
  ];

  static Color forName(String name) {
    final s = name.trim();
    var hash = 0;
    for (final c in s.codeUnits) {
      hash = 0x1fffffff & (hash * 31 + c);
    }
    if (hash < 0) hash = -hash;
    return palette[hash % palette.length];
  }
}
