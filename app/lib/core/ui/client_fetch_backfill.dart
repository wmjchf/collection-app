import 'dart:async';

import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/parse_progress_tracker.dart';
import 'package:super_collection/features/items/items_repository.dart';

/// 进 App / 回前台时，自动补齐「仅入库、待本机抓页」的条目（如微信）。
/// 多条时按入库时间排队；一轮结束后重新拉列表，直到清空。
class ClientFetchBackfill {
  ClientFetchBackfill._();

  static bool _running = false;
  static bool _starting = false;
  static bool _rerunRequested = false;
  static final _items = ItemsRepository();

  static const _startupDelay = Duration(milliseconds: 1600);
  static const _perItemTimeout = Duration(seconds: 55);
  static const _betweenItems = Duration(milliseconds: 400);

  /// 可选：每条补齐结束后刷新列表
  static Future<void> Function()? onItemSettled;

  /// 真正在抓页排队时才为 true（启动空等不算），避免挡住首页剪贴板检测
  static bool get isRunning => _running;

  static Future<void> run({Duration delay = _startupDelay}) async {
    if (_running || _starting) {
      _rerunRequested = true;
      return;
    }
    _starting = true;
    _rerunRequested = false;
    try {
      // 空等期间不占 isRunning，首页可立刻弹系统「允许粘贴」
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
    } finally {
      _starting = false;
    }

    if (_running) {
      _rerunRequested = true;
      return;
    }
    _running = true;
    try {
      await _drainAll();
    } on ApiException {
      // 未登录 / 网络失败：下次回前台再试
    } catch (_) {
    } finally {
      _running = false;
      if (_rerunRequested) {
        _rerunRequested = false;
        unawaited(run(delay: Duration.zero));
      }
    }
  }

  /// 反复拉取待补齐列表并处理，直到本轮为空。
  static Future<void> _drainAll() async {
    final attempted = <int>{};
    while (true) {
      await _waitUntilIdle();
      final pending = await _items.listNeedsClientFetch(limit: 50);
      final todo = pending.where((e) => !attempted.contains(e.id)).toList();
      if (todo.isEmpty) return;

      for (var i = 0; i < todo.length; i++) {
        await _waitUntilIdle();
        final row = todo[i];
        attempted.add(row.id);
        if (row.url.isEmpty) continue;

        final label = (row.title?.trim().isNotEmpty == true)
            ? row.title!.trim()
            : row.url;
        final done = Completer<void>();

        try {
          await ParseProgressTracker.watchItem(
            row.id,
            platform: row.platform,
            url: row.url,
            title: '正在补全解析',
            subtitle: '${attempted.length} · $label',
            onSettled: () async {
              try {
                await onItemSettled?.call();
              } catch (_) {}
              if (!done.isCompleted) done.complete();
            },
          );
          await done.future.timeout(_perItemTimeout);
        } on TimeoutException {
          ParseProgressTracker.cancel();
          if (!done.isCompleted) done.complete();
        } catch (_) {
          ParseProgressTracker.cancel();
          if (!done.isCompleted) done.complete();
        }

        await Future<void>.delayed(_betweenItems);
      }
      // 继续 while：可能还有未尝试的（本批>20 时下一批）
    }
  }

  static Future<void> _waitUntilIdle() async {
    var spins = 0;
    while (ParseProgressTracker.isBusy) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      spins++;
      // 防止异常状态下永久卡住整队
      if (spins > 120) {
        ParseProgressTracker.cancel();
        break;
      }
    }
  }
}
