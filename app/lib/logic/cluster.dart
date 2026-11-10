class PinPos {
  const PinPos(this.id, this.x, this.y);
  final String id;
  final double x;
  final double y;
}

class PinCluster {
  const PinCluster(this.ids, this.x, this.y);
  final List<String> ids;
  final double x;
  final double y;
  bool get isCluster => ids.length > 1;
}

List<PinCluster> clusterPins(List<PinPos> pins, {double radius = 48}) {
  final pending = [...pins];
  final clusters = <PinCluster>[];
  while (pending.isNotEmpty) {
    final seed = pending.removeAt(0);
    final group = <PinPos>[seed];
    pending.removeWhere((pin) {
      final dx = pin.x - seed.x;
      final dy = pin.y - seed.y;
      if (dx * dx + dy * dy <= radius * radius) {
        group.add(pin);
        return true;
      }
      return false;
    });
    final x = group.fold<double>(0, (sum, pin) => sum + pin.x) / group.length;
    final y = group.fold<double>(0, (sum, pin) => sum + pin.y) / group.length;
    clusters.add(PinCluster(group.map((pin) => pin.id).toList(), x, y));
  }
  return clusters;
}
