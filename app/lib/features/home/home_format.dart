import 'package:super_collection/features/home/home_mock_data.dart';
import 'package:super_collection/features/items/item_models.dart';

/// 来源标签。
/// - 已知平台 id 直接展示
/// - `web` / 空：尝试从 URL 域名主体推断，避免一律显示 web
String platformLabel(String? platform, {String? url}) {
  final p = (platform ?? '').trim();
  if (p == 'guide') return '奏折';
  if (p.isNotEmpty && p != 'web') return p;
  final fromUrl = platformIdFromUrl(url);
  if (fromUrl != null && fromUrl.isNotEmpty) return fromUrl;
  return p.isEmpty ? 'web' : p;
}

/// 与后端 `platformIdFromHost` 对齐：m.theblockbeats.info → theblockbeats
String? platformIdFromUrl(String? rawUrl) {
  final raw = (rawUrl ?? '').trim();
  if (raw.isEmpty) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null || uri.host.isEmpty) return null;
  return platformIdFromHost(uri.host);
}

String? platformIdFromHost(String hostname) {
  var host = hostname.trim().toLowerCase();
  if (host.endsWith('.')) host = host.substring(0, host.length - 1);
  if (host.isEmpty) return null;
  if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host) || host.contains(':')) {
    return null;
  }
  if (host == 'localhost') return 'localhost';

  host = host.replaceFirst(RegExp(r'^www\.'), '');
  host = host.replaceFirst(RegExp(r'^(m|mobile|wap|app|www\d*)\.'), '');

  final parts = host.split('.').where((e) => e.isNotEmpty).toList();
  if (parts.isEmpty) return null;

  const multiTld = {
    'com.cn',
    'net.cn',
    'org.cn',
    'co.uk',
    'com.hk',
    'com.tw',
  };
  final last2 =
      parts.length >= 2 ? '${parts[parts.length - 2]}.${parts[parts.length - 1]}' : '';
  String brand;
  if (parts.length >= 3 && multiTld.contains(last2)) {
    brand = parts[parts.length - 3];
  } else if (parts.length >= 2) {
    brand = parts[parts.length - 2];
  } else {
    brand = parts[0];
  }

  final id = brand.replaceAll(RegExp(r'[^a-z0-9-]', caseSensitive: false), '').toLowerCase();
  if (id.isEmpty || id == 'www') return null;
  return id;
}

String formatRelativeDay(DateTime? time, {DateTime? now}) {
  if (time == null) return '';
  final n = now ?? DateTime.now();
  final local = time.toLocal();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(local.year, local.month, local.day);
  final diffDays = today.difference(day).inDays;
  if (diffDays == 0) return '今天';
  if (diffDays == 1) return '昨天';
  final mm = local.month.toString().padLeft(2, '0');
  final dd = local.day.toString().padLeft(2, '0');
  return '$mm/$dd';
}

String formatRelativeTime(DateTime? time, {DateTime? now}) {
  if (time == null) return '';
  final n = now ?? DateTime.now();
  final local = time.toLocal();
  final diff = n.difference(local);
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  if (diff.inHours < 24 && n.day == local.day) {
    return '${diff.inHours} 小时前';
  }
  return formatRelativeDay(local, now: n);
}

HomeItemPreview previewForUnread(CollectionItem item) {
  final title = item.title?.isNotEmpty == true ? item.title! : item.url;
  final pageUrl = (item.canonicalUrl?.trim().isNotEmpty == true)
      ? item.canonicalUrl!
      : item.url;
  final subtitle =
      '${platformLabel(item.platform, url: pageUrl)} · ${formatRelativeDay(item.createdAt)}';
  return HomeItemPreview(
    id: item.id,
    title: title,
    subtitle: subtitle,
    coverImageUrl: item.coverImageUrl,
    pageUrl: item.sourcePageUrl,
    tags: item.tags,
  );
}

HomeItemPreview previewForRecentRead(CollectionItem item) {
  final title = item.title?.isNotEmpty == true ? item.title! : item.url;
  final pageUrl = (item.canonicalUrl?.trim().isNotEmpty == true)
      ? item.canonicalUrl!
      : item.url;
  final subtitle =
      '${platformLabel(item.platform, url: pageUrl)} · ${formatRelativeTime(item.lastReadAt)}';
  return HomeItemPreview(
    id: item.id,
    title: title,
    subtitle: subtitle,
    coverImageUrl: item.coverImageUrl,
    pageUrl: item.sourcePageUrl,
    tags: item.tags,
  );
}
