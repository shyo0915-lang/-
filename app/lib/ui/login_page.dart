import 'package:flutter/material.dart';

import '../state/app_state.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.state});
  final AppState state;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _org = TextEditingController();
  var _signUp = false;
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    _org.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 24),
            const Text('顧客マップ', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text('社内の顧客台帳にログインします。最初の登録者がその会社の管理者になります。', style: TextStyle(fontSize: 16, height: 1.4)),
            const SizedBox(height: 24),
            TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'メールアドレス'), style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 12),
            TextField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'パスワード'), style: const TextStyle(fontSize: 18)),
            if (_signUp) ...[
              const SizedBox(height: 12),
              TextField(controller: _name, decoration: const InputDecoration(labelText: '表示名'), style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 12),
              TextField(controller: _org, decoration: const InputDecoration(labelText: '会社名'), style: const TextStyle(fontSize: 18)),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 15)),
            ],
            const SizedBox(height: 20),
            SizedBox(
              height: 56,
              child: FilledButton(
                onPressed: _busy ? null : _submit,
                child: Text(_signUp ? '登録してはじめる' : 'ログイン', style: const TextStyle(fontSize: 18)),
              ),
            ),
            TextButton(onPressed: () => setState(() => _signUp = !_signUp), child: Text(_signUp ? 'ログインに戻る' : '新しく会社を登録')),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = _signUp
        ? await widget.state.repo.signUp(email: _email.text, password: _password.text, displayName: _name.text, orgName: _org.text)
        : await widget.state.repo.signIn(_email.text, _password.text);
    if (error == null) {
      await widget.state.bootstrap();
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
  }
}
