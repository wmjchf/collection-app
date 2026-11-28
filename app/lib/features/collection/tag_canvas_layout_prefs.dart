import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 标签画布：点位（按 tag id）+ 视口缩放/平移（按层 scope）。
/// 点位：相对主视口归一化坐标，约 0～1，拖到四周 pad 时可超出。
/// 视口：按面包屑层 `root` / 父标签 id 存 Matrix4（16 doubles）。
class TagCanvasLayoutPrefs {
  TagCanvasLayoutPrefs._();

  static const _key = 'tag_canvas_norm_positions_v1';
  static const _viewportKey = 'tag_canvas_viewport_v1';
  /// 相对主视口可超出的归一化范围（对应 world pad）。
  static const _minNorm = -2.0;
  static const _maxNorm = 3.0;
  static const _minScale = 0.18;
  static const _maxScale = 2.4;

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

  static Future<Matrix4?> loadViewport(String scope) async {
    final key = scope.trim().isEmpty ? 'root' : scope.trim();
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_viewportKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final entry = decoded[key];
      if (entry is! List || entry.length != 16) return null;
      final values = <double>[];
      for (final e in entry) {
        final v = e is num ? e.toDouble() : double.tryParse('$e');
        if (v == null || !v.isFinite) return null;
        values.add(v);
      }
      final m = Matrix4.fromList(values);
      final scale = m.getMaxScaleOnAxis();
      if (!scale.isFinite ||
          scale < _minScale * 0.5 ||
          scale > _maxScale * 1.5) {
        return null;
      }
      return m;
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveViewport(String scope, Matrix4 matrix) async {
    final key = scope.trim().isEmpty ? 'root' : scope.trim();
    try {
      final scale = matrix.getMaxScaleOnAxis();
      if (!scale.isFinite || scale <= 0) return;
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_viewportKey);
      Map<String, dynamic> map = {};
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          map = Map<String, dynamic>.from(decoded);
        }
      }
      map[key] = matrix.storage.toList(growable: false);
      await prefs.setString(_viewportKey, jsonEncode(map));
    } catch (_) {}
  }
}
