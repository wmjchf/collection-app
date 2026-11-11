import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 标签画布用户拖动位置：按 tag id 存相对主视口的归一化坐标。
/// 主视口内约为 0～1；拖到四周 pad 时可超出该范围。
class TagCanvasLayoutPrefs {
  TagCanvasLayoutPrefs._();

  static const _key = 'tag_canvas_norm_positions_v1';
  /// 相对主视口可超出的归一化范围（对应 world pad）。
  static const _minNorm = -2.0;
  static const _maxNorm = 3.0;

  static Future<Map<int, Offset>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final out = <int, Offset>{};
      for (final e in decoded.entries) {
        final id = int.tryParse(e.key.toString());
        if (id == null) continue;
        final parts = e.value.toString().split(',');
        if (parts.length != 2) continue;
        final x = double.tryParse(parts[0]);
        final y = double.tryParse(parts[1]);
        if (x == null || y == null) continue;
        out[id] = Offset(
          x.clamp(_minNorm, _maxNorm),
          y.clamp(_minNorm, _maxNorm),
        );
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  static Future<void> save(Map<int, Offset> positions) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = <String, String>{
        for (final e in positions.entries)
          '${e.key}':
              '${e.value.dx.clamp(_minNorm, _maxNorm)},${e.value.dy.clamp(_minNorm, _maxNorm)}',
      };
      await prefs.setString(_key, jsonEncode(encoded));
    } catch (_) {}
  }
}
