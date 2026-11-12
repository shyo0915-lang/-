import 'dart:async';
import 'dart:ui';

/// 指を約0.5秒止め、10px以上動かしたらキャンセルする長押し。
class HoldGesture {
  Timer? _timer;
  Offset? _origin;

  static const duration = Duration(milliseconds: 500);
  static const maxMovePixels = 10.0;

  bool get armed => _timer != null;

  void down(Offset point, void Function() onFire) {
    up();
    _origin = point;
    _timer = Timer(duration, () {
      _timer = null;
      if (_origin == null) return;
      _origin = null;
      onFire();
    });
  }

  void move(Offset point) {
    final origin = _origin;
    if (origin == null) return;
    final dx = point.dx - origin.dx;
    final dy = point.dy - origin.dy;
    if (dx * dx + dy * dy > maxMovePixels * maxMovePixels) up();
  }

  void up() {
    _timer?.cancel();
    _timer = null;
    _origin = null;
  }
}
