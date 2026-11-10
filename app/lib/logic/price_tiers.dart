class PriceTierConfig {
  const PriceTierConfig(this.boundaries, {this.personal = false});

  /// 昇順の境界。段階数は boundaries.length + 1（2〜5段階）。
  final List<int> boundaries;
  final bool personal;

  int get tierCount => boundaries.length + 1;

  int tierOf(int price) {
    for (var i = 0; i < boundaries.length; i++) {
      if (price < boundaries[i]) return i;
    }
    return boundaries.length;
  }

  String? validate() {
    if (boundaries.isEmpty || boundaries.length > 4) {
      return '単価帯は2〜5段階にしてください';
    }
    for (var i = 0; i < boundaries.length; i++) {
      if (boundaries[i] < 1) return '境界は1円以上にしてください';
      if (i > 0 && boundaries[i] <= boundaries[i - 1]) {
        return '境界は小さい順に入力してください';
      }
    }
    return null;
  }

  static const PriceTierConfig defaults = PriceTierConfig([50000, 200000]);
}

double pinDiameterForTier(int tier) {
  const sizes = [28.0, 32.0, 36.0, 40.0, 44.0];
  final index = tier.clamp(0, sizes.length - 1);
  return sizes[index];
}
