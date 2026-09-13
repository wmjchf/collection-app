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
  static const _accent = Color(0xFF2A6B52);
  static const _accentSoft = Color(0xFFE8F3EE);
  static const _border = Color(0xFFE8EBF0);

  final _iap = AppleIapService();
  final _usageRepo = UsageRepository();

  Map<String, ProductDetails> _products = {};
  /// 月付 SKU → 是否仍有资格领取免费试用（StoreKit2）
  Map<String, bool> _introEligible = {};
  PlanQuotasTable _quotas = PlanQuotasTable.defaults;
  BillingProductsConfig? _billing;
  String _selectedTier = UsagePlan.prince;
  bool _productsLoading = true;
  AppleIapPhase? _phase;
  bool _restoreFlow = false;
  String? _error;
  bool _yearlyBilling = false;

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

  String _tierDisplayName(String tier) =>
      tier == UsagePlan.emperor ? '帝王Pro' : '太子Pro';

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
      final result = await _iap.loadProducts(productIds: billing.allIds);
      if (!mounted) return;
      final eligible = await _resolveIntroEligibility(result.products);
      if (!mounted) return;
      setState(() {
        _products = result.products;
        _introEligible = eligible;
        _productsLoading = false;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _productsLoading = false;
        _introEligible = {};
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _productsLoading = false;
        _introEligible = {};
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

  ProductDetails? get _selected => _productForTier(_selectedTier);

  TierProductIds _idsForTier(String tier) {
    final billing = _billing;
    if (billing == null) {
      return tier == UsagePlan.emperor
          ? const TierProductIds(
              monthly: IapProductIds.emperorMonthly,
              yearly: IapProductIds.emperorYearly,
            )
          : const TierProductIds(
              monthly: IapProductIds.princeMonthly,
              yearly: IapProductIds.princeYearly,
            );
    }
    return tier == UsagePlan.emperor ? billing.emperor : billing.prince;
  }

  ProductDetails? _productForTier(String tier) {
    final ids = _idsForTier(tier);
    final preferred = _yearlyBilling ? ids.yearly : ids.monthly;
    final direct = _products[preferred];
    if (direct != null) return direct;

    for (final p in _products.values) {
      final id = p.id.toLowerCase();
      final isEmperor = id.contains('emperor');
      if (tier == UsagePlan.prince && isEmperor) continue;
      if (tier == UsagePlan.emperor && !isEmperor) continue;
      final isYear = _isYearlyProduct(p);
      if (_yearlyBilling == isYear) return p;
    }
    return null;
  }

  Future<Map<String, bool>> _resolveIntroEligibility(
    Map<String, ProductDetails> products,
  ) async {
    final out = <String, bool>{};
    for (final entry in products.entries) {
      final offer = freeTrialOfferOf(entry.value);
      if (offer == null) continue;
      out[entry.key] = await isIntroOfferEligible(entry.key);
    }
    return out;
  }

  /// 当前周期下该档位可展示的免费试用（仅月付 + ASC 已配 + 有资格）
  AppleFreeTrialOffer? _trialForTier(String tier) {
    if (_yearlyBilling) return null;
    final p = _productForTier(tier);
    if (p == null) return null;
    final offer = freeTrialOfferOf(p);
    if (offer == null) return null;
    if (_introEligible[p.id] == false) return null;
    return offer;
  }

  AppleFreeTrialOffer? get _selectedTrial => _trialForTier(_selectedTier);

  String? _priceLabelForTier(String tier) {
    final p = _productForTier(tier);
    if (p == null) return null;
    if (_yearlyBilling) return '${p.price}/年';
    final trial = _trialForTier(tier);
    if (trial != null) {
      return '免费试用 ${trial.days} 天，之后 ${p.price}/月';
    }
    return '${p.price}/月';
  }

  void _setBillingPeriod(bool yearly) {
    setState(() => _yearlyBilling = yearly);
  }

  List<String> _missingIdsForSelectedTier() {
    final ids = _tierIds;
    return [ids.monthly, ids.yearly]
        .where((id) => !_products.containsKey(id))
        .toList();
  }

  bool get _selectedTierProductsReady =>
      _productForTier(_selectedTier) != null;

  bool _isYearlyProduct(ProductDetails? p) {
    if (p == null) return false;
    final id = p.id.toLowerCase();
    return id.contains('year') || id.contains('annual');
  }

  String _subscribeLabel() {
    if (_busy && !_restoreFlow) return _phaseLabel;
    final p = _selected;
    if (p == null) return '选择方案';
    if (_isYearlyProduct(p)) return '订阅 ${p.price} / 年';
    final trial = _selectedTrial;
    if (trial != null) return '免费试用 ${trial.days} 天';
    return '订阅 ${p.price} / 月';
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
      AppToast.show(context, '${_tierDisplayName(_selectedTier)} 已开通');
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
                const _MembershipIntro(),
                const SizedBox(height: 16),
                if (_isIos)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        const Spacer(),
                        _BillingPeriodToggle(
                          yearly: _yearlyBilling,
                          enabled: !_busy &&
                              !_productsLoading &&
                              _error == null,
                          onChanged: _setBillingPeriod,
                        ),
                      ],
                    ),
                  ),
                _TierPlanCard(
                  title: '太子Pro',
                  tagline: '智能整理：不限收藏，解锁 AI',
                  priceLabel: _isIos && !_productsLoading && _error == null
                      ? _priceLabelForTier(UsagePlan.prince)
                      : null,
                  features: _princeFeatures(_quotas),
                  selected: _selectedTier == UsagePlan.prince,
                  onTap: () => _selectTier(UsagePlan.prince),
                ),
                const SizedBox(height: 10),
                _TierPlanCard(
                  title: '帝王Pro',
                  tagline: '深度加工：含太子Pro，另解锁脑图与转写',
                  priceLabel: _isIos && !_productsLoading && _error == null
                      ? _priceLabelForTier(UsagePlan.emperor)
                      : null,
                  features: _emperorFeatures(_quotas),
                  selected: _selectedTier == UsagePlan.emperor,
                  onTap: () => _selectTier(UsagePlan.emperor),
                ),
                const SizedBox(height: 8),
                Text(
                  '普通用户收藏上限 ${_quotas.free.itemLimit ?? 300} 条；额度按自然月重置',
                  style: const TextStyle(
                    fontSize: 12,
                    color: _muted,
                    height: 1.45,
                  ),
                ),
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
                ] else if (!_selectedTierProductsReady) ...[
                  const SizedBox(height: 16),
                  _TierProductsSyncHint(
                    tierLabel: _tierDisplayName(_selectedTier),
                    missingIds: _missingIdsForSelectedTier(),
                    onRetry: _busy ? null : _load,
                  ),
                ],
              ],
            ),
          ),
          _BottomActionBar(
            showPurchaseActions:
                _isIos && !_productsLoading && _error == null,
            subscribeLabel: _subscribeLabel(),
            restoreLabel: _busy && _restoreFlow ? _phaseLabel : '恢复购买',
            busy: _busy,
            restoreFlow: _restoreFlow,
            subscribeEnabled: _selected != null && _selectedTierProductsReady,
            trialOffer: _selectedTrial,
            selectedPrice: _selected?.price,
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

  void _selectTier(String tier) {
    setState(() => _selectedTier = tier);
  }

  List<_PlanFeature> _princeFeatures(PlanQuotasTable quotas) {
    return [
      const _PlanFeature('收藏不限条数', included: true),
      const _PlanFeature('AI 标签', included: true),
      const _PlanFeature('AI 解读', included: true),
      const _PlanFeature('AI 思维导图', included: false),
      const _PlanFeature('视频 / 音频转写', included: false),
      _PlanFeature(
        'AI 额度 ${formatAiCredits(quotas.prince.aiTokens)} 积分 / 月',
        included: true,
        isQuota: true,
      ),
    ];
  }

  List<_PlanFeature> _emperorFeatures(PlanQuotasTable quotas) {
    return [
      const _PlanFeature('含太子Pro全部权益', included: true),
      const _PlanFeature('AI 思维导图', included: true),
      const _PlanFeature('视频 / 音频转写', included: true),
      _PlanFeature(
        'AI 额度 ${formatAiCredits(quotas.emperor.aiTokens)} 积分 / 月',
        included: true,
        isQuota: true,
      ),
      _PlanFeature(
        '转写 ${quotas.emperor.transcriptMinutes} 分钟 / 月',
        included: true,
        isQuota: true,
      ),
    ];
  }

  void _openLegal({required String title, required String body}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SimpleDocPage(title: title, body: body),
      ),
    );
  }
}

