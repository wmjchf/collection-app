import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/network/client_page_fetch.dart';
import 'package:super_collection/core/ui/parse_progress_tracker.dart';
import 'package:super_collection/core/utils/clipboard_utils.dart';
import 'package:super_collection/core/utils/link_utils.dart';
import 'package:super_collection/features/auth/auth_repository.dart';
import 'package:super_collection/features/items/items_repository.dart';
import 'package:super_collection/features/shortcuts/app_navigator.dart';

/// 处理 `supercollection://save` / `supercollection://save?url=`
class ShortcutInbound {
  ShortcutInbound._();

  static const _pendingKey = 'pending_shortcut_uri';
  static bool _handling = false;

  static bool get _overlayReady {
    final ctx = ClientPageFetch.overlayContext;
    return ctx != null && ctx.mounted;
  }

  static Future<void> handleUri(Uri uri) async {
    if (uri.scheme != 'supercollection') return;
    final isSave = uri.host == 'save' ||
        uri.path == '/save' ||
        uri.pathSegments.contains('save');
    if (!isSave) return;

    final session = await AuthRepository().readSession();
    if (session == null) {
      await _storePending(uri);
      AppNavigator.showSnackBar('请先登录，登录后将自动保存链接');
      return;
    }

    // 冷启动时 deep link 往往早于 MainShell：此时无 Overlay，本机 WebView 抓页会失败，
    // 服务端又可能把短链图文误判成视频。先挂起，等主壳就绪再执行。
    if (!_overlayReady) {
      await _storePending(uri);
      return;
    }

    await _executeSave(uri);
  }

  /// 登录成功或进入主壳后调用，消化待处理的快捷指令。
  static Future<void> flushPending() async {
    if (!_overlayReady) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingKey);
    if (raw == null || raw.isEmpty) return;
    await prefs.remove(_pendingKey);
    final uri = Uri.tryParse(raw);
    if (uri == null) return;
    await handleUri(uri);
  }

  static Future<void> _storePending(Uri uri) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingKey, uri.toString());
  }

  static Future<void> _executeSave(Uri uri) async {
    if (_handling) return;
    _handling = true;
    try {
      var url = uri.queryParameters['url']?.trim() ?? '';
      if (url.isEmpty) {
        url = await _readClipboardUrl() ?? '';
      }
      if (!isValidHttpUrl(url)) {
        AppNavigator.showSnackBar(
          url.isEmpty ? '剪贴板里没有链接' : '链接无效，请检查后重试',
        );
        return;
      }

      ParseProgressTracker.begin();
      final result = await ItemsRepository().createItem(url);
      await clearClipboard();
      if (result.existed && result.item.isSuccess) {
        ParseProgressTracker.cancel();
        AppNavigator.showSnackBar('该链接已收藏');
      } else {
        // ignore: unawaited_futures
        ParseProgressTracker.watchItem(
          result.item.id,
          initialStatus: result.item.status,
          platform: result.item.platform,
          url: result.item.canonicalUrl ?? result.item.url,
        );
      }
    } on ApiException catch (e) {
      ParseProgressTracker.cancel();
      AppNavigator.showSnackBar(e.message);
    } catch (_) {
      ParseProgressTracker.cancel();
      AppNavigator.showSnackBar('保存失败，请稍后重试');
    } finally {
      _handling = false;
    }
  }

  static Future<String?> _readClipboardUrl() => readClipboardHttpUrl();
}
