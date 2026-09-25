import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_collection/core/config/app_brand.dart';
import 'package:super_collection/core/ui/app_confirm_dialog.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/features/settings/app_version_repository.dart';
import 'package:url_launcher/url_launcher.dart';

/// 进入主壳后可选更新提示（失败静默）。
abstract final class AppUpdatePrompt {
  static const _dismissKeyPrefix = 'app_update_dismissed_';

  static bool _checking = false;

  /// 与本地版本比较；有新版本且未对本 latest 点过「稍后再说」则弹窗。
  static Future<void> maybeShow(BuildContext context) async {
    if (_checking) return;
    _checking = true;
    try {
      final remote = await AppVersionRepository().fetch();
      final latest = remote.latestVersion;
      if (latest.isEmpty) return;

      final info = await PackageInfo.fromPlatform();
      final local = info.version.trim();
      if (!_isOlder(local, latest)) return;

      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('$_dismissKeyPrefix$latest') == true) return;

      if (!context.mounted) return;

      final storeUrl = _storeUrlForPlatform(remote);
      final notes = remote.releaseNotes.isNotEmpty
          ? remote.releaseNotes
          : '${AppBrand.name} $latest 已发布，建议更新以获得更好体验。';

      final go = await showAppConfirmDialog(
        context,
        title: '发现新版本',
        message: notes,
        cancelLabel: '稍后再说',
        confirmLabel: storeUrl.isEmpty ? '知道了' : '立即更新',
        dangerConfirm: false,
      );

      if (go != true) {
        await prefs.setBool('$_dismissKeyPrefix$latest', true);
        return;
      }

      if (storeUrl.isEmpty) {
        await prefs.setBool('$_dismissKeyPrefix$latest', true);
        if (context.mounted) {
          AppToast.show(context, '更新链接未配置');
        }
        return;
      }

      final uri = Uri.tryParse(storeUrl);
      if (uri == null) {
        if (context.mounted) {
          AppToast.show(context, '更新链接无效');
        }
        return;
      }
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && context.mounted) {
        AppToast.show(context, '无法打开应用商店');
      }
    } catch (_) {
      // 网络等失败不打扰
    } finally {
      _checking = false;
    }
  }

  static String _storeUrlForPlatform(AppVersionInfo remote) {
    if (kIsWeb) return '';
    if (Platform.isIOS || Platform.isMacOS) return remote.iosStoreUrl;
    if (Platform.isAndroid) return remote.androidStoreUrl;
    return '';
  }

  /// 本地版本是否低于远端（按 major.minor.patch 数字比较）。
  static bool _isOlder(String local, String remote) {
    final a = _parts(local);
    final b = _parts(remote);
    for (var i = 0; i < 3; i++) {
      if (a[i] < b[i]) return true;
      if (a[i] > b[i]) return false;
    }
    return false;
  }

  static List<int> _parts(String version) {
    final raw = version.split('+').first.trim();
    final segs = raw.split('.');
    return List<int>.generate(3, (i) {
      if (i >= segs.length) return 0;
      return int.tryParse(segs[i].replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    });
  }
}
