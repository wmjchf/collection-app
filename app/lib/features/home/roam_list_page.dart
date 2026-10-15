import 'package:flutter/material.dart';
import 'package:super_collection/core/analytics/screen_dwell_tracker.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_subpage_app_bar.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/core/ui/paged_list.dart';
import 'package:super_collection/features/home/home_repository.dart';
import 'package:super_collection/features/home/roam_models.dart';
import 'package:super_collection/features/home/roam_mute.dart';
import 'package:super_collection/features/home/roam_open.dart';
import 'package:super_collection/features/home/widgets/roam_quote_card.dart';
import 'package:super_collection/features/items/items_repository.dart';

class RoamListPage extends StatefulWidget {
  const RoamListPage({super.key});

  @override
  State<RoamListPage> createState() => _RoamListPageState();
}

class _RoamListPageState extends State<RoamListPage> with ScreenDwellMixin {
  static const _bg = Color(0xFFF7F7FA);
  static const _muted = Color(0xFF737A85);

  final _repo = HomeRepository();
  final _items = ItemsRepository();
  final _scroll = ScrollController();
  List<RoamSnippet> _itemsList = const [];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  bool get _hasMore => _itemsList.length < _total;

  @override
  String get dwellScreen => AnalyticsScreens.roamList;

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
      });
    }
    try {
      final data = await _repo.fetchRoam(limit: 20, offset: 0);
      final items = await RoamMute.visible(data.items);
      if (!mounted) return;
      setState(() {
        _itemsList = items;
        _total = data.total;
        _loading = false;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '加载失败';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loading) return;
    setState(() => _loadingMore = true);
    try {
      final data = await _repo.fetchRoam(
        limit: 20,
        offset: _itemsList.length,
      );
      final more = await RoamMute.visible(data.items);
      if (!mounted) return;
      setState(() {
        _itemsList = [..._itemsList, ...more];
        _total = data.total;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _open(RoamSnippet snippet) async {
    try {
      final deleted = await openRoamSnippet(
        context,
        snippet,
        itemsRepository: _items,
      );
      if (!mounted) return;
      if (deleted == true) {
        setState(() {
          _itemsList =
              _itemsList.where((e) => e.itemId != snippet.itemId).toList();
          _total = (_total - 1).clamp(0, 1 << 30);
        });
      } else {
        await _load(reset: true);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      AppToast.show(context, e.message);
    } catch (_) {
      if (!mounted) return;
      AppToast.show(context, '打开失败');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: const AppSubpageAppBar(title: '漫游'),
      body: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: _loading && _itemsList.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  Center(child: CircularProgressIndicator()),
                ],
              )
            : _error != null && _itemsList.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 80),
                      Center(
                        child: Text(
                          _error!,
                          style: const TextStyle(color: _muted),
                        ),
                      ),
                      TextButton(
                        onPressed: () => _load(reset: true),
                        child: const Text('重试'),
                      ),
                    ],
                  )
                : ListView.separated(
                    controller: _scroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      16,
                      12,
                      16,
                      24 + MediaQuery.paddingOf(context).bottom,
                    ),
                    itemCount: _itemsList.isEmpty ? 1 : _itemsList.length + 1,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      if (_itemsList.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.only(top: 80),
                          child: Text(
                            '读的时候划重点、写批注或感想，就会出现在这里',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14, color: _muted),
                          ),
                        );
                      }
                      if (index == _itemsList.length) {
                        return pagedListFooter(
                          loadingMore: _loadingMore,
                          hasMore: _hasMore,
                          isEmpty: false,
                        );
                      }
                      final snippet = _itemsList[index];
                      return RoamQuoteCard(
                        snippet: snippet,
                        maxLines: 6,
                        onTap: () => _open(snippet),
                      );
                    },
                  ),
      ),
    );
  }
}
