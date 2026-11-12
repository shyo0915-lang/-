import 'package:field_sales/logic/hold_gesture.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('指を離すと長押しは発火しない', () {
    var fired = 0;
    final hold = HoldGesture();
    hold.down(Offset.zero, () => fired++);
    expect(hold.armed, isTrue);
    hold.up();
    expect(fired, 0);
    expect(hold.armed, isFalse);
  });

  test('10pxを超えて動かすと長押しはキャンセル', () {
    var fired = 0;
    final hold = HoldGesture();
    hold.down(Offset.zero, () => fired++);
    hold.move(const Offset(11, 0));
    expect(hold.armed, isFalse);
    expect(fired, 0);
  });

  test('9pxの揺れでは長押しが残る', () async {
    var fired = 0;
    final hold = HoldGesture();
    hold.down(Offset.zero, () => fired++);
    hold.move(const Offset(9, 0));
    expect(hold.armed, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 520));
    expect(fired, 1);
  });
}
