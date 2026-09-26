import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../core/theme/app_theme.dart';
import '../../ui/widgets.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _registerMode = true;
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _displayName = TextEditingController();
  bool _obscure = true;
  String? _localError;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _displayName.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _localError = null);
    final email = _email.text.trim();
    final password = _password.text;
    final name = _displayName.text.trim();

    if (email.isEmpty || !email.contains('@')) {
      setState(() => _localError = 'Enter a valid email.');
      return;
    }
    if (password.length < 8) {
      setState(() => _localError = 'Password must be at least 8 characters.');
      return;
    }
    if (_registerMode && name.isEmpty) {
      setState(() => _localError = 'Enter a display name for greetings.');
      return;
    }

    final state = context.read<AppState>();
    try {
      if (_registerMode) {
        await state.registerAccount(
          email: email,
          password: password,
          displayName: name,
        );
      } else {
        await state.loginAccount(email: email, password: password);
      }
    } catch (_) {
      // errorMessage set on AppState
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final error = _localError ?? state.errorMessage;

    return NightScaffold(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 24),
          Text(
            _registerMode ? 'Create your account' : 'Welcome back',
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            _registerMode
                ? 'Your name appears in greetings and syncs across devices.'
                : 'Sign in to restore your routine on this device.',
            style: const TextStyle(color: AppTheme.secondaryText),
          ),
          const SizedBox(height: 28),
          if (_registerMode) ...[
            TextField(
              controller: _displayName,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Display name',
                hintText: 'Zy',
              ),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Email',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: _obscure,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Password',
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 16),
            Text(
              error,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ],
          const SizedBox(height: 24),
          PrimaryButton(
            label: _registerMode ? 'Create account' : 'Sign in',
            busy: state.busy,
            onPressed: state.busy ? null : _submit,
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: state.busy
                ? null
                : () {
                    setState(() {
                      _registerMode = !_registerMode;
                      _localError = null;
                      state.clearMessages();
                    });
                  },
            child: Text(
              _registerMode
                  ? 'Already have an account? Sign in'
                  : 'Need an account? Register',
              style: const TextStyle(color: AppTheme.secondaryText),
            ),
          ),
        ],
      ),
    );
  }
}
