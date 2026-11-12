import 'package:flutter/material.dart';

import '../models/models.dart';
import '../state/app_state.dart';

Future<void> showShareSheet(BuildContext context, AppState app, Customer customer) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _ShareSheet(app: app, customer: customer),
  );
}

class _ShareSheet extends StatefulWidget {
  const _ShareSheet({required this.app, required this.customer});
  final AppState app;
  final Customer customer;

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  List<CustomerShare> _shares = const [];
  List<OrgMember> _members = const [];
  String _role = 'viewer';
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final shares = await widget.app.repo.loadShares(widget.customer.id);
    final members = await widget.app.repo.loadMembers();
    if (!mounted) return;
    setState(() {
      _shares = shares;
      _members = members.where((member) => member.id != widget.app.repo.session?.userId && member.active).toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: _loading
            ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back, size: 26),
                        label: const Text('顧客情報へ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                        style: TextButton.styleFrom(minimumSize: const Size(48, 56)),
                      ),
                      const Spacer(),
                      const Text('共有', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('同じ会社の人だけを招待できます。初期の役割は閲覧者です。', style: TextStyle(fontSize: 14)),
                  const SizedBox(height: 12),
                  if (_shares.isEmpty) const Text('まだ共有していません'),
                  for (final share in _shares)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(share.userName, style: const TextStyle(fontSize: 17)),
                      subtitle: Text(share.role == 'editor' ? '編集者' : '閲覧者'),
                      trailing: IconButton(
                        tooltip: '解除',
                        onPressed: () async {
                          await widget.app.repo.revokeShare(widget.customer.id, share.userId);
                          await _load();
                        },
                        icon: const Icon(Icons.close),
                      ),
                    ),
                  const Divider(),
                  DropdownButtonFormField<String>(
                    initialValue: _role,
                    decoration: const InputDecoration(labelText: '役割'),
                    items: const [
                      DropdownMenuItem(value: 'viewer', child: Text('閲覧者')),
                      DropdownMenuItem(value: 'editor', child: Text('編集者')),
                    ],
                    onChanged: (value) => setState(() => _role = value ?? 'viewer'),
                  ),
                  const SizedBox(height: 8),
                  ..._members.map(
                    (member) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(member.displayName, style: const TextStyle(fontSize: 17)),
                      subtitle: Text(member.role == 'admin' ? '管理者' : '担当者'),
                      trailing: FilledButton(
                        onPressed: () async {
                          final error = await widget.app.repo.invite(
                            customerId: widget.customer.id,
                            userId: member.id,
                            role: _role,
                          );
                          if (error != null && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
                          }
                          await _load();
                        },
                        child: const Text('招待'),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
