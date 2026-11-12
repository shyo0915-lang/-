import 'dart:async';
import 'dart:js_interop';
import 'dart:ui';

import 'package:web/web.dart' as web;

import '../logic/hold_gesture.dart';

/// ブラウザの Google マップは長押しを右クリックとしてしか渡さない。
/// タッチを自分で計り、iPhone の拡大鏡や選択メニューも止める。
HoldBinding watchMapHold(void Function(Offset client) onHold) {
  final hold = HoldGesture();
  web.EventTarget? root;
  late final JSFunction onDown;
  late final JSFunction onMove;
  late final JSFunction onUp;
  late final JSFunction onContext;

  void cancel() => hold.up();

  void down(web.Event event) {
    if (event.isA<web.TouchEvent>() && (event as web.TouchEvent).touches.length > 1) {
      cancel();
      return;
    }
    final point = _clientPoint(event);
    if (point == null) return;
    hold.down(point, () => onHold(point));
  }

  void move(web.Event event) {
    if (event.isA<web.TouchEvent>() && (event as web.TouchEvent).touches.length > 1) {
      cancel();
      return;
    }
    final point = _clientPoint(event);
    if (point != null) hold.move(point);
  }

  onDown = down.toJS;
  onMove = move.toJS;
  onUp = ((web.Event _) => cancel()).toJS;
  onContext = ((web.Event event) => event.preventDefault()).toJS;

  void attach(web.EventTarget target) {
    for (final type in ['touchstart', 'mousedown']) {
      target.addEventListener(type, onDown, true.toJS);
    }
    for (final type in ['touchmove', 'mousemove']) {
      target.addEventListener(type, onMove, true.toJS);
    }
    for (final type in ['touchend', 'touchcancel', 'mouseup', 'wheel']) {
      target.addEventListener(type, onUp, true.toJS);
    }
    target.addEventListener('contextmenu', onContext, true.toJS);
  }

  void detach(web.EventTarget target) {
    for (final type in ['touchstart', 'mousedown']) {
      target.removeEventListener(type, onDown, true.toJS);
    }
    for (final type in ['touchmove', 'mousemove']) {
      target.removeEventListener(type, onMove, true.toJS);
    }
    for (final type in ['touchend', 'touchcancel', 'mouseup', 'wheel']) {
      target.removeEventListener(type, onUp, true.toJS);
    }
    target.removeEventListener('contextmenu', onContext, true.toJS);
  }

  bool tryAttach() {
    if (root != null) return true;
    final view = web.document.querySelector('flutter-view');
    final shadow = view?.shadowRoot;
    final next = web.document.querySelector('flt-platform-view') ??
        web.document.querySelector('.gm-style') ??
        shadow?.querySelector('flt-platform-view') ??
        shadow?.querySelector('.gm-style');
    if (next == null) return false;
    if (next.isA<web.HTMLElement>()) {
      final style = (next as web.HTMLElement).style;
      style.setProperty('-webkit-touch-callout', 'none');
      style.setProperty('-webkit-user-select', 'none');
      style.setProperty('user-select', 'none');
    }
    attach(next);
    root = next;
    return true;
  }

  final poll = Timer.periodic(const Duration(milliseconds: 300), (timer) {
    if (tryAttach()) timer.cancel();
  });
  tryAttach();

  return HoldBinding(() {
    poll.cancel();
    cancel();
    final current = root;
    if (current != null) detach(current);
  });
}

Offset? _clientPoint(web.Event event) {
  if (event.isA<web.TouchEvent>()) {
    final touchEvent = event as web.TouchEvent;
    final touches = touchEvent.touches.length > 0 ? touchEvent.touches : touchEvent.changedTouches;
    if (touches.length == 0) return null;
    final touch = touches.item(0);
    if (touch == null) return null;
    return Offset(touch.clientX, touch.clientY);
  }
  if (event.isA<web.MouseEvent>()) {
    final mouse = event as web.MouseEvent;
    if (mouse.button != 0) return null;
    return Offset(mouse.clientX.toDouble(), mouse.clientY.toDouble());
  }
  return null;
}

class HoldBinding {
  HoldBinding(this.dispose);
  final void Function() dispose;
}
