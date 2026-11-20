import 'dart:convert';
import 'dart:math';

/// 笔记条目类型：手写想法 / 助手整理成文；`excerpt` 仅兼容旧数据。
enum ItemNoteKind {
  thought,
  excerpt,
  article;

  static ItemNoteKind parse(Object? raw) {
    final s = (raw ?? '').toString().trim().toLowerCase();
    if (s == 'excerpt' || s == 'ai_excerpt' || s == 'ai-excerpt') {
      return ItemNoteKind.excerpt;
    }
    if (s == 'article' || s == 'draft' || s == 'draft_article') {
      return ItemNoteKind.article;
    }
    return ItemNoteKind.thought;
  }

  String get wire => switch (this) {
        ItemNoteKind.excerpt => 'excerpt',
        ItemNoteKind.article => 'article',
        ItemNoteKind.thought => 'thought',
      };
}

/// 正文存储格式：规范以 Markdown 为唯一真相；富文本编辑器序列化回 MD。
/// 预留 `html` / `delta` 仅作将来扩展，当前写入一律 `markdown`。
enum ItemNoteFormat {
  markdown,
  html,
  delta;

  static ItemNoteFormat parse(Object? raw) {
    final s = (raw ?? '').toString().trim().toLowerCase();
    if (s == 'html') return ItemNoteFormat.html;
    if (s == 'delta' || s == 'quill') return ItemNoteFormat.delta;
    // plain / md / 缺省 → markdown
    return ItemNoteFormat.markdown;
  }

  String get wire => switch (this) {
        ItemNoteFormat.markdown => 'markdown',
        ItemNoteFormat.html => 'html',
        ItemNoteFormat.delta => 'delta',
      };
}

/// 条目笔记项：存于 `items.note`（JSON 数组；旧纯文本视为单条想法）。
class ItemThought {
  const ItemThought({
    required this.id,
    required this.text,
    this.title,
    this.createdAt,
    this.kind = ItemNoteKind.thought,
    this.format = ItemNoteFormat.markdown,
  });

  final String id;
  /// 正文（规范：Markdown 源）
  final String text;
  /// 标题（想法用；旧数据可空）
  final String? title;
  final DateTime? createdAt;
  final ItemNoteKind kind;
  /// 正文格式；缺省 / 旧数据视为 markdown
  final ItemNoteFormat format;

  bool get isExcerpt => kind == ItemNoteKind.excerpt;
  bool get isThought => kind == ItemNoteKind.thought;
  bool get isArticle => kind == ItemNoteKind.article;

  String get titleTrimmed => (title ?? '').trim();

  /// 列表展示标题；无标题时想法用「未命名」
  String get displayTitle {
    final t = titleTrimmed;
    if (t.isNotEmpty) return t;
    if (isThought) return '未命名';
    return '';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'kind': kind.wire,
        'format': format.wire,
        if (titleTrimmed.isNotEmpty) 'title': titleTrimmed,
        if (createdAt != null) 'createdAt': createdAt!.toUtc().toIso8601String(),
      };

  static ItemThought? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final text = (raw['text'] ?? raw['body'] ?? '').toString().trim();
    if (text.isEmpty) return null;
    final id = (raw['id'] ?? '').toString().trim();
    final titleRaw = (raw['title'] ?? '').toString().trim();
    DateTime? createdAt;
    final ca = raw['createdAt'] ?? raw['created_at'];
    if (ca != null) {
      createdAt = DateTime.tryParse(ca.toString());
    }
    return ItemThought(
      id: id.isNotEmpty ? id : _newId(),
      text: text,
      title: titleRaw.isEmpty ? null : titleRaw,
      createdAt: createdAt,
      kind: ItemNoteKind.parse(raw['kind'] ?? raw['type']),
      format: ItemNoteFormat.parse(raw['format'] ?? raw['contentFormat']),
    );
  }

  ItemThought copyWith({
    String? text,
    String? title,
    ItemNoteKind? kind,
    ItemNoteFormat? format,
    bool clearTitle = false,
  }) =>
      ItemThought(
        id: id,
        text: text ?? this.text,
        title: clearTitle ? null : (title ?? this.title),
        createdAt: createdAt,
        kind: kind ?? this.kind,
        format: format ?? this.format,
      );
}

String _newId() {
  final r = Random();
  return 't${DateTime.now().microsecondsSinceEpoch}${r.nextInt(1 << 20)}';
}

ItemThought newItemThought(
  String text, {
  String? title,
  ItemNoteFormat format = ItemNoteFormat.markdown,
}) =>
    ItemThought(
      id: _newId(),
      text: text.trim(),
      title: (title ?? '').trim().isEmpty ? null : title!.trim(),
      createdAt: DateTime.now().toUtc(),
      kind: ItemNoteKind.thought,
      format: format,
    );

ItemThought newItemExcerpt(String text) => ItemThought(
      id: _newId(),
      text: text.trim(),
      createdAt: DateTime.now().toUtc(),
      kind: ItemNoteKind.excerpt,
      format: ItemNoteFormat.markdown,
    );

ItemThought newItemArticle(String text) => ItemThought(
      id: _newId(),
      text: text.trim(),
      createdAt: DateTime.now().toUtc(),
      kind: ItemNoteKind.article,
      format: ItemNoteFormat.markdown,
    );

/// 解析 `items.note`：JSON 数组或多条兼容；旧纯文本 → 单条想法。
List<ItemThought> parseItemThoughts(String? note) {
  final raw = (note ?? '').trim();
  if (raw.isEmpty) return const [];

  if (raw.startsWith('[')) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final out = <ItemThought>[];
        for (final e in decoded) {
          final t = ItemThought.fromJson(e);
          if (t != null) out.add(t);
        }
        if (out.isNotEmpty) return out;
      }
    } catch (_) {}
  }

  if (raw.startsWith('{')) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final list = decoded['thoughts'] ?? decoded['items'];
        if (list is List) {
          final out = <ItemThought>[];
          for (final e in list) {
            final t = ItemThought.fromJson(e);
            if (t != null) out.add(t);
          }
          if (out.isNotEmpty) return out;
        }
        final single = ItemThought.fromJson(decoded);
        if (single != null) return [single];
      }
    } catch (_) {}
  }

  return [
    ItemThought(id: 'legacy', text: raw, kind: ItemNoteKind.thought),
  ];
}

/// 写回 `items.note`；空列表返回 `null`（清空字段）。
String? serializeItemThoughts(List<ItemThought> thoughts) {
  final cleaned = [
    for (final t in thoughts)
      if (t.text.trim().isNotEmpty)
        ItemThought(
          id: t.id.trim().isEmpty ? _newId() : t.id,
          text: t.text.trim(),
          title: t.titleTrimmed.isEmpty ? null : t.titleTrimmed,
          createdAt: t.createdAt,
          kind: t.kind,
          format: t.format,
        ),
  ];
  if (cleaned.isEmpty) return null;
  return jsonEncode([for (final t in cleaned) t.toJson()]);
}

bool itemNoteHasThoughts(String? note) => parseItemThoughts(note).isNotEmpty;

bool itemNoteHasKind(String? note, ItemNoteKind kind) =>
    parseItemThoughts(note).any((t) => t.kind == kind);
