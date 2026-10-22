import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Restores only the editor whose keyboard was open before an Android app switch.
/// Native code supplies window readiness; Flutter remains the owner of focus.
class KeyboardResumeScope extends StatefulWidget {
  const KeyboardResumeScope({super.key, required this.child});

  final Widget child;

  @override
  State<KeyboardResumeScope> createState() => _KeyboardResumeScopeState();
}

class _KeyboardResumeScopeState extends State<KeyboardResumeScope>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('com.yapchat.app/keyboard_resume');
  static _KeyboardResumeScopeState? _channelOwner;
  _ResumeEditor? _editor;
  int _generation = 0;
  bool _wasResumed = true;
  bool get _enabled =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    if (!_enabled) return;
    _wasResumed =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_focusChanged);
    _channelOwner = this;
    _channel.setMethodCallHandler(_handleNativeRequest);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _wasResumed = true;
      return;
    }
    if (!_wasResumed) return;
    _wasResumed = false;
    _generation++;
    final focus = FocusManager.instance.primaryFocus;
    final focusContext = focus?.context;
    final editor = focusContext?.findAncestorStateOfType<EditableTextState>();
    final view = focusContext == null ? null : View.maybeOf(focusContext);
    _editor =
        focus != null &&
            focus.hasFocus &&
            editor != null &&
            !editor.widget.readOnly &&
            editor.widget.keyboardType != TextInputType.none &&
            view != null &&
            view.viewInsets.bottom > 0
        ? _ResumeEditor(
            editor,
            focus,
            ModalRoute.of(focusContext!),
            view.viewId,
          )
        : null;
  }

  void _focusChanged() {
    if (_wasResumed &&
        _editor != null &&
        FocusManager.instance.primaryFocus != _editor!.focus) {
      _editor = null;
    }
  }

  Future<bool> _handleNativeRequest(MethodCall call) async {
    if (call.method != 'restoreFocusedInput') return false;
    final editor = _editor;
    _editor = null;
    if (editor == null) return false;
    final generation = _generation;
    final deadline = (call.arguments as Map?)?['deadlineMs'];
    if (deadline is! int) return false;
    // Android has regained its window focus, but Dart may still be processing
    // resumed/focus/route events. Revalidate after those have reached the frame.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted ||
        generation != _generation ||
        !_wasResumed ||
        DateTime.now().millisecondsSinceEpoch > deadline ||
        !editor.state.mounted ||
        !editor.focus.hasPrimaryFocus ||
        editor.state.widget.focusNode != editor.focus ||
        editor.state.widget.readOnly ||
        editor.state.widget.keyboardType == TextInputType.none ||
        editor.route?.isCurrent == false ||
        View.of(editor.state.context).viewId != editor.viewId) {
      return false;
    }
    editor.state.requestKeyboard();
    return true;
  }

  @override
  void dispose() {
    _generation++;
    _editor = null;
    WidgetsBinding.instance.removeObserver(this);
    FocusManager.instance.removeListener(_focusChanged);
    if (identical(_channelOwner, this)) {
      _channelOwner = null;
      _channel.setMethodCallHandler(null);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _ResumeEditor {
  const _ResumeEditor(this.state, this.focus, this.route, this.viewId);

  final EditableTextState state;
  final FocusNode focus;
  final ModalRoute<dynamic>? route;
  final int viewId;
}
