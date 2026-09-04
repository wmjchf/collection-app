import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:super_collection/core/analytics/analytics.dart';
import 'package:super_collection/core/analytics/screen_dwell_tracker.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/features/settings/apple_iap_service.dart';
import 'package:super_collection/features/settings/legal_docs.dart';
import 'package:super_collection/features/settings/simple_doc_page.dart';
import 'package:super_collection/features/settings/usage_repository.dart';

/// 订阅升级页（太子 / 帝王；iOS StoreKit）
class UpgradeProPage extends StatefulWidget {
  const UpgradeProPage({
    super.key,
    this.from = 'settings',
    this.initialTier,
  });

  /// settings | quota | feature_gate
  final String from;

  /// 引导订阅时预选档位：`prince` | `emperor`
  final String? initialTier;

  @override
  State<UpgradeProPage> createState() => _UpgradeProPageState();
}

class _UpgradeProPageState extends State<UpgradeProPage> with ScreenDwellMixin {
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
  BillingProductsConfig? _billing;
  String _selectedTier = UsagePlan.prince;
  bool _productsLoading = true;
  AppleIapPhase? _phase;
  bool _restoreFlow = false;
  String? _error;
  String? _selectedId;

  bool get _isIos => !kIsWeb && Platform.isIOS;
  bool get _busy => _phase != null;

  String get _phaseLabel {
    switch (_phase) {
      case AppleIapPhase.paying:
        return '支付中…';
      case AppleIapPhase.activating:
        return '开通中…';
      case AppleIapPhase.restoring:
        return '恢复中…';
      case null:
        return '';
    }
  }

  @override
  String get dwellScreen => AnalyticsScreens.pro;

  @override
  Map<String, Object?> get dwellProps => {'from': widget.from};

  @override
  void initState() {
    super.initState();
    final t = UsagePlan.normalize(widget.initialTier);
    if (t == UsagePlan.emperor) _selectedTier = UsagePlan.emperor;
    Analytics.instance.proPageView(from: widget.from);
    _load();
  }

