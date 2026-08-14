import 'package:super_collection/features/home/home_mock_data.dart';
import 'package:super_collection/features/items/item_models.dart';

String platformLabel(String? platform) {
  switch (platform) {
    case 'weixin':
      return '微信';
    case 'xiaohongshu':
      return '小红书';
    case 'douyin':
      return '抖音';
    case 'weibo':
      return '微博';
    case 'bilibili':
      return 'B站';
    case 'jike':
      return '即刻';
    case 'zhihu':
      return '知乎';
    case 'web':
      return '网页';
    default:
      return platform?.isNotEmpty == true ? platform! : '网页';
  }
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
  final subtitle =
      '${platformLabel(item.platform)} · ${formatRelativeDay(item.createdAt)}';
  return HomeItemPreview(
    id: item.id,
    title: title,
    subtitle: subtitle,
    coverImageUrl: item.coverImageUrl,
  );
}

HomeItemPreview previewForAnnotated(CollectionItem item) {
  final title = item.title?.isNotEmpty == true ? item.title! : item.url;
  final count = item.annotationCount ?? 0;
  return HomeItemPreview(
    id: item.id,
    title: title,
    subtitle: '$count 处标注',
    coverImageUrl: item.coverImageUrl,
  );
}

HomeItemPreview previewForRecent(CollectionItem item) {
  final title = item.title?.isNotEmpty == true ? item.title! : item.url;
  return HomeItemPreview(
    id: item.id,
    title: title,
    subtitle: formatRelativeTime(item.lastReadAt ?? item.updatedAt),
    coverImageUrl: item.coverImageUrl,
  );
}
