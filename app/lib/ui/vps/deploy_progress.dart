import 'dart:async';

import 'package:flutter/material.dart' hide Durations;

import '../../l10n/app_localizations.dart';
import '../../theme/theme.dart';
import '../../vps/vps_models.dart';
import '../widgets/widgets.dart';
import 'vps_common.dart';

/// Console lines kept in memory.
const int kConsoleMaxLines = 400;

/// Starts a VPS operation. [trustedHostKey] is null on the first run and set to the
/// fingerprint the user trusted after a host key change.
typedef DeployStart = Stream<DeployEvent> Function(String? trustedHostKey);

/// Final value of an operation, plus the SSH host key it was pinned to.
class DeployOutcome<T> {
  const DeployOutcome(this.value, this.hostKey);

  final T value;

  /// Fingerprint the operation ran with. Non-null only after the user trusted a new key.
  final String? hostKey;
}

/// Progress bar, current step and live console for one VPS operation. Used inline in the
/// deploy wizard and inside [showDeployProgressSheet].
///
/// Runs [start] once on mount. On a failure it shows the message with "Повторить" and
/// "Скопировать журнал". A changed host key opens the warning dialog first.
class DeployProgressView<T> extends StatefulWidget {
  const DeployProgressView({
    super.key,
    required this.start,
    required this.onDone,
    this.cancellable = false,
    this.onCancel,
    this.busy,
  });

  final DeployStart start;
  final ValueChanged<DeployOutcome<T>> onDone;

  /// Shows "Отмена" while running. The user confirms before [onCancel] runs.
  final bool cancellable;
  final VoidCallback? onCancel;

  /// Set to true while the operation runs, so the host can block dismissal.
  final ValueNotifier<bool>? busy;

  @override
  State<DeployProgressView<T>> createState() => _DeployProgressViewState<T>();
}

class _DeployProgressViewState<T> extends State<DeployProgressView<T>> {
  final List<String> _lines = <String>[];
  final ScrollController _scroll = ScrollController();
  StreamSubscription<DeployEvent>? _sub;
  double? _fraction;
  String _step = '';
  Object? _error;
  bool _running = false;
  String? _trusted;
  T? _value;
  bool _hasValue = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _run() {
    _sub?.cancel();
    _hasValue = false;
    _value = null;
    setState(() {
      _running = true;
      _error = null;
    });
    widget.busy?.value = true;
    _sub = widget.start(_trusted).listen(
          _onEvent,
          onError: _onError,
          onDone: _onStreamDone,
        );
  }

  void _onEvent(DeployEvent event) {
    if (!mounted) return;
    if (event is DeployProgress) {
      setState(() {
        _fraction = event.percent / 100;
        _step = event.stepRu;
      });
      _add(event.stepRu);
    } else if (event is DeployLog) {
      _add(event.line);
    } else if (event is DeployFinished<T>) {
      _value = event.value;
      _hasValue = true;
    }
  }

  void _onError(Object error, StackTrace stack) {
    if (!mounted) return;
    _add(error is VpsException ? error.messageRu : error.toString());
    if (error is HostKeyChangedException) {
      _askTrust(error);
      return;
    }
    _fail(error);
  }

  void _fail(Object error) {
    setState(() {
      _running = false;
      _error = error;
    });
    widget.busy?.value = false;
  }

  Future<void> _askTrust(HostKeyChangedException error) async {
    _fail(error);
    final trust = await showHostKeyChangedDialog(context, error);
    if (!mounted) return;
    if (trust) {
      _trusted = error.actual;
      _run();
    }
  }

  void _onStreamDone() {
    if (!mounted) return;
    if (_hasValue) {
      final value = _value as T;
      setState(() => _running = false);
      widget.busy?.value = false;
      widget.onDone(DeployOutcome<T>(value, _trusted));
    } else if (_error == null) {
      _fail(StateError('Операция завершилась без результата.'));
    }
  }

