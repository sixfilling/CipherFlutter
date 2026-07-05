import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import 'cipher_engine.dart';

const _appTitle = 'Cipher';
const _appVersion = '3.0.0';
const _githubUrl = 'https://github.com/sixfilling';
const _mitLicense = '''
MIT License

Copyright (c) 2026 SixFilling

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
''';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(<String>[_appTitle], _mitLicense);
  });

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(854, 480),
      center: true,
      backgroundColor: Color(0xFF182230),
      title: _appTitle,
    );
    windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.setMinimumSize(const Size(854, 480));
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(const CipherApp());
}

class CipherApp extends StatefulWidget {
  const CipherApp({super.key});

  @override
  State<CipherApp> createState() => _CipherAppState();
}

class _CipherAppState extends State<CipherApp> {
  static const _darkKey = 'dark_mode';

  bool _dark = true;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _dark = prefs.getBool(_darkKey) ?? true);
  }

  Future<void> _setDark(bool value) async {
    setState(() => _dark = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_darkKey, value);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: _appTitle,
      themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: CipherHome(dark: _dark, onDarkChanged: _setDark),
    );
  }

  ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF1A73E8),
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      visualDensity: VisualDensity.standard,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

enum CipherMode { encrypt, decrypt }

class CipherHome extends StatefulWidget {
  const CipherHome({
    required this.dark,
    required this.onDarkChanged,
    super.key,
  });

  final bool dark;
  final ValueChanged<bool> onDarkChanged;

  @override
  State<CipherHome> createState() => _CipherHomeState();
}