class _BillingPeriodToggle extends StatelessWidget {
  const _BillingPeriodToggle({
    required this.yearly,
    required this.enabled,
    required this.onChanged,
  });

  final bool yearly;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _UpgradeProPageState._border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _BillingPeriodChip(
              label: '月付',
              selected: !yearly,
              enabled: enabled,
              onTap: () => onChanged(false),
            ),
            _BillingPeriodChip(
              label: '年付',
              selected: yearly,
              enabled: enabled,
              onTap: () => onChanged(true),
            ),
          ],
        ),
      ),
    );
  }
}

class _BillingPeriodChip extends StatelessWidget {
  const _BillingPeriodChip({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _UpgradeProPageState._accentSoft : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected
                  ? _UpgradeProPageState._accent
                  : _UpgradeProPageState._muted,
            ),
          ),
        ),
      ),
    );
  }
}

class _TierProductsSyncHint extends StatelessWidget {
  const _TierProductsSyncHint({
    required this.tierLabel,
    required this.missingIds,
    this.onRetry,
  });

  final String tierLabel;
  final List<String> missingIds;
  final VoidCallback? onRetry;

  static const _muted = Color(0xFF737A85);
  static const _accent = Color(0xFF2A6B52);

  @override
  Widget build(BuildContext context) {
    final ids = missingIds.isEmpty ? '（商品 id 未配置）' : missingIds.join('\n');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD8E4DE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$tierLabel 订阅商品尚未从 App Store 同步',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1F242E),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'ASC 新建订阅后，沙盒通常需数小时才能查到。'
            '请确认商品已「准备提交」、id 与后端一致，稍后点重试；'
            '太子Pro档不受影响，可先订阅太子Pro。',
            style: TextStyle(fontSize: 13, color: _muted, height: 1.45),
          ),
          if (missingIds.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              ids,
              style: const TextStyle(
                fontSize: 11,
                color: _muted,
                height: 1.35,
                fontFamily: 'Menlo',
              ),
            ),
          ],
          if (onRetry != null) ...[
            const SizedBox(height: 10),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: _accent,
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('重新拉取商品'),
            ),
          ],
        ],
      ),
    );
  }
}

