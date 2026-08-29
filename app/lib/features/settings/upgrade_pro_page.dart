import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/features/settings/apple_iap_service.dart';
import 'package:super_collection/features/settings/usage_repository.dart';

/// 升级 Pro（对齐 Figma `42. 升级 Pro`；iOS StoreKit）
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
  static const _border = Color(0xFFE8EBF0);

  final _iap = AppleIapService();
  final _usageRepo = UsageRepository();

  Map<String, ProductDetails> _products = {};
  PlanQuotasTable _quotas = PlanQuotasTable.defaults;
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
    setState(() {
      _loading = true;
      _error = null;
    });

    final quotasFuture = _usageRepo.fetchPlanQuotas();

    if (!_isIos) {
      final quotas = await quotasFuture;
      if (!mounted) return;
      setState(() {
        _quotas = quotas;
        _loading = false;
        _error = null;
      });
      return;
    }

    try {
      final results = await Future.wait<Object>([
        _iap.loadProducts(),
        quotasFuture,
      ]);
      if (!mounted) return;
      final map = results[0] as Map<String, ProductDetails>;
      final quotas = results[1] as PlanQuotasTable;
      final yearly = _findProduct(map, yearly: true);
      final monthly = _findProduct(map, yearly: false);
      setState(() {
        _products = map;
        _quotas = quotas;
        _selectedId = yearly?.id ?? monthly?.id ?? map.keys.firstOrNull;
        _loading = false;
      });
    } on ApiException catch (e) {
      final quotas = await quotasFuture;
      if (!mounted) return;
      setState(() {
        _quotas = quotas;
        _loading = false;
        _error = e.message;
      });
    } catch (e) {
      final quotas = await quotasFuture;
      if (!mounted) return;
      setState(() {
        _quotas = quotas;
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

  bool _isYearlyProduct(ProductDetails? p) {
    if (p == null) return false;
    final id = p.id.toLowerCase();
    return id.contains('year') || id.contains('annual');
  }

  String _yearlyPerMonthHint(ProductDetails yearly) {
    final raw = yearly.rawPrice;
    if (raw > 0) {
      final perMonth = raw / 12;
      final symbol = yearly.currencySymbol;
      final n = perMonth >= 100
          ? perMonth.toStringAsFixed(0)
          : perMonth.toStringAsFixed(1);
      return '约 $symbol$n / 月 · 自动续期';
    }
    return '自动续期';
  }

  String _subscribeLabel() {
    if (_busy) return '处理中…';
    final p = _selected;
    if (p == null) return '选择方案';
    if (_isYearlyProduct(p)) return '订阅 ${p.price} / 年';
    return '订阅 ${p.price}';
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
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          const _HeroCard(),
          const SizedBox(height: 14),
          _QuotaTable(quotas: _quotas),
          const SizedBox(height: 14),
          if (!_isIos)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '请在 iPhone 上通过 App Store 订阅。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: _muted, height: 1.4),
              ),
            )
          else if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
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
            const SizedBox(height: 14),
            _SubscribeButton(
              label: _subscribeLabel(),
              enabled: !_busy && _selected != null,
              onPressed: _buy,
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : _restore,
              style: TextButton.styleFrom(
                foregroundColor: _muted,
                minimumSize: const Size(0, 36),
              ),
              child: const Text('恢复购买', style: TextStyle(fontSize: 14)),
            ),
          ],
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
          subtitle: _yearlyPerMonthHint(yearly),
          price: yearly.price,
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
          subtitle: '按月自动续期',
          price: monthly.price,
          selected: _selectedId == monthly.id,
          onTap: () => setState(() => _selectedId = monthly.id),
        ),
      );
    }
    if (tiles.isEmpty) {
      for (final p in _products.values) {
        if (tiles.isNotEmpty) tiles.add(const SizedBox(height: 10));
        tiles.add(
          _PlanTile(
            title: p.title,
            subtitle: p.description.isNotEmpty ? p.description : p.price,
            price: p.price,
            selected: _selectedId == p.id,
            onTap: () => setState(() => _selectedId = p.id),
          ),
        );
      }
    }
    return tiles;
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(-0.85, -0.4),
            end: Alignment(0.9, 1.0),
            colors: [
              Color(0xFF121F1C),
              Color(0xFF1A382E),
              Color(0xFF24473D),
            ],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              right: -24,
              top: -36,
              child: Container(
                width: 160,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF8CD9B8).withValues(alpha: 0.22),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF8CD9B8).withValues(alpha: 0.35),
                      blurRadius: 48,
                      spreadRadius: 8,
                    ),
                  ],
                ),
              ),
            ),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ProBadge(),
                SizedBox(height: 10),
                Text(
                  'Conflux Pro',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFC7EDDB),
                    height: 38 / 32,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  '基础收藏与解析永远免费。\nPro 提高转写与 AI 的月额度。',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xC7FFFFFF),
                    height: 21 / 14,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProBadge extends StatelessWidget {
  const _ProBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFB8E5D1).withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Text(
        'PRO',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: Color(0xFFB8E5D1),
          letterSpacing: 1.2,
          height: 1.2,
        ),
      ),
    );
  }
}

