import 'dart:async';

import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/parse_progress_controller.dart';
import 'package:super_collection/features/items/items_repository.dart';

/// 创建后展示底栏上方不确定进度条，并轮询解析状态。
class ParseProgressTracker {
  ParseProgressTracker._();

  static Timer? _timer;
  static final _items = ItemsRepository();
  static final _progress = ParseProgressController.instance;

  static Future<void> Function()? _onSettled;

  /// 一点击就显示底栏上方进度条（不等待 create 返回）。
  static void begin({
    String title = '正在解析内容',
    String subtitle = '拉取标题、封面与正文…',
  }) {
    _timer?.cancel();
    _progress.start(title: title, subtitle: subtitle);
  }

  static Future<void> watchItem(
    int itemId, {
    String? initialStatus,
    Future<void> Function()? onSettled,
  }) async {
    _timer?.cancel();
    _onSettled = onSettled;
    _progress.start(itemId: itemId);

    final status = (initialStatus ?? 'pending').toLowerCase();
    if (status == 'success') {
      await _finishSuccess();
      return;
    }
    if (status == 'failed') {
      await _finishFailed();
      return;
    }

    _timer = Timer.periodic(const Duration(milliseconds: 900), (_) {
      _tick(itemId);
    });
    // 立刻查一次
    await _tick(itemId);
  }

  static Future<void> _tick(int itemId) async {
    try {
      final s = await _items.getParseStatus(itemId);
      final status = s.status.toLowerCase();
      if (status == 'success') {
        _timer?.cancel();
        await _finishSuccess();
      } else if (status == 'failed') {
        _timer?.cancel();
        await _finishFailed(subtitle: s.errorMessage ?? '可稍后在详情中重试');
      }
    } on ApiException {
      // 轮询失败不打断，等下次
    } catch (_) {}
  }

  static Future<void> _finishSuccess() async {
    _progress.markSuccess();
    await _notifySettled();
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (_progress.phase == ParseProgressPhase.success) {
      _progress.hide();
    }
  }

  static Future<void> _finishFailed({String? subtitle}) async {
    _progress.markFailed(subtitle: subtitle ?? '可稍后在详情中重试');
    await _notifySettled();
    await Future<void>.delayed(const Duration(milliseconds: 1800));
    if (_progress.phase == ParseProgressPhase.failed) {
      _progress.hide();
    }
  }

  static Future<void> _notifySettled() async {
    final cb = _onSettled;
    _onSettled = null;
    if (cb != null) {
      try {
        await cb();
      } catch (_) {}
    }
  }

  static void cancel() {
    _timer?.cancel();
    _timer = null;
    _progress.hide();
  }
}
