import 'dart:async';

import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/network/client_page_fetch.dart';
import 'package:super_collection/core/network/client_webview_fetch.dart';
import 'package:super_collection/core/ui/parse_progress_controller.dart';
import 'package:super_collection/features/items/items_repository.dart';

/// 创建后展示底栏上方不确定进度条，并轮询解析状态。
/// 若服务端要求客户端抓取（如微信），则由手机出口拉 HTML 再回传。
class ParseProgressTracker {
  ParseProgressTracker._();

  static Timer? _timer;
  static final _items = ItemsRepository();
  static final _progress = ParseProgressController.instance;

  static Future<void> Function()? _onSettled;
  static bool _clientFetchStarted = false;
  static int? _watchingId;

  /// 是否正在解析 / 本机抓取（后台补齐队列需避开）
  static bool get isBusy =>
      _watchingId != null ||
      _progress.phase == ParseProgressPhase.running ||
      _progress.phase == ParseProgressPhase.success ||
      _progress.phase == ParseProgressPhase.failed;

  /// 一点击就显示底栏上方进度条（不等待 create 返回）。
  static void begin({
    String title = '正在解析内容',
    String subtitle = '拉取标题、封面与正文…',
  }) {
    _timer?.cancel();
    _timer = null;
    _clientFetchStarted = false;
    _watchingId = null;
    // 打断上一条时必须释放等待中的补齐队列 Completer
    unawaited(_notifySettled());
    _progress.start(title: title, subtitle: subtitle);
  }

  static Future<void> watchItem(
    int itemId, {
    String? initialStatus,
    String? platform,
    String? url,
    String? title,
    String? subtitle,
    Future<void> Function()? onSettled,
  }) async {
    _timer?.cancel();
    _onSettled = onSettled;
    _clientFetchStarted = false;
    _watchingId = itemId;
    _progress.start(
      itemId: itemId,
      title: title ?? '正在解析内容',
      subtitle: subtitle ?? '拉取标题、封面与正文…',
    );

    final status = (initialStatus ?? 'pending').toLowerCase();
    if (status == 'success') {
      await _finishSuccess();
      return;
    }
    if (status == 'failed') {
      await _finishFailed();
      return;
    }

    // 微信 / 抖音 / 36氪：尽早用客户端抓，不等服务端确认
    final p = (platform ?? '').toLowerCase();
    if (url != null &&
        url.isNotEmpty &&
        (p == 'weixin' ||
            p == 'wechat' ||
            p == 'douyin' ||
            p == 'kr36' ||
            ClientWebViewFetch.needsWebView(url))) {
      unawaited(_tryClientFetch(itemId, url));
    }

    _timer = Timer.periodic(const Duration(milliseconds: 900), (_) {
      _tick(itemId);
    });
    await _tick(itemId);
  }

  static Future<void> _tick(int itemId) async {
    if (_watchingId != itemId) return;
    try {
      final s = await _items.getParseStatusDetailed(itemId);
      if (_watchingId != itemId) return;
      final status = s.status.toLowerCase();
      if (status == 'success') {
        _timer?.cancel();
        await _finishSuccess();
        return;
      }
      if (status == 'failed') {
        _timer?.cancel();
        await _finishFailed(subtitle: s.errorMessage ?? '可稍后在详情中重试');
        return;
      }
      if (s.needsClientFetch &&
          s.url != null &&
          s.url!.isNotEmpty &&
          !_clientFetchStarted) {
        unawaited(_tryClientFetch(itemId, s.url!));
      }
    } on ApiException {
      // 轮询失败不打断，等下次
    } catch (_) {}
  }

  static Future<void> _tryClientFetch(int itemId, String url) async {
    if (_clientFetchStarted || _watchingId != itemId) return;
    _clientFetchStarted = true;
    _progress.start(
      itemId: itemId,
      title: _progress.title,
      subtitle: '使用本机打开页面提取…',
    );
    try {
      final html = await ClientPageFetch.fetchHtml(url);
      if (_watchingId != itemId) return;
      final item = await _items.parseWithHtml(itemId, html);
      if (_watchingId != itemId) return;
      if (item.isSuccess) {
        _timer?.cancel();
        await _finishSuccess();
      } else if (item.isFailed) {
        _timer?.cancel();
        await _finishFailed(
          subtitle: item.errorMessage ?? '可稍后在详情中重试',
        );
      }
      // 仍 pending：继续靠轮询收尾
    } on ClientPageFetchException catch (e) {
      if (_watchingId != itemId) return;
      // Overlay 未就绪：别标失败，留给主壳就绪后重试 / 补齐队列
      if (_isOverlayNotReady(e.message)) {
        _clientFetchStarted = false;
        _progress.start(
          itemId: itemId,
          title: _progress.title,
          subtitle: '等待页面就绪…',
        );
        return;
      }
      _timer?.cancel();
      await _finishFailed(subtitle: e.message);
    } on ApiException catch (e) {
      if (_watchingId != itemId) return;
      _timer?.cancel();
      await _finishFailed(subtitle: e.message);
    } catch (_) {
      if (_watchingId != itemId) return;
      _timer?.cancel();
      await _finishFailed(subtitle: '本机抓取失败，请稍后重试');
    }
  }

  static bool _isOverlayNotReady(String message) {
    return message.contains('页面未就绪') || message.contains('打开 App 后重试');
  }

  static Future<void> _finishSuccess() async {
    _timer?.cancel();
    _watchingId = null;
    _clientFetchStarted = false;
    _progress.markSuccess();
    await _notifySettled();
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (_progress.phase == ParseProgressPhase.success) {
      _progress.hide();
    }
  }

  static Future<void> _finishFailed({String? subtitle}) async {
    _timer?.cancel();
    _watchingId = null;
    _clientFetchStarted = false;
    _progress.markFailed(subtitle: subtitle ?? '可稍后在详情中重试');
    await _notifySettled();
    await Future<void>.delayed(const Duration(milliseconds: 1400));
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
    _watchingId = null;
    _clientFetchStarted = false;
    unawaited(_notifySettled());
    _progress.hide();
  }
}
