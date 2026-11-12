import 'package:flutter/material.dart';

import '../logic/validators.dart';
import '../state/app_state.dart';
import 'back_button.dart';
import 'edit_form.dart';

class NewCustomerPage extends StatefulWidget {
  const NewCustomerPage({super.key, required this.state});
  final AppState state;

  @override
  State<NewCustomerPage> createState() => _NewCustomerPageState();
}

class _NewCustomerPageState extends State<NewCustomerPage> {
  CustomerDraft? _live;
  var _saving = false;

  AppState get app => widget.state;
  CustomerDraft get _draft => _live ?? app.drop!.draft;

  @override
  Widget build(BuildContext context) {
    final drop = app.drop;
    if (drop == null) {
      return const Scaffold(body: SizedBox.shrink());
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: largeBackBar('新規登録', _leave, label: '地図へ'),
        body: CustomerEditForm(
          initial: drop.draft,
          statuses: app.statuses,
          onChanged: (draft) => _live = draft,
          onSave: _save,
        ),
      ),
    );
  }

  Future<void> _save(CustomerDraft draft) async {
    if (_saving) return;
    setState(() => _saving = true);
    final created = await app.createCustomer(draft.copyWith(lat: app.drop?.lat, lng: app.drop?.lng, locationSource: 'manual'));
    if (!mounted) return;
    setState(() => _saving = false);
    if (created == null) return;
    app.clearDrop();
    Navigator.of(context).pop(true);
  }

  Future<void> _leave() async {
    final choice = await app.choose?.call('この場所の登録', ['保存する', '下書きを残して地図へ', '破棄してピンを消す']);
    if (!mounted || choice == null) return;
    if (choice == 0) {
      await _save(_draft);
      return;
    }
    if (choice == 1) {
      final drop = app.drop;
      if (drop != null) app.setDrop(drop.copyWith(draft: _draft));
      Navigator.of(context).pop(false);
      return;
    }
    app.clearDrop();
    Navigator.of(context).pop(false);
  }
}