class _QuotaTable extends StatelessWidget {
  const _QuotaTable({required this.quotas});

  final PlanQuotasTable quotas;

  @override
  Widget build(BuildContext context) {
    final rows = [
      (
        '转写',
        '每月 · 分钟',
        '${quotas.free.transcriptMinutes}',
        '${quotas.pro.transcriptMinutes}',
      ),
      (
        'AI 标签',
        '每月 · 次',
        '${quotas.free.aiTags}',
        '${quotas.pro.aiTags}',
      ),
      (
        '思维导图',
        '每月 · 次',
        '${quotas.free.aiMindmap}',
        '${quotas.pro.aiMindmap}',
      ),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _UpgradeProPageState._border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Expanded(
                child: Text(
                  '本月额度',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: _UpgradeProPageState._muted,
                  ),
                ),
              ),
              SizedBox(
                width: 72,
                child: Text(
                  '普通',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: _UpgradeProPageState._muted,
                  ),
                ),
              ),
              SizedBox(
                width: 88,
                child: Center(
                  child: _ProColumnHeader(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, thickness: 1, color: Color(0xFFF0F1F4)),
            _QuotaRow(
              label: rows[i].$1,
              unit: rows[i].$2,
              freeValue: rows[i].$3,
              proValue: rows[i].$4,
            ),
          ],
          const SizedBox(height: 8),
          const Text(
            '额度按自然月重置；已生成内容始终可查看',
            style: TextStyle(
              fontSize: 11,
              color: _UpgradeProPageState._muted,
              height: 16 / 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProColumnHeader extends StatelessWidget {
  const _ProColumnHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _UpgradeProPageState._blueSoft,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'Pro',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: _UpgradeProPageState._blue,
        ),
      ),
    );
  }
}

class _QuotaRow extends StatelessWidget {
  const _QuotaRow({
    required this.label,
    required this.unit,
    required this.freeValue,
    required this.proValue,
  });

  final String label;
  final String unit;
  final String freeValue;
  final String proValue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: _UpgradeProPageState._text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  unit,
                  style: const TextStyle(
                    fontSize: 12,
                    color: _UpgradeProPageState._muted,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 72,
            child: Text(
              freeValue,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                color: _UpgradeProPageState._muted,
              ),
            ),
          ),
          SizedBox(
            width: 88,
            child: Text(
              proValue,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _UpgradeProPageState._blue,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({
    required this.title,
    required this.subtitle,
    required this.price,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final String title;
  final String subtitle;
  final String price;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _UpgradeProPageState._blueSoft : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? _UpgradeProPageState._blue
                  : _UpgradeProPageState._border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              _RadioMark(selected: selected),
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
                            fontWeight: FontWeight.w700,
                            color: _UpgradeProPageState._text,
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _UpgradeProPageState._blue,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              badge!,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: _UpgradeProPageState._muted,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                price,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? _UpgradeProPageState._blue
                      : _UpgradeProPageState._text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RadioMark extends StatelessWidget {
  const _RadioMark({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    const size = 20.0;
    if (!selected) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFC7CCD4), width: 1.5),
        ),
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _SelectedRadioPainter()),
    );
  }
}

class _SelectedRadioPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = const Color(0xFF2F6FED)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final fill = Paint()
      ..color = const Color(0xFF2F6FED)
      ..style = PaintingStyle.fill;
    final c = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(c, size.width / 2 - 1, stroke);
    canvas.drawCircle(c, size.width * 0.25, fill);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SubscribeButton extends StatelessWidget {
  const _SubscribeButton({
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: const Color(0xFF2E59D9).withValues(alpha: 0.28),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: FilledButton(
          onPressed: enabled ? onPressed : null,
          style: FilledButton.styleFrom(
            backgroundColor: _UpgradeProPageState._blue,
            foregroundColor: Colors.white,
            disabledBackgroundColor:
                _UpgradeProPageState._blue.withValues(alpha: 0.5),
            elevation: 0,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
