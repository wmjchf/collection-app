class ItemAiEstimate {
  const ItemAiEstimate({
    required this.show,
    required this.estimateCredits,
  });

  final bool show;
  final int estimateCredits;

  factory ItemAiEstimate.fromJson(Map<String, dynamic> json) {
    return ItemAiEstimate(
      show: json['show'] == true,
      estimateCredits: (json['estimateCredits'] as num?)?.toInt() ?? 0,
    );
  }
}