  @override
  void dispose() {
    _iap.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _productsLoading = _isIos;
      _error = null;
    });

    // 1) 先拉额度（快），立刻上屏；商品 id 一并拿到
    final billing = await _usageRepo.fetchBillingProducts();
    if (!mounted) return;
    setState(() {
      _quotas = billing.quotas;
      _billing = billing;
    });

    if (!_isIos) {
      setState(() => _productsLoading = false);
      return;
    }

    try {
      final map = await _iap.loadProducts(productIds: billing.allIds);
      if (!mounted) return;
      setState(() {
        _products = map;
        _selectedId = _defaultProductId(map);
        _productsLoading = false;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _productsLoading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _productsLoading = false;
        _error = '无法加载订阅商品';
      });
    }
  }

  TierProductIds get _tierIds {
    final billing = _billing;
    if (billing == null) {
      return const TierProductIds(
        monthly: IapProductIds.princeMonthly,
        yearly: IapProductIds.princeYearly,
      );
    }
    return _selectedTier == UsagePlan.emperor
        ? billing.emperor
        : billing.prince;
  }

  String? _defaultProductId(Map<String, ProductDetails> map) {
    final ids = _tierIds;
    if (map.containsKey(ids.yearly)) return ids.yearly;
    if (map.containsKey(ids.monthly)) return ids.monthly;
    for (final p in map.values) {
      final id = p.id.toLowerCase();
      final tier = _selectedTier;
      if (tier == UsagePlan.emperor && id.contains('emperor')) {
        if (id.contains('year')) return p.id;
      }
      if (tier == UsagePlan.prince &&
          !id.contains('emperor') &&
          id.contains('year')) {
        return p.id;
      }
    }
    return map.keys.firstOrNull;
  }

  ProductDetails? _findProduct(
    Map<String, ProductDetails> map, {
    required bool yearly,
  }) {
    final ids = _tierIds;
    final prefer = yearly ? ids.yearly : ids.monthly;
    if (map.containsKey(prefer)) return map[prefer];
    for (final p in map.values) {
      final id = p.id.toLowerCase();
      final isEmperor = id.contains('emperor');
      if (_selectedTier == UsagePlan.prince && isEmperor) continue;
      if (_selectedTier == UsagePlan.emperor && !isEmperor) continue;
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
    if (_busy && !_restoreFlow) return _phaseLabel;
    final p = _selected;
    if (p == null) return '选择方案';
    if (_isYearlyProduct(p)) return '订阅 ${p.price} / 年';
    return '订阅 ${p.price}';
  }

  void _setPhase(AppleIapPhase? phase) {
    if (!mounted) return;
    setState(() => _phase = phase);
  }

  Future<void> _buy() async {
    final product = _selected;
    if (product == null || _busy) return;
    setState(() {
      _restoreFlow = false;
      _phase = AppleIapPhase.paying;
    });
    Analytics.instance.iapPurchaseStart(
      productId: product.id,
      from: widget.from,
    );
    try {
      await _iap.buy(
        product,
        onPhase: _setPhase,
      );
      if (!mounted) return;
      UsageRefresh.bump();
      AppToast.show(context, '${UsagePlan.label(_selectedTier)} 已开通');
      Navigator.of(context).maybePop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      Analytics.instance.iapPurchaseFail(
        productId: product.id,
        errorCode: e.code ?? e.message,
      );
      if (e.message.contains('取消')) {
        AppToast.show(context, '已取消');
      } else {
        AppToast.show(context, e.message);
      }
    } catch (e) {
      if (!mounted) return;
      Analytics.instance.iapPurchaseFail(
        productId: product.id,
        errorCode: e.toString(),
      );
      AppToast.show(context, '购买失败，请稍后重试');
    } finally {
      if (mounted) {
        setState(() {
          _phase = null;
          _restoreFlow = false;
        });
      }
    }
  }

  Future<void> _restore() async {
    if (_busy) return;
    setState(() {
      _restoreFlow = true;
      _phase = AppleIapPhase.restoring;
    });
    try {
      final usage = await _iap.restore(onPhase: _setPhase);
      if (!mounted) return;
      if (usage == null || !usage.isPro) {
        AppToast.show(context, '未找到可恢复的订阅');
      } else {
        UsageRefresh.bump();
        AppToast.show(context, '已恢复 ${usage.displayPlan}');
        Navigator.of(context).maybePop(true);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      AppToast.show(context, e.message);
    } catch (_) {
      if (!mounted) return;
      AppToast.show(context, '恢复失败');
    } finally {
      if (mounted) {
        setState(() {
          _phase = null;
          _restoreFlow = false;
        });
      }
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
          icon: const Icon(Icons.chevron_left, size: 30),
          label: const Text('返回', style: TextStyle(fontSize: 15)),
        ),
        title: const Text(
          '订阅会员',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: _text,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
              children: [
                _HeroCard(tier: _selectedTier),
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
                else if (_productsLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (_error != null) ...[
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: _muted,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _busy ? null : _load,
                    child: const Text('重试'),
                  ),
                ]                 else ...[
                  _TierPicker(
                    selected: _selectedTier,
                    onChanged: (tier) {
                      setState(() {
                        _selectedTier = tier;
                        _selectedId = _defaultProductId(_products);
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  ..._planTiles(),
                ],
              ],
            ),
          ),
          _BottomActionBar(
            showPurchaseActions: _isIos && !_productsLoading && _error == null,
            subscribeLabel: _subscribeLabel(),
            restoreLabel: _busy && _restoreFlow ? _phaseLabel : '恢复购买',
            busy: _busy,
            restoreFlow: _restoreFlow,
            subscribeEnabled: _selected != null,
            onSubscribe: _buy,
            onRestore: _restore,
            onUserAgreement: () => _openLegal(
              title: '用户协议',
              body: LegalDocs.userAgreement,
            ),
            onPrivacy: () => _openLegal(
              title: '隐私政策',
              body: LegalDocs.privacyPolicy,
            ),
          ),
        ],
      ),
    );
  }

  void _openLegal({required String title, required String body}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SimpleDocPage(title: title, body: body),
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
  const _HeroCard({required this.tier});

  final String tier;

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
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _ProBadge(),
                const SizedBox(height: 10),
                Text(
                  tier == UsagePlan.emperor ? '帝王' : '太子',
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFC7EDDB),
                    height: 38 / 32,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  tier == UsagePlan.emperor
                      ? '含太子全部能力，另解锁思维导图与视频转写。'
                      : '收藏不限条数，解锁 AI 标签与 AI 解读。',
                  style: const TextStyle(
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

class _TierPicker extends StatelessWidget {
  const _TierPicker({
    required this.selected,
    required this.onChanged,
  });

  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _TierChip(
            label: '太子',
            subtitle: 'AI 标签 · 解读',
            selected: selected == UsagePlan.prince,
            onTap: () => onChanged(UsagePlan.prince),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _TierChip(
            label: '帝王',
            subtitle: '含太子 + 脑图 · 转写',
            selected: selected == UsagePlan.emperor,
            onTap: () => onChanged(UsagePlan.emperor),
          ),
        ),
      ],
    );
  }
}

class _TierChip extends StatelessWidget {
  const _TierChip({
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? _UpgradeProPageState._blueSoft
          : Colors.white,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? _UpgradeProPageState._blue
                  : _UpgradeProPageState._border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? _UpgradeProPageState._blue
                      : _UpgradeProPageState._text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11,
                  color: _UpgradeProPageState._muted,
                  height: 1.3,
                ),
              ),
            ],
          ),
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
    final itemFree = quotas.free.itemLimit?.toString() ?? '300';
    final rows = [
      ('收藏', '在库条数', itemFree, '不限', '不限'),
      (
        'AI',
        '每月 · 积分',
        formatAiCredits(quotas.free.aiTokens),
        formatAiCredits(quotas.prince.aiTokens),
        formatAiCredits(quotas.emperor.aiTokens),
      ),
      (
        '转写',
        '每月 · 分钟',
        '${quotas.free.transcriptMinutes}',
        '${quotas.prince.transcriptMinutes}',
        '${quotas.emperor.transcriptMinutes}',
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
                flex: 2,
                child: Text(
                  '权益对照',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: _UpgradeProPageState._muted,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  '普通',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: _UpgradeProPageState._muted),
                ),
              ),
              Expanded(
                child: Text(
                  '太子',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: _UpgradeProPageState._muted),
                ),
              ),
              Expanded(
                child: Text(
                  '帝王',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _UpgradeProPageState._blue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, thickness: 1, color: Color(0xFFF0F1F4)),
            _QuotaRow3(
              label: rows[i].$1,
              unit: rows[i].$2,
              free: rows[i].$3,
              prince: rows[i].$4,
              emperor: rows[i].$5,
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

class _QuotaRow3 extends StatelessWidget {
  const _QuotaRow3({
    required this.label,
    required this.unit,
    required this.free,
    required this.prince,
    required this.emperor,
  });

  final String label;
  final String unit;
  final String free;
  final String prince;
  final String emperor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: _UpgradeProPageState._text,
                  ),
                ),
                Text(
                  unit,
                  style: const TextStyle(
                    fontSize: 11,
                    color: _UpgradeProPageState._muted,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Text(
              free,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: _UpgradeProPageState._muted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              prince,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: _UpgradeProPageState._text,
              ),
            ),
          ),
          Expanded(
            child: Text(
              emperor,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
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
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final canTap = enabled && !busy;
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: (canTap || busy)
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
          onPressed: canTap ? onPressed : null,
          style: FilledButton.styleFrom(
            backgroundColor: _UpgradeProPageState._blue,
            foregroundColor: Colors.white,
            disabledBackgroundColor: busy
                ? _UpgradeProPageState._blue
                : _UpgradeProPageState._blue.withValues(alpha: 0.5),
            disabledForegroundColor: Colors.white,
            elevation: 0,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: busy
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                )
              : Text(
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

class _BottomActionBar extends StatelessWidget {
  const _BottomActionBar({
    required this.showPurchaseActions,
    required this.subscribeLabel,
    required this.restoreLabel,
    required this.busy,
    required this.restoreFlow,
    required this.subscribeEnabled,
    required this.onSubscribe,
    required this.onRestore,
    required this.onUserAgreement,
    required this.onPrivacy,
  });

  final bool showPurchaseActions;
  final String subscribeLabel;
  final String restoreLabel;
  final bool busy;
  final bool restoreFlow;
  final bool subscribeEnabled;
  final VoidCallback onSubscribe;
  final VoidCallback onRestore;
  final VoidCallback onUserAgreement;
  final VoidCallback onPrivacy;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE8EBF0))),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showPurchaseActions) ...[
                  _SubscribeButton(
                    label: subscribeLabel,
                    busy: busy && !restoreFlow,
                    enabled: subscribeEnabled,
                    onPressed: onSubscribe,
                  ),
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: busy ? null : onRestore,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF737A85),
                      minimumSize: const Size(0, 36),
                    ),
                    child: Text(
                      restoreLabel,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                _SubscriptionLegalFooter(
                  onUserAgreement: onUserAgreement,
                  onPrivacy: onPrivacy,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SubscriptionLegalFooter extends StatelessWidget {
  const _SubscriptionLegalFooter({
    required this.onUserAgreement,
    required this.onPrivacy,
  });

  final VoidCallback onUserAgreement;
  final VoidCallback onPrivacy;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 12, color: Color(0xFF737A85), height: 1.55);
    const linkStyle = TextStyle(
      fontSize: 12,
      color: Color(0xFF2F6FED),
      height: 1.55,
    );
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          const TextSpan(
            text:
                '订阅会自动续费，除非您在当前订阅结束前 24 小时以上取消自动续订。订阅高级会员即表示你接受我们的',
          ),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: GestureDetector(
              onTap: onPrivacy,
              child: const Text('隐私政策', style: linkStyle),
            ),
          ),
          const TextSpan(text: '和'),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: GestureDetector(
              onTap: onUserAgreement,
              child: const Text('用户条款', style: linkStyle),
            ),
          ),
          const TextSpan(text: '。如果您已经订阅过但未生效，请恢复购买。'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