  void _add(String line) {
    setState(() {
      _lines.add(line);
      if (_lines.length > kConsoleMaxLines) {
        _lines.removeRange(0, _lines.length - kConsoleMaxLines);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _confirmCancel() async {
    final l = AppLocalizations.of(context);
    final ok = await confirmSheet(
      context,
      title: l.vpsCancelDeployTitle,
      text: l.vpsCancelDeployText,
      action: l.vpsCancelDeployAction,
      cancelLabel: l.vpsStay,
      destructive: true,
    );
    if (ok && mounted) widget.onCancel?.call();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.obs.colors;
    final error = _error;
    final percentText = _fraction == null ? '' : '${(_fraction! * 100).round()}%';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: _fraction,
            minHeight: 3,
            color: c.ember,
            backgroundColor: c.line,
          ),
        ),
        const SizedBox(height: Space.s12),
        Row(
          children: [
            Expanded(
              child: Text(
                _step.isEmpty ? l.vpsProgressTitle : _step,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.text),
              ),
            ),
            Text(percentText, style: context.obs.mono.copyWith(fontSize: 12, color: c.textDim)),
          ],
        ),
        const SizedBox(height: Space.s16),
        Text(l.vpsConsole, style: vpsBodyDim(context).copyWith(fontSize: 12)),
        const SizedBox(height: Space.s8),
        Container(
          height: 240,
          padding: const EdgeInsets.all(Space.s12),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(Radii.row),
            border: Border.all(color: c.line),
          ),
          child: SingleChildScrollView(
            controller: _scroll,
            child: SelectableText(
              _lines.join('\n'),
              style: context.obs.mono.copyWith(fontSize: 12, height: 1.45, color: c.textDim),
            ),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: Space.s16),
          Text(
            l.vpsFailed,
            style: TextStyle(color: c.danger, fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: Space.s4),
          Text(vpsErrorText(l, error), style: vpsBodyDim(context)),
          const SizedBox(height: Space.s16),
          ObsButton(label: l.vpsRetry, onPressed: _run),
          const SizedBox(height: Space.s8),
          ObsButton(
            label: l.vpsCopyLog,
            kind: ObsButtonKind.secondary,
            onPressed: () => copyText(context, _lines.join('\n'), l.vpsLogCopied),
          ),
        ],
        if (widget.cancellable && _running) ...[
          const SizedBox(height: Space.s16),
          ObsButton(
            label: l.vpsCancel,
            kind: ObsButtonKind.secondary,
            onPressed: _confirmCancel,
          ),
        ],
      ],
    );
  }
}

/// Runs a VPS operation in a sheet with [DeployProgressView]. Resolves to the outcome on
/// success, or to null when the sheet is closed. Errors stay in the sheet with a retry.
Future<DeployOutcome<T>?> showDeployProgressSheet<T>(
  BuildContext context, {
  required String title,
  required DeployStart start,
  bool cancellable = false,
}) {
  return showAdaptiveSheet<DeployOutcome<T>>(
    context,
    (ctx) => _DeployProgressSheet<T>(title: title, start: start, cancellable: cancellable),
  );
}

class _DeployProgressSheet<T> extends StatefulWidget {
  const _DeployProgressSheet({required this.title, required this.start, required this.cancellable});

  final String title;
  final DeployStart start;
  final bool cancellable;

  @override
  State<_DeployProgressSheet<T>> createState() => _DeployProgressSheetState<T>();
}

class _DeployProgressSheetState<T> extends State<_DeployProgressSheet<T>> {
  final ValueNotifier<bool> _busy = ValueNotifier<bool>(true);

  @override
  void dispose() {
    _busy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: _busy,
      builder: (context, busy, child) => PopScope(
        canPop: !busy,
        child: ObsSheet(
          title: widget.title,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (busy) Text(l.vpsSheetRunning, style: vpsBodyDim(context)),
              if (busy) const SizedBox(height: Space.s16),
              DeployProgressView<T>(
                start: widget.start,
                busy: _busy,
                cancellable: widget.cancellable,
                onCancel: () => Navigator.of(context).pop(),
                onDone: (outcome) => Navigator.of(context).pop(outcome),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
