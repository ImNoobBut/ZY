import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/greeting.dart';
import '../../ui/widgets.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  /// Quick picks: short minutes + a few longer sleep lengths.
  static const presets = [15, 30, 45, 60, 90, 120, 180, 480];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final active = state.routineState == RoutineState.timerRunning;
    final remaining = state.remaining();
    final currentMinutes = state.preferences.defaultSleepTimerSeconds ~/ 60;
    final spotifyConnected = state.spotify.isAuthenticated;
    final hasSelection = state.preferences.hasSpotifySelection;
    final musicLabel = active
        ? state.musicLabel
        : (!spotifyConnected
            ? 'Connect Spotify'
            : (hasSelection
                ? (state.preferences.spotifySelectionLabel ?? 'Spotify')
                : 'Current Spotify playback'));
    final headline = active
        ? 'Sleep timer running'
        : greetingFor(DateTime.now(), state.preferences.displayName);

    return NightScaffold(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            headline,
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            active
                ? 'Spotify will pause when the timer ends.'
                : 'Set a timer. Use what is already playing on Spotify, or pick tracks in the app.',
            style: const TextStyle(color: AppTheme.secondaryText),
          ),
          const SizedBox(height: 20),
          ZyCard(
            child: Column(
              children: [
                InkWell(
                  onTap: () => Navigator.of(context).pushNamed('/spotify'),
                  child: _row('Music', musicLabel),
                ),
                _row(
                  active ? 'Music stops in' : 'Sleep timer',
                  active ? _fmt(remaining) : formatSleepTimerMinutes(currentMinutes),
                ),
              ],
            ),
          ),
          if (!active) ...[
            const SizedBox(height: 20),
            const Text(
              'Timer length',
              style: TextStyle(color: AppTheme.secondaryText),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in presets)
                  ChoiceChip(
                    label: Text(formatSleepTimerMinutes(m)),
                    selected: currentMinutes == m,
                    onSelected: (_) => state.setDefaultTimerMinutes(m),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _CustomTimerCard(currentMinutes: currentMinutes),
          ],
          const SizedBox(height: 20),
          PrimaryButton(
            label: active ? 'Stop timer' : 'Start timer',
            busy: state.busy,
            onPressed: () async {
              if (active) {
                await state.endRoutine();
              } else {
                await state.startRoutine();
              }
            },
          ),
          if (!spotifyConnected) ...[
            const SizedBox(height: 8),
            SecondaryButton(
              label: 'Connect Spotify',
              onPressed: () => Navigator.of(context).pushNamed('/spotify'),
            ),
          ] else if (!hasSelection) ...[
            const SizedBox(height: 8),
            SecondaryButton(
              label: 'Optional: choose tracks',
              onPressed: () => Navigator.of(context).pushNamed('/spotify'),
            ),
          ],
          if (state.errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(state.errorMessage!, style: const TextStyle(color: AppTheme.destructive)),
          ],
          if (state.infoMessage != null) ...[
            const SizedBox(height: 12),
            Text(state.infoMessage!, style: const TextStyle(color: AppTheme.secondaryText)),
          ],
          const SizedBox(height: 16),
          const Text(
            'Keep the app available so the timer can pause Spotify when time is up. '
            'Spotify Premium and an active device are required for playback.',
            style: TextStyle(color: AppTheme.tertiaryText, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _row(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Text(title, style: const TextStyle(color: AppTheme.secondaryText)),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(Duration? d) {
    if (d == null) return '—';
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }
}

class _CustomTimerCard extends StatefulWidget {
  const _CustomTimerCard({required this.currentMinutes});

  final int currentMinutes;

  @override
  State<_CustomTimerCard> createState() => _CustomTimerCardState();
}

class _CustomTimerCardState extends State<_CustomTimerCard> {
  late final TextEditingController _controller;
  final _focusNode = FocusNode();
  String? _previewLabel;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      setState(() {
        _previewLabel = null;
        _errorText = null;
      });
    }
  }

  void _onTypeChanged(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _previewLabel = null;
        _errorText = null;
      });
      return;
    }
    final parsed = parseSleepTimerInput(trimmed);
    setState(() {
      if (parsed == null) {
        _previewLabel = null;
        _errorText = 'Try 90, 2h, or 2:30';
      } else {
        _previewLabel = formatSleepTimerMinutes(parsed);
        _errorText = null;
      }
    });
  }

  Future<void> _nudge(AppState state, int deltaMinutes) async {
    await state.setDefaultTimerMinutes(widget.currentMinutes + deltaMinutes);
  }

  Future<void> _applyTyped(AppState state) async {
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty) return;
    final parsed = parseSleepTimerInput(trimmed);
    if (parsed == null) {
      setState(() {
        _errorText = 'Try 90, 2h, or 2:30';
        _previewLabel = null;
      });
      return;
    }
    await state.setDefaultTimerMinutes(parsed);
    if (!mounted) return;
    _controller.clear();
    setState(() {
      _previewLabel = null;
      _errorText = null;
    });
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final hours = widget.currentMinutes ~/ 60;
    final minutes = widget.currentMinutes % 60;
    final label = formatSleepTimerMinutes(widget.currentMinutes);
    final atMin = widget.currentMinutes <= 1;
    final atMax = widget.currentMinutes >= kMaxSleepTimerMinutes;

    return ZyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Custom',
                style: TextStyle(color: AppTheme.secondaryText),
              ),
              const Spacer(),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Up to 24 hours',
            style: const TextStyle(color: AppTheme.tertiaryText, fontSize: 13),
          ),
          Slider(
            value: widget.currentMinutes.toDouble().clamp(1, 180),
            min: 1,
            max: 180,
            divisions: 179,
            onChanged: (v) => state.setDefaultTimerMinutes(v.round()),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: _StepperColumn(
                  label: 'Hours',
                  valueLabel: '$hours',
                  onMinus: atMin || hours == 0
                      ? null
                      : () => _nudge(state, -60),
                  onPlus: atMax ? null : () => _nudge(state, 60),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StepperColumn(
                  label: 'Minutes',
                  valueLabel: minutes.toString().padLeft(2, '0'),
                  onMinus: atMin ? null : () => _nudge(state, -5),
                  onPlus: atMax ? null : () => _nudge(state, 5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Or type a time',
            style: TextStyle(color: AppTheme.secondaryText, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.done,
                  style: const TextStyle(color: AppTheme.primaryText),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9hHmM:.\s]')),
                  ],
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'e.g. 2h 30 or 2:30',
                    hintStyle: const TextStyle(color: AppTheme.tertiaryText),
                    filled: true,
                    fillColor: const Color(0x14FFFFFF),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    errorText: _errorText,
                    errorStyle: const TextStyle(
                      color: AppTheme.destructive,
                      fontSize: 12,
                    ),
                  ),
                  onChanged: _onTypeChanged,
                  onSubmitted: (_) => _applyTyped(state),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => _applyTyped(state),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: AppTheme.primaryText,
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Use'),
              ),
            ],
          ),
          if (_previewLabel != null) ...[
            const SizedBox(height: 8),
            Text(
              'Will set: $_previewLabel',
              style: const TextStyle(
                color: AppTheme.accentSoft,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StepperColumn extends StatelessWidget {
  const _StepperColumn({
    required this.label,
    required this.valueLabel,
    required this.onMinus,
    required this.onPlus,
  });

  final String label;
  final String valueLabel;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(color: AppTheme.tertiaryText, fontSize: 12),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _RoundIconButton(
              icon: Icons.remove,
              onPressed: onMinus,
            ),
            Expanded(
              child: Text(
                valueLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            _RoundIconButton(
              icon: Icons.add,
              onPressed: onPlus,
            ),
          ],
        ),
      ],
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.onPressed,
  });

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x22FFFFFF),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            icon,
            size: 20,
            color: onPressed == null
                ? AppTheme.tertiaryText
                : AppTheme.primaryText,
          ),
        ),
      ),
    );
  }
}
