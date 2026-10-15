import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// App 触感反馈。
///
/// iOS 优先走原生 `UIImpactFeedbackGenerator`（MethodChannel），
/// 与是否自定义 Widget、响铃/静音开关无关；系统「触感反馈」关闭时仍无震。
class AppHaptics {
  AppHaptics._();

  static const _channel = MethodChannel('super_collection/haptics');

  /// 轻点卡片 / 切换选项
  static Future<void> tap() => impact('light');

  /// 稍重一点（确认、切换档位）
  static Future<void> select() => impact('medium');

  static Future<void> impact(String style) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<void>('impact', {'style': style});
    } catch (_) {
      // 通道未就绪时回退 Flutter 内置 API
      if (style == 'heavy') {
        await HapticFeedback.heavyImpact();
      } else if (style == 'medium') {
        await HapticFeedback.mediumImpact();
      } else {
        await HapticFeedback.lightImpact();
      }
    }
  }
}
