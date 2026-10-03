import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../core/theme/app_theme.dart';
import '../../ui/widgets.dart';

enum _AuthMode { signIn, register, forgot, reset }

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  _AuthMode _mode = _AuthMode.signIn;
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _displayName = TextEditingController();
  final _resetCode = TextEditingController();
  bool _obscure = true;
  bool _obscureConfirm = true;
  String? _localError;
  String? _localInfo;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _displayName.dispose();
    _resetCode.dispose();
    super.dispose();
  }

  bool _emailLooksValid(String email) {
    if (email.length < 5 || email.length > 320 || email.contains(' ')) {
      return false;
    }
    final at = email.indexOf('@');
    if (at <= 0 || at == email.length - 1) return false;
    final domain = email.substring(at + 1);
    return domain.contains('.');
  }

  void _setMode(_AuthMode mode) {
    final state = context.read<AppState>();
    setState(() {
      _mode = mode;
      _localError = null;
      _localInfo = null;
      _password.clear();
      _confirmPassword.clear();
      if (mode != _AuthMode.reset) {
        _resetCode.clear();
      }
      state.clearMessages();
    });
  }

  Future<void> _submit() async {
    setState(() {
      _localError = null;
      _localInfo = null;
    });
    final email = _email.text.trim();
    final password = _password.text;
    final confirm = _confirmPassword.text;
    final name = _displayName.text.trim();
    final code = _resetCode.text.trim();
    final state = context.read<AppState>();

    if (!_emailLooksValid(email)) {
      setState(() => _localError = 'Enter a valid email address.');
      return;
    }

    if (_mode == _AuthMode.forgot) {
      try {
        final devCode = await state.requestPasswordReset(email: email);
        if (!mounted) return;
        setState(() {
          _mode = _AuthMode.reset;
          _localInfo = state.infoMessage ??
              'If an account exists for that email, a reset code has been sent.';
          if (devCode != null && devCode.isNotEmpty) {
            _resetCode.text = devCode;
            _localInfo =
                '$_localInfo\n\nDev code (SMTP not required locally): $devCode';
          }
        });
      } catch (_) {}
      return;
    }

    if (_mode == _AuthMode.reset) {
      final digits = code.replaceAll(RegExp(r'\D'), '');
      if (digits.length != 6) {
        setState(() => _localError = 'Enter the 6-digit reset code from your email.');
        return;
      }
      if (password.length < 8) {
        setState(() => _localError = 'Password must be at least 8 characters.');
        return;
      }
      if (password != confirm) {
        setState(() => _localError = 'Passwords do not match.');
        return;
      }
      try {
        await state.resetPassword(email: email, code: digits, password: password);
        if (!mounted) return;
        _password.clear();
        _confirmPassword.clear();
        _resetCode.clear();
        setState(() {
          _mode = _AuthMode.signIn;
          _localInfo = state.infoMessage ?? 'Password updated. You can sign in now.';
        });
      } catch (_) {}
      return;
    }

    if (password.length < 8) {
      setState(() => _localError = 'Password must be at least 8 characters.');
      return;
    }

    if (_mode == _AuthMode.register) {
      if (name.isEmpty) {
        setState(() => _localError = 'Enter a display name for greetings.');
        return;
      }
      if (password != confirm) {
        setState(() => _localError = 'Passwords do not match.');
        return;
      }
    }

    try {
      if (_mode == _AuthMode.register) {
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

  String get _title => switch (_mode) {
        _AuthMode.signIn => 'Welcome back',
        _AuthMode.register => 'Create your account',
        _AuthMode.forgot => 'Forgot password',
        _AuthMode.reset => 'Choose a new password',
      };

  String get _subtitle => switch (_mode) {
        _AuthMode.signIn => 'Sign in to restore your routine on this device.',
        _AuthMode.register =>
          'Your name appears in greetings and syncs across devices.',
        _AuthMode.forgot =>
          'Enter your email and we will send a 6-digit reset code.',
        _AuthMode.reset =>
          'Enter the code from your email, then choose a new password.',
      };

  String get _primaryLabel => switch (_mode) {
        _AuthMode.signIn => 'Sign in',
        _AuthMode.register => 'Create account',
        _AuthMode.forgot => 'Send reset code',
        _AuthMode.reset => 'Update password',
      };

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final error = _localError ?? state.errorMessage;
    final info = _localInfo ??
        (_mode == _AuthMode.forgot || _mode == _AuthMode.reset
            ? state.infoMessage
            : null);
    final showPassword =
        _mode == _AuthMode.signIn ||
        _mode == _AuthMode.register ||
        _mode == _AuthMode.reset;
    final showConfirm =
        _mode == _AuthMode.register || _mode == _AuthMode.reset;

    return NightScaffold(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 24),
              Text(
                'Zy Sleep',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: AppTheme.accentSoft,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _title,
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                _subtitle,
                style: const TextStyle(color: AppTheme.secondaryText, height: 1.35),
              ),
              const SizedBox(height: 28),
              AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_mode == _AuthMode.register) ...[
                      TextField(
                        controller: _displayName,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.name],
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
                      enableSuggestions: false,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: 'Email',
                      ),
                    ),
                    if (_mode == _AuthMode.reset) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _resetCode,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        autofillHints: const [AutofillHints.oneTimeCode],
                        decoration: const InputDecoration(
                          labelText: 'Reset code',
                          hintText: '6-digit code',
                        ),
                      ),
                    ],
                    if (showPassword) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _password,
                        obscureText: _obscure,
                        textInputAction:
                            showConfirm ? TextInputAction.next : TextInputAction.done,
                        onSubmitted: showConfirm ? null : (_) => _submit(),
                        autofillHints: [
                          if (_mode == _AuthMode.register || _mode == _AuthMode.reset)
                            AutofillHints.newPassword
                          else
                            AutofillHints.password,
                        ],
                        decoration: InputDecoration(
                          labelText: _mode == _AuthMode.reset
                              ? 'New password'
                              : 'Password',
                          helperText: _mode == _AuthMode.signIn
                              ? null
                              : 'At least 8 characters',
                          suffixIcon: IconButton(
                            tooltip: _obscure ? 'Show password' : 'Hide password',
                            icon: Icon(
                              _obscure ? Icons.visibility_off : Icons.visibility,
                            ),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                      ),
                    ],
                    if (showConfirm) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _confirmPassword,
                        obscureText: _obscureConfirm,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submit(),
                        autofillHints: const [AutofillHints.newPassword],
                        decoration: InputDecoration(
                          labelText: 'Confirm password',
                          suffixIcon: IconButton(
                            tooltip: _obscureConfirm
                                ? 'Show password'
                                : 'Hide password',
                            icon: Icon(
                              _obscureConfirm
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            onPressed: () => setState(
                              () => _obscureConfirm = !_obscureConfirm,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (_mode == _AuthMode.signIn) ...[
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: state.busy
                        ? null
                        : () => _setMode(_AuthMode.forgot),
                    child: const Text(
                      'Forgot password?',
                      style: TextStyle(color: AppTheme.secondaryText),
                    ),
                  ),
                ),
              ] else
                const SizedBox(height: 8),
              if (info != null) ...[
                const SizedBox(height: 8),
                Text(
                  info,
                  style: const TextStyle(
                    color: AppTheme.accentSoft,
                    height: 1.35,
                  ),
                ),
              ],
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(
                  error,
                  style: const TextStyle(
                    color: AppTheme.destructive,
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              PrimaryButton(
                label: _primaryLabel,
                busy: state.busy,
                onPressed: state.busy ? null : _submit,
              ),
              const SizedBox(height: 12),
              ..._footerActions(state.busy),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _footerActions(bool busy) {
    switch (_mode) {
      case _AuthMode.signIn:
        return [
          TextButton(
            onPressed: busy ? null : () => _setMode(_AuthMode.register),
            child: const Text(
              'Need an account? Register',
              style: TextStyle(color: AppTheme.secondaryText),
            ),
          ),
        ];
      case _AuthMode.register:
        return [
          TextButton(
            onPressed: busy ? null : () => _setMode(_AuthMode.signIn),
            child: const Text(
              'Already have an account? Sign in',
              style: TextStyle(color: AppTheme.secondaryText),
            ),
          ),
        ];
      case _AuthMode.forgot:
        return [
          TextButton(
            onPressed: busy ? null : () => _setMode(_AuthMode.signIn),
            child: const Text(
              'Back to sign in',
              style: TextStyle(color: AppTheme.secondaryText),
            ),
          ),
        ];
      case _AuthMode.reset:
        return [
          TextButton(
            onPressed: busy ? null : () => _setMode(_AuthMode.forgot),
            child: const Text(
              'Resend code',
              style: TextStyle(color: AppTheme.secondaryText),
            ),
          ),
          TextButton(
            onPressed: busy ? null : () => _setMode(_AuthMode.signIn),
            child: const Text(
              'Back to sign in',
              style: TextStyle(color: AppTheme.secondaryText),
            ),
          ),
        ];
    }
  }
}
