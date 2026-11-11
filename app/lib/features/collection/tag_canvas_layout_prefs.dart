import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 标签画布用户拖动位置：按 tag id 存归一化坐标（0～1）。
class TagCanvasLayoutPrefs {
  TagCanvasLayoutPrefs._();

  static const _key = 'tag_canvas_norm_positions_v1';

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
        out[id] = Offset(x.clamp(0.0, 1.0), y.clamp(0.0, 1.0));
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
              '${e.value.dx.clamp(0.0, 1.0)},${e.value.dy.clamp(0.0, 1.0)}',
      };
      await prefs.setString(_key, jsonEncode(encoded));
    } catch (_) {}
  }
}
