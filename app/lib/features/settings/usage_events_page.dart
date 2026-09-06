import 'package:flutter/material.dart';
import 'package:super_collection/core/analytics/screen_dwell_tracker.dart';
import 'package:super_collection/core/ui/paged_list.dart';
import 'package:super_collection/features/items/item_reading_page.dart';
import 'package:super_collection/features/settings/usage_repository.dart';

enum UsageEventsKind { ai, transcript }

/// 本月 AI / 转写用量明细
class UsageEventsPage extends StatefulWidget {
  const UsageEventsPage({
    super.key,
    required this.kind,
    this.yearMonth,
  });

  final UsageEventsKind kind;
  final String? yearMonth;

  @override
  State<UsageEventsPage> createState() => _UsageEventsPageState();
}

class _UsageEventsPageState extends State<UsageEventsPage> with ScreenDwellMixin {
  static const _bg = Color(0xFFF7F7FA);
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _divider = Color(0xFFECEEF2);

  final _repo = UsageRepository();
  final _scroll = ScrollController();

  List<UsageEvent> _items = const [];
  int _total = 0;
  String _yearMonth = '';
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  bool get _hasMore => _items.length < _total;

  @override
  String get dwellScreen => widget.kind == UsageEventsKind.ai
      ? AnalyticsScreens.usageAiEvents
      : AnalyticsScreens.usageTranscriptEvents;

  String get _pageTitle =>
      widget.kind == UsageEventsKind.ai ? 'AI 用量记录' : '转写用量记录';

  String get _apiKind =>
      widget.kind == UsageEventsKind.ai ? 'ai' : 'transcript';

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (shouldLoadMore(_scroll)) _loadMore();
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _items = const [];
        _total = 0;
      });
    }
    try {
      final data = await _repo.fetchUsageEvents(
        kind: _apiKind,
        limit: kItemsPageSize,
        offset: 0,
      );
      if (!mounted) return;
      setState(() {
        _items = data.items;
        _total = data.total;
        _yearMonth = data.yearMonth;
        _loading = false;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = '加载失败';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final data = await _repo.fetchUsageEvents(
        kind: _apiKind,
        limit: kItemsPageSize,
        offset: _items.length,
      );
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...data.items];
        _total = data.total;
        _yearMonth = data.yearMonth;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  String _fmtDateTime(DateTime? dt) {
    if (dt == null) return '';
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '${local.month}月${local.day}日 $h:$min';
  }

  void _openItem(UsageEvent event) {
    final id = event.itemId;
    if (id == null || event.itemDeleted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ItemReadingPage(
          itemId: id,
          openEntry: 'usage',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ym = _yearMonth.isNotEmpty ? _yearMonth : (widget.yearMonth ?? '');
    final sectionTitle = ym.isEmpty ? '本月' : '本月（$ym）';

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leadingWidth: 80,
        leading: TextButton.icon(
          onPressed: () => Navigator.of(context).maybePop(),
          style: TextButton.styleFrom(
            foregroundColor: _text,
            padding: const EdgeInsets.only(left: 8),
          ),
          icon: const Icon(Icons.chevron_left, size: 30),
          label: const Text('返回', style: TextStyle(fontSize: 15)),
        ),
        title: Text(
          _pageTitle,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: _text,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, style: const TextStyle(color: _muted)),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => _load(reset: true),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _load(reset: true),
                  child: CustomScrollView(
                    controller: _scroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
                        sliver: SliverList(
                          delegate: SliverChildListDelegate([
                            _SectionHeader(
                              title: sectionTitle,
                              count: _total,
                            ),
                            const SizedBox(height: 8),
                            if (_items.isEmpty)
                              const Padding(
                                padding: EdgeInsets.only(top: 48),
                                child: Center(
                                  child: Text(
                                    '本月暂无记录',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: _muted,
                                    ),
                                  ),
                                ),
                              )
                            else
                              _CardGroup(
                                children: [
                                  for (var i = 0; i < _items.length; i++) ...[
                                    if (i > 0)
                                      const Divider(
                                        height: 1,
                                        indent: 16,
                                        endIndent: 16,
                                        color: _divider,
                                      ),
                                    _UsageEventRow(
                                      event: _items[i],
                                      timeLabel:
                                          _fmtDateTime(_items[i].createdAt),
                                      onTap: _items[i].canOpenItem
                                          ? () => _openItem(_items[i])
                                          : null,
                                    ),
                                  ],
                                ],
                              ),
                            pagedListFooter(
                              loadingMore: _loadingMore,
                              hasMore: _hasMore,
                              isEmpty: _items.isEmpty,
                            ),
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.count,
  });

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFF737A85),
            ),
          ),
          if (count > 0) ...[
            const Spacer(),
            Text(
              '共 $count 条',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF737A85),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CardGroup extends StatelessWidget {
  const _CardGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _UsageEventRow extends StatelessWidget {
  const _UsageEventRow({
    required this.event,
    required this.timeLabel,
    this.onTap,
  });

  final UsageEvent event;
  final String timeLabel;
  final VoidCallback? onTap;

  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _blue = Color(0xFF2F6FED);

  @override
  Widget build(BuildContext context) {
    final mutedTitle = event.itemDeleted;
    final meta = timeLabel.isEmpty
        ? event.featureLabel
        : '${event.featureLabel} · $timeLabel';

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 14, onTap != null ? 12 : 16, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: mutedTitle ? _muted : _text,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: _muted,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      event.amountLabel,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _blue,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: _muted,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