class _CipherHomeState extends State<CipherHome>
    with SingleTickerProviderStateMixin {
  static const _generatedTokenLength = 24;
  static const _lower = 'abcdefghijklmnopqrstuvwxyz';
  static const _upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const _digits = '0123456789';
  static const _symbols = '!@#\$%^&*()-_=+[]{};:,.?';

  final _rng = Random.secure();
  final _tokenController = TextEditingController();
  final _inputController = TextEditingController();
  final _outputController = TextEditingController();

  CipherMode _mode = CipherMode.encrypt;
  String _activeToken = '';
  String _status = 'Choose mode. Set a secret token. Then type or paste.';
  bool _showToken = false;
  bool _autoCopyEncrypted = false;
  bool _busy = false;
  bool _syncingText = false;
  bool _showFps = false;
  int _versionTapCount = 0;
  int _fpsFrames = 0;
  double _fps = 0;
  Duration? _fpsWindowStart;
  Ticker? _fpsTicker;
  Timer? _debounce;
  int _job = 0;

  @override
  void initState() {
    super.initState();
    _inputController.addListener(_onInputChanged);
    _fpsTicker = createTicker(_onFpsTick);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _fpsTicker?.dispose();
    _tokenController.dispose();
    _inputController.dispose();
    _outputController.dispose();
    super.dispose();
  }

  void _onInputChanged() {
    if (_syncingText) return;
    final text = _inputController.text;
    if (text.trim().isEmpty) {
      _debounce?.cancel();
      _setTextSilently(_outputController, '');
      setState(() => _status = 'Cleared.');
      return;
    }
    _scheduleRun();
  }

  void _scheduleRun() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _runSelectedMode);
  }

  void _setToken() {
    final token = _tokenController.text.trim();
    setState(() {
      _activeToken = token;
      if (token.isEmpty) {
        _status = 'Token cleared.';
      } else if (token.length < 16) {
        _status =
            'Token set, but it is short. Use Generate for better security.';
      } else {
        _status = 'Token set.';
      }
    });
    _refreshCurrentText();
  }

  void _generateToken() {
    final chars = <String>[
      _randomChar(_lower),
      _randomChar(_upper),
      _randomChar(_digits),
      _randomChar(_symbols),
      ...List<String>.generate(
        _generatedTokenLength - 4,
        (_) => _randomChar(_lower + _upper + _digits + _symbols),
      ),
    ]..shuffle(_rng);

    final token = chars.join();
    setState(() {
      _tokenController.text = token;
      _activeToken = token;
      _status = 'Generated strong token. Store it safely.';
    });
    _refreshCurrentText();
  }

  String _randomChar(String source) => source[_rng.nextInt(source.length)];

  void _refreshCurrentText() {
    if (_inputController.text.trim().isNotEmpty) {
      _scheduleRun();
    }
  }

  Future<void> _runSelectedMode() async {
    if (_activeToken.isEmpty) {
      setState(() => _status = 'Set token first.');
      return;
    }
    final sourceText = _inputController.text;
    if (sourceText.trim().isEmpty) return;

    final job = ++_job;
    setState(() => _busy = true);

    try {
      final result = _mode == CipherMode.encrypt
          ? await CipherEngine.encrypt(_activeToken, sourceText)
          : await CipherEngine.decrypt(_activeToken, sourceText);

      if (!mounted || job != _job) return;

      _setTextSilently(_outputController, result);

      if (_mode == CipherMode.encrypt && _autoCopyEncrypted) {
        await Clipboard.setData(ClipboardData(text: result));
        setState(() => _status = 'Encrypted and copied.');
      } else {
        setState(
          () => _status = _mode == CipherMode.encrypt
              ? 'Encrypted.'
              : 'Decrypted.',
        );
      }
    } catch (_) {
      if (!mounted || job != _job) return;
      _setTextSilently(
        _outputController,
        _mode == CipherMode.decrypt
            ? 'Wrong token or bad ciphertext.'
            : 'Encryption failed.',
      );
      setState(() => _status = 'Failed.');
    } finally {
      if (mounted && job == _job) setState(() => _busy = false);
    }
  }

  void _setTextSilently(TextEditingController controller, String value) {
    _syncingText = true;
    controller.text = value;
    _syncingText = false;
  }

  Future<void> _pasteInput() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.trim().isEmpty) {
      setState(() => _status = 'Clipboard has no text.');
      return;
    }
    _inputController.text = text;
    setState(
      () => _status = _mode == CipherMode.encrypt
          ? 'Pasted normal text.'
          : 'Pasted ciphertext.',
    );
  }

  Future<void> _copyOutput() async {
    final text = _outputController.text;
    if (text.trim().isEmpty) {
      setState(() => _status = 'No result to copy.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    setState(() => _status = 'Copied result.');
  }

  void _clear() {
    _debounce?.cancel();
    _syncingText = true;
    _inputController.clear();
    _outputController.clear();
    _syncingText = false;
    setState(() {
      _status = 'Cleared.';
    });
  }

  Future<void> _open(Uri uri) async {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _onFpsTick(Duration elapsed) {
    if (!_showFps) return;

    final windowStart = _fpsWindowStart;
    if (windowStart == null) {
      _fpsWindowStart = elapsed;
      _fpsFrames = 0;
      return;
    }

    _fpsFrames++;
    final window = elapsed - windowStart;
    if (window >= const Duration(seconds: 1)) {
      final fps =
          _fpsFrames * Duration.microsecondsPerSecond / window.inMicroseconds;
      if (mounted) {
        setState(() => _fps = fps);
      }
      _fpsFrames = 0;
      _fpsWindowStart = elapsed;
    }
  }

  void _enableFpsOverlay(BuildContext dialogContext) {
    setState(() {
      _showFps = true;
      _fps = 0;
      _fpsFrames = 0;
      _fpsWindowStart = null;
    });
    if (!(_fpsTicker?.isActive ?? false)) {
      _fpsTicker?.start();
    }
    Navigator.of(dialogContext).maybePop();
  }

  void _handleVersionTap(BuildContext dialogContext) {
    _versionTapCount++;
    if (_versionTapCount >= 7) {
      _versionTapCount = 0;
      _enableFpsOverlay(dialogContext);
    }
  }

  Color _invert(Color color) {
    int channel(double value) => (value * 255).round().clamp(0, 255);

    return Color.fromARGB(
      channel(color.a),
      255 - channel(color.r),
      255 - channel(color.g),
      255 - channel(color.b),
    );
  }

  void _showAbout() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final textTheme = Theme.of(dialogContext).textTheme;
        final scheme = Theme.of(dialogContext).colorScheme;

        return AlertDialog(
          icon: Icon(Icons.lock_rounded, color: scheme.primary),
          title: const Text(_appTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _handleVersionTap(dialogContext),
                child: Text(_appVersion, style: textTheme.bodyMedium),
              ),
              const SizedBox(height: 12),
              const Text('MIT License'),
              const SizedBox(height: 12),
              const Text('Made by SixFilling'),
              TextButton.icon(
                onPressed: () => _open(Uri.parse(_githubUrl)),
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('GitHub'),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                showLicensePage(
                  context: dialogContext,
                  applicationName: _appTitle,
                  applicationVersion: _appVersion,
                  applicationLegalese: 'MIT License',
                );
              },
              child: const Text('Licenses'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final appSurfaceColor = widget.dark
        ? const Color(0xFF182230)
        : const Color(0xFFEAF3FF);
    return Scaffold(
      backgroundColor: appSurfaceColor,
      body: Stack(
        children: <Widget>[
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: appSurfaceColor,
                    border: Border.all(color: appSurfaceColor),
                  ),
                  child: Column(
                    children: <Widget>[
                      _Header(
                        status: _status,
                        busy: _busy,
                        dark: widget.dark,
                        onDarkChanged: widget.onDarkChanged,
                        onAbout: _showAbout,
                      ),
                      _Controls(
                        tokenController: _tokenController,
                        showToken: _showToken,
                        onShowTokenChanged: () =>
                            setState(() => _showToken = !_showToken),
                        onSetToken: _setToken,
                        onGenerateToken: _generateToken,
                        mode: _mode,
                        onModeChanged: (mode) {
                          setState(() => _mode = mode);
                          _refreshCurrentText();
                        },
                        autoCopyEncrypted: _autoCopyEncrypted,
                        onAutoCopyChanged: (value) =>
                            setState(() => _autoCopyEncrypted = value),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final inputPanel = _TextPanel(
                                label: _mode == CipherMode.encrypt
                                    ? 'Normal text'
                                    : 'Ciphertext',
                                icon: _mode == CipherMode.encrypt
                                    ? Icons.notes_rounded
                                    : Icons.lock_rounded,
                                controller: _inputController,
                                hint: _mode == CipherMode.encrypt
                                    ? 'Type normal text here'
                                    : 'Paste ciphertext here',
                              );
                              final outputPanel = _TextPanel(
                                label: _mode == CipherMode.encrypt
                                    ? 'Ciphertext'
                                    : 'Normal text',
                                icon: _mode == CipherMode.encrypt
                                    ? Icons.lock_rounded
                                    : Icons.notes_rounded,
                                controller: _outputController,
                                hint: 'Output appears here',
                                readOnly: true,
                              );

                              if (constraints.maxWidth >= 760) {
                                return Row(
                                  children: <Widget>[
                                    Expanded(child: inputPanel),
                                    const SizedBox(width: 12),
                                    Expanded(child: outputPanel),
                                  ],
                                );
                              }
                              return Column(
                                children: <Widget>[
                                  Expanded(child: inputPanel),
                                  const SizedBox(height: 12),
                                  Expanded(child: outputPanel),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                      _Actions(
                        canCopy: _outputController.text.trim().isNotEmpty,
                        onPaste: _pasteInput,
                        onCopy: _copyOutput,
                        onClear: _clear,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_showFps)
            Positioned(
              left: 8,
              top: 8,
              child: IgnorePointer(
                child: Text(
                  '${_fps.toStringAsFixed(0)} FPS',
                  style: TextStyle(
                    color: _invert(appSurfaceColor),
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    shadows: <Shadow>[
                      Shadow(
                        color: appSurfaceColor.withValues(alpha: 0.85),
                        blurRadius: 3,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.status,
    required this.busy,
    required this.dark,
    required this.onDarkChanged,
    required this.onAbout,
  });

  final String status;
  final bool busy;
  final bool dark;
  final ValueChanged<bool> onDarkChanged;
  final VoidCallback onAbout;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Row(
        children: <Widget>[
          Icon(Icons.lock_rounded, color: scheme.primary),
          const SizedBox(width: 10),
          Text(_appTitle, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(width: 12),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Row(
                key: ValueKey('$busy$status'),
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (busy)
                    const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      Icons.info_outline_rounded,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      status,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'About',
            onPressed: onAbout,
            icon: const Icon(Icons.more_vert_rounded),
          ),
          Switch(
            value: dark,
            thumbIcon: WidgetStateProperty.resolveWith<Icon?>(
              (states) => Icon(
                states.contains(WidgetState.selected)
                    ? Icons.dark_mode_rounded
                    : Icons.light_mode_rounded,
              ),
            ),
            onChanged: onDarkChanged,
          ),
        ],
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.tokenController,
    required this.showToken,
    required this.onShowTokenChanged,
    required this.onSetToken,
    required this.onGenerateToken,
    required this.mode,
    required this.onModeChanged,
    required this.autoCopyEncrypted,
    required this.onAutoCopyChanged,
  });

  final TextEditingController tokenController;
  final bool showToken;
  final VoidCallback onShowTokenChanged;
  final VoidCallback onSetToken;
  final VoidCallback onGenerateToken;
  final CipherMode mode;
  final ValueChanged<CipherMode> onModeChanged;
  final bool autoCopyEncrypted;
  final ValueChanged<bool> onAutoCopyChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: tokenController,
                  obscureText: !showToken,
                  onSubmitted: (_) => onSetToken(),
                  decoration: InputDecoration(
                    hintText: 'Token',
                    prefixIcon: const Icon(Icons.key_rounded),
                    suffixIcon: IconButton(
                      tooltip: showToken ? 'Hide token' : 'Show token',
                      onPressed: onShowTokenChanged,
                      icon: Icon(
                        showToken
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: onSetToken,
                icon: const Icon(Icons.done_rounded),
                label: const Text('Set'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: onGenerateToken,
                icon: const Icon(Icons.auto_awesome_rounded),
                label: const Text('Generate'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              SegmentedButton<CipherMode>(
                segments: const <ButtonSegment<CipherMode>>[
                  ButtonSegment<CipherMode>(
                    value: CipherMode.encrypt,
                    icon: Icon(Icons.lock_rounded),
                    label: Text('Encrypt'),
                  ),
                  ButtonSegment<CipherMode>(
                    value: CipherMode.decrypt,
                    icon: Icon(Icons.lock_open_rounded),
                    label: Text('Decrypt'),
                  ),
                ],
                selected: <CipherMode>{mode},
                onSelectionChanged: (selection) =>
                    onModeChanged(selection.first),
              ),
              const SizedBox(width: 12),
              const Spacer(),
              Text(
                'Auto-copy',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(width: 8),
              Switch(
                value: autoCopyEncrypted,
                thumbIcon: WidgetStateProperty.resolveWith<Icon?>(
                  (states) => Icon(
                    states.contains(WidgetState.selected)
                        ? Icons.check_rounded
                        : Icons.close_rounded,
                  ),
                ),
                onChanged: onAutoCopyChanged,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TextPanel extends StatelessWidget {
  const _TextPanel({
    required this.label,
    required this.icon,
    required this.controller,
    required this.hint,
    this.readOnly = false,
  });

  final String label;
  final IconData icon;
  final TextEditingController controller;
  final String hint;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text(label, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TextField(
                controller: controller,
                readOnly: readOnly,
                expands: true,
                minLines: null,
                maxLines: null,
                textAlignVertical: TextAlignVertical.top,
                decoration: InputDecoration(hintText: hint),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.canCopy,
    required this.onPaste,
    required this.onCopy,
    required this.onClear,
  });

  final bool canCopy;
  final VoidCallback onPaste;
  final VoidCallback onCopy;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: <Widget>[
          FilledButton.tonalIcon(
            onPressed: onPaste,
            icon: const Icon(Icons.content_paste_rounded),
            label: const Text('Paste text'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: canCopy ? onCopy : null,
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copy result'),
          ),
          const Spacer(),
          IconButton.outlined(
            tooltip: 'Clear',
            onPressed: onClear,
            icon: const Icon(Icons.clear_rounded),
          ),
        ],
      ),
    );
  }
}