class _MembershipIntro extends StatelessWidget {
  const _MembershipIntro();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
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
              right: -20,
              top: -28,
              child: Container(
                width: 120,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF8CD9B8).withValues(alpha: 0.2),
                ),
              ),
            ),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '订阅会员',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFC7EDDB),
                    height: 1.2,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '选一个适合你的档位，\n已生成的内容始终可查看。',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xC7FFFFFF),
                    height: 1.5,
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

class _PlanFeature {
  const _PlanFeature(this.label, {required this.included, this.isQuota = false});

  final String label;
  final bool included;
  final bool isQuota;
}

class _TierPlanCard extends StatelessWidget {
  const _TierPlanCard({
    required this.title,
    required this.tagline,
    required this.features,
    required this.selected,
    required this.onTap,
    this.priceLabel,
  });

  final String title;
  final String tagline;
  final List<_PlanFeature> features;
  final bool selected;
  final VoidCallback onTap;
  final String? priceLabel;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? _UpgradeProPageState._accentSoft
          : Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? _UpgradeProPageState._accent
                  : _UpgradeProPageState._border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: selected
                                ? _UpgradeProPageState._accent
                                : _UpgradeProPageState._text,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          tagline,
                          style: const TextStyle(
                            fontSize: 13,
                            color: _UpgradeProPageState._muted,
                            height: 1.4,
                          ),
                        ),
                        if (priceLabel != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            priceLabel!,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: selected
                                  ? _UpgradeProPageState._accent
                                  : _UpgradeProPageState._text,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  _TierRadioMark(selected: selected),
                ],
              ),
              const SizedBox(height: 14),
              ...features.map(
                (f) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _FeatureLine(feature: f),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureLine extends StatelessWidget {
  const _FeatureLine({required this.feature});

  final _PlanFeature feature;

  @override
  Widget build(BuildContext context) {
    final included = feature.included;
    final icon = included
        ? Icons.check_rounded
        : Icons.remove_rounded;
    final color = included
        ? (feature.isQuota
            ? _UpgradeProPageState._accent
            : _UpgradeProPageState._text)
        : _UpgradeProPageState._muted.withValues(alpha: 0.55);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            feature.label,
            style: TextStyle(
              fontSize: feature.isQuota ? 13 : 14,
              fontWeight: feature.isQuota ? FontWeight.w500 : FontWeight.w400,
              color: color,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

class _TierRadioMark extends StatelessWidget {
  const _TierRadioMark({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    const size = 22.0;
    if (!selected) {
      return Container(
        width: size,
        height: size,
        margin: const EdgeInsets.only(top: 2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFC7CCD4), width: 1.5),
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      margin: const EdgeInsets.only(top: 2),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: _UpgradeProPageState._accent,
      ),
      child: const Icon(Icons.check_rounded, size: 14, color: Colors.white),
    );
  }
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
                    color: const Color(0xFF2A6B52).withValues(alpha: 0.22),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: FilledButton(
          onPressed: canTap ? onPressed : null,
          style: FilledButton.styleFrom(
            backgroundColor: _UpgradeProPageState._accent,
            foregroundColor: Colors.white,
            disabledBackgroundColor: busy
                ? _UpgradeProPageState._accent
                : _UpgradeProPageState._accent.withValues(alpha: 0.5),
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
    this.trialOffer,
    this.selectedPrice,
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
  final AppleFreeTrialOffer? trialOffer;
  final String? selectedPrice;

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
                  trialOffer: trialOffer,
                  selectedPrice: selectedPrice,
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
    this.trialOffer,
    this.selectedPrice,
  });

  final VoidCallback onUserAgreement;
  final VoidCallback onPrivacy;
  final AppleFreeTrialOffer? trialOffer;
  final String? selectedPrice;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 12, color: Color(0xFF737A85), height: 1.55);
    const linkStyle = TextStyle(
      fontSize: 12,
      color: Color(0xFF2A6B52),
      height: 1.55,
    );
    final trial = trialOffer;
    final price = selectedPrice;
    final trialLead = trial != null && price != null
        ? '符合条件的用户可免费试用 ${trial.days} 天，试用结束后将按 $price/月自动扣费并续订。'
        : '';
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          if (trialLead.isNotEmpty) TextSpan(text: trialLead),
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
