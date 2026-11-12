import 'package:flutter/material.dart';

/// ホーム画面のPWAにはブラウザの戻るがないので、左上に大きく置く。
class LargeBackButton extends StatelessWidget {
  const LargeBackButton({super.key, required this.onPressed, this.label = '戻る'});

  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.arrow_back, size: 26),
      label: Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 56),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
    );
  }
}

AppBar largeBackBar(String title, VoidCallback onPressed, {String label = '戻る', List<Widget>? actions}) {
  return AppBar(
    automaticallyImplyLeading: false,
    leadingWidth: 148,
    leading: LargeBackButton(onPressed: onPressed, label: label),
    title: Text(title, style: const TextStyle(fontSize: 18)),
    actions: actions,
  );
}
