import 'dart:ui';

/// ネイティブでは地図ウィジェットの onLongPress を使う。
HoldBinding watchMapHold(void Function(Offset client) onHold) => HoldBinding(() {});

class HoldBinding {
  HoldBinding(this.dispose);
  final void Function() dispose;
}
