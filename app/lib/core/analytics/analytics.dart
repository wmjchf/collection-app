import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/features/auth/auth_repository.dart';

/// P0 产品行为埋点（fire-and-forget 批量上报）。
/// 不含正文/链接原文；失败静默，不影响主流程。
class Analytics {
  Analytics._();

  static final Analytics instance = Analytics._();

  static const _appVersion = '1.1.0';
  static const _flushInterval = Duration(seconds: 8);
  static const _maxQueue = 40;

  final _auth = AuthRepository();
  final _api = ApiClient();
  final _queue = <Map<String, dynamic>>[];
  final _rng = Random();

  String? _sessionId;
  Timer? _flushTimer;
  bool _flushing = false;
  bool _coldStartSent = false;

  String get sessionId {
    _sessionId ??=
        '${DateTime.now().millisecondsSinceEpoch}-${_rng.nextInt(1 << 32)}';
    return _sessionId!;
  }

  void _ensureFlushTimer() {
    _flushTimer ??= Timer.periodic(_flushInterval, (_) => unawaited(flush()));
  }

  /// 统一入口
  void track(String name, [Map<String, Object?> props = const {}]) {
    final clean = <String, Object?>{};
    for (final e in props.entries) {
      final v = e.value;
      if (v == null) continue;
      if (v is bool || v is num || v is String) {
        clean[e.key] = v is String && v.length > 200 ? v.substring(0, 200) : v;
      }
    }
    _queue.add({
      'name': name,
      'props': clean,
      'clientTs': DateTime.now().toUtc().toIso8601String(),
      'sessionId': sessionId,
    });
    while (_queue.length > _maxQueue) {
      _queue.removeAt(0);
    }
    _ensureFlushTimer();
    if (_queue.length >= 12) {
      unawaited(flush());
    }
  }

  Future<void> flush() async {
    if (_flushing || _queue.isEmpty) return;
    final session = await _auth.readSession();
    if (session == null) return;

    _flushing = true;
    final batch = List<Map<String, dynamic>>.from(_queue);
    _queue.clear();
    try {
      await _api.post(
        '/api/analytics/events',
        accessToken: session.accessToken,
        body: {
          'events': batch,
          'sessionId': sessionId,
          'appVersion': _appVersion,
          'platformOs': Platform.isIOS
              ? 'ios'
              : (Platform.isAndroid ? 'android' : 'other'),
        },
      );
    } catch (e, st) {
      // 放回队列头部，下次再试（丢弃过多避免堆积）
      _queue.insertAll(0, batch);
      while (_queue.length > _maxQueue) {
        _queue.removeLast();
      }
      debugPrint('[analytics] flush failed: $e\n$st');
    } finally {
      _flushing = false;
    }
  }

  // —— P0 便捷方法 ——

  void appOpen({bool coldStart = false, bool fromShortcut = false}) {
    if (coldStart) {
      if (_coldStartSent) {
        track('app_open', {
          'cold_start': false,
          if (fromShortcut) 'from_shortcut': true,
        });
        return;
      }
      _coldStartSent = true;
    }
    track('app_open', {
      'cold_start': coldStart,
      if (fromShortcut) 'from_shortcut': true,
    });
  }

  void appBackground() => track('app_background');

  void itemSaveStart({required String source, String? platform}) {
    track('item_save_start', {
      'source': source,
      if (platform != null && platform.isNotEmpty) 'platform': platform,
    });
  }

  void itemSaveSuccess({
    required String source,
    required int itemId,
    String? platform,
    bool existed = false,
  }) {
    track('item_save_success', {
      'source': source,
      'item_id': itemId,
      'existed': existed,
      if (platform != null && platform.isNotEmpty) 'platform': platform,
    });
  }

  void itemSaveFail({
    required String source,
    String? platform,
    String? errorCode,
  }) {
    track('item_save_fail', {
      'source': source,
      if (platform != null && platform.isNotEmpty) 'platform': platform,
      if (errorCode != null && errorCode.isNotEmpty) 'error_code': errorCode,
    });
  }

  void itemOpen({required int itemId, required String entry, String? platform}) {
    track('item_open', {
      'item_id': itemId,
      'entry': entry,
      if (platform != null && platform.isNotEmpty) 'platform': platform,
    });
  }

  void readingDwell({required int itemId, required int seconds}) {
    track('reading_dwell', {
      'item_id': itemId,
      'seconds': seconds,
      'seconds_bucket': secondsBucket(seconds),
    });
  }

  void screenDwell({
    required String screen,
    required int seconds,
    Map<String, Object?> props = const {},
  }) {
    track('screen_dwell', {
      'screen': screen,
      'seconds': seconds,
      'seconds_bucket': secondsBucket(seconds),
      ...props,
    });
  }

  void searchSubmit({required bool hasResult, required int resultCount}) {
    track('search_submit', {
      'has_result': hasResult,
      'result_count': resultCount,
    });
  }

  void proPageView({required String from}) {
    track('pro_page_view', {'from': from});
  }

  void iapPurchaseFail({String? productId, String? errorCode}) {
    track('iap_purchase_fail', {
      if (productId != null) 'product_id': productId,
      if (errorCode != null) 'error_code': errorCode,
    });
  }

  static String secondsBucket(int seconds) {
    if (seconds < 5) return '0-5';
    if (seconds < 15) return '5-15';
    if (seconds < 60) return '15-60';
    if (seconds < 180) return '60-180';
    return '180+';
  }
}
