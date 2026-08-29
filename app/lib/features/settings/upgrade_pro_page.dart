import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/features/settings/apple_iap_service.dart';

/// 升级 Pro（iOS StoreKit；其它平台提示即将开放）
class UpgradeProPage extends StatefulWidget {
  const UpgradeProPage({super.key});

  @override
  State<UpgradeProPage> createState() => _UpgradeProPageState();
}

class _UpgradeProPageState extends State<UpgradeProPage> {
  static const _bg = Color(0xFFF7F7FA);
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _blue = Color(0xFF2F6FED);
  static const _blueSoft = Color(0xFFE8F0FF);

  final _iap = AppleIapService();

  Map<String, ProductDetails> _products = {};
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _selectedId;

  bool get _isIos => !kIsWeb && Platform.isIOS;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _iap.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!_isIos) {
      setState(() {
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final map = await _iap.loadProducts();
      if (!mounted) return;
      final yearly = _findProduct(map, yearly: true);
      final monthly = _findProduct(map, yearly: false);
      setState(() {
        _products = map;
        _selectedId = yearly?.id ?? monthly?.id ?? map.keys.firstOrNull;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '无法加载订阅商品';
      });
    }
  }

  ProductDetails? _findProduct(
    Map<String, ProductDetails> map, {
    required bool yearly,
  }) {
    final prefer = yearly ? IapProductIds.yearly : IapProductIds.monthly;
    if (map.containsKey(prefer)) return map[prefer];
    for (final p in map.values) {
      final id = p.id.toLowerCase();
      if (yearly && (id.contains('year') || id.contains('annual'))) {
        return p;
      }
      if (!yearly && id.contains('month')) return p;
    }
    return null;
  }

  ProductDetails? get _selected {
    final id = _selectedId;
    if (id == null) return null;
    return _products[id];
  }

  Future<void> _buy() async {
    final product = _selected;
    if (product == null || _busy) return;
    setState(() => _busy = true);
    try {
      await _iap.buy(product);
      if (!mounted) return;
      AppToast.show(context, 'Pro 已开通');
      Navigator.of(context).maybePop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.message.contains('取消')) {
        AppToast.show(context, '已取消');
      } else {
        AppToast.show(context, e.message);
      }
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, '购买失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final usage = await _iap.restore();
      if (!mounted) return;
      if (usage == null || !usage.isPro) {
        AppToast.show(context, '未找到可恢复的订阅');
      } else {
        AppToast.show(context, '已恢复 Pro');
        Navigator.of(context).maybePop(true);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      AppToast.show(context, e.message);
    } catch (_) {
      if (!mounted) return;
      AppToast.show(context, '恢复失败');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
          icon: const Icon(Icons.chevron_left, size: 28),
          label: const Text('返回', style: TextStyle(fontSize: 15)),
        ),
        title: const Text(
          '升级 Pro',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: _text,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
            decoration: BoxDecoration(
              color: _blueSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pro',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: _blue,
                    height: 1.1,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '基础收藏与解析永远免费。\nPro 提高转写与 AI 的月额度。',
                  style: TextStyle(
                    fontSize: 14,
                    color: _text,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              children: [
                _BenefitRow(title: '更高转写分钟额度'),
                _BenefitRow(title: '更多 AI 标签生成次数'),
                _BenefitRow(title: '更多思维导图生成次数'),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (!_isIos)
            const Text(
              '请在 iPhone 上通过 App Store 订阅。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: _muted, height: 1.4),
            )
          else if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_error != null) ...[
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: _muted, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: _busy ? null : _load, child: const Text('重试')),
          ] else ...[
            ..._planTiles(),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _busy || _selected == null ? null : _buy,
                style: FilledButton.styleFrom(
                  backgroundColor: _blue,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _blue.withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  _busy
                      ? '处理中…'
                      : (_selected == null
                          ? '选择方案'
                          : '订阅 ${_selected!.price}'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : _restore,
              child: const Text(
                '恢复购买',
                style: TextStyle(fontSize: 14, color: _muted),
              ),
            ),
          ],
          const SizedBox(height: 10),
          const Text(
            '订阅与额度以后端校验为准。可随时在系统设置中管理或取消订阅。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: _muted, height: 1.4),
          ),
        ],
      ),
    );
  }

  List<Widget> _planTiles() {
    final monthly = _findProduct(_products, yearly: false);
    final yearly = _findProduct(_products, yearly: true);
    final tiles = <Widget>[];
    if (yearly != null) {
      tiles.add(
        _PlanTile(
          title: '年付',
          subtitle: yearly.price,
          selected: _selectedId == yearly.id,
          badge: '更划算',
          onTap: () => setState(() => _selectedId = yearly.id),
        ),
      );
    }
    if (monthly != null) {
      if (tiles.isNotEmpty) tiles.add(const SizedBox(height: 10));
      tiles.add(
        _PlanTile(
          title: '月付',
          subtitle: monthly.price,
          selected: _selectedId == monthly.id,
          onTap: () => setState(() => _selectedId = monthly.id),
        ),
      );
    }
    // 未知 id 兜底
    if (tiles.isEmpty) {
      for (final p in _products.values) {
        if (tiles.isNotEmpty) tiles.add(const SizedBox(height: 10));
        tiles.add(
          _PlanTile(
            title: p.title,
            subtitle: p.price,
            selected: _selectedId == p.id,
            onTap: () => setState(() => _selectedId = p.id),
          ),
        );
      }
    }
    return tiles;
  }
}
class _PlanTile extends StatelessWidget {
  const _PlanTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? const Color(0xFF2F6FED) : const Color(0xFFE5E8EF),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: selected
                    ? const Color(0xFF2F6FED)
                    : const Color(0xFF737A85),
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1F242E),
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F0FF),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              badge!,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF2F6FED),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF737A85),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  const _BenefitRow({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_outline,
            size: 20,
            color: Color(0xFF2F6FED),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                color: Color(0xFF1F242E),
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
