import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// App 内触感（偏「多邻国」手感）。
///
/// iOS 走 AudioToolbox Taptic（1519/1520/1521），**不依赖**「设置 → 声音与触感 →
/// 系统触感反馈」；与 Flutter `HapticFeedback` / UIKit FeedbackGenerator 手感不同。
class AppHaptics {
  AppHaptics._();

  static const _channel = MethodChannel('super_collection/haptics');

  /// 轻点 / 切换选项（peek）
  static Future<void> tap() => _play('light');

  /// 选中方案卡等（pop）
  static Future<void> select() => _play('medium');

  static Future<void> _play(String style) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<void>('taptic', {'style': style});
    } catch (_) {
      // 非 iOS 或通道未就绪时回退系统 API（受「系统触感反馈」开关影响）
      if (style == 'medium') {
        await HapticFeedback.mediumImpact();
      } else {
        await HapticFeedback.selectionClick();
      }
    }
  }
}
