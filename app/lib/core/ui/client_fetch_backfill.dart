import 'dart:async';

import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/parse_progress_tracker.dart';
import 'package:super_collection/features/items/items_repository.dart';

/// 进 App / 回前台时，自动补齐「仅入库、待本机抓页」的条目（如微信）。
/// 多条时按入库时间排队处理，用户无需手动选择解析哪一条。
class ClientFetchBackfill {
  ClientFetchBackfill._();

  static bool _running = false;
  static final _items = ItemsRepository();

  /// 可选：每条补齐结束后刷新列表
  static Future<void> Function()? onItemSettled;

  static Future<void> run({Duration delay = const Duration(milliseconds: 1600)}) async {
    if (_running) return;
    _running = true;
    try {
      // 让剪贴板自动保存等前台流程先占用进度条
      await Future<void>.delayed(delay);
      await _waitUntilIdle();

      final pending = await _items.listNeedsClientFetch(limit: 20);
      if (pending.isEmpty) return;

      for (var i = 0; i < pending.length; i++) {
        await _waitUntilIdle();
        final row = pending[i];
        final label = (row.title?.trim().isNotEmpty == true)
            ? row.title!.trim()
            : row.url;
        final done = Completer<void>();

        ParseProgressTracker.begin(
          title: '正在补全解析',
          subtitle: '${i + 1}/${pending.length} · $label',
        );
        await ParseProgressTracker.watchItem(
          row.id,
          platform: row.platform,
          url: row.url,
          onSettled: () async {
            try {
              await onItemSettled?.call();
            } catch (_) {}
            if (!done.isCompleted) done.complete();
          },
        );
        await done.future;
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
    } on ApiException {
      // 未登录 / 网络失败：下次回前台再试
    } catch (_) {
    } finally {
      _running = false;
    }
  }

  static Future<void> _waitUntilIdle() async {
    while (ParseProgressTracker.isBusy) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
  }
}
