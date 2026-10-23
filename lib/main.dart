import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pad_controller.dart';

void main() => runApp(const LenovoGraphicsPadApp());

class LenovoGraphicsPadApp extends StatelessWidget {
  const LenovoGraphicsPadApp({super.key, this.controller, this.preferences});

  final PadController? controller;
  final SharedPreferences? preferences;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Lenovo Graphics Pad',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff176b5b)),
      useMaterial3: true,
    ),
    home: PadHomePage(
      controller: controller ?? NativePadController(),
      preferences: preferences,
    ),
  );
}

@immutable
class PadSettings {
  const PadSettings({
    this.rotation = 0,
    this.pressureMode = 'auto',
    this.pressureCurve = 1.0,
    this.activeWidth = 1.0,
    this.activeHeight = 1.0,
    this.leftHanded = false,
    this.barrel = true,
    this.eraser = true,
    this.fingerInput = true,
  });

  final int rotation;
  final String pressureMode;
  final double pressureCurve;
  final double activeWidth;
  final double activeHeight;
  final bool leftHanded;
  final bool barrel;
  final bool eraser;
  final bool fingerInput;

  Map<String, dynamic> toMap() => {
    'rotation': rotation,
    'pressureMode': pressureMode,
    'pressureCurve': pressureCurve,
    'activeWidth': activeWidth,
    'activeHeight': activeHeight,
    'leftHanded': leftHanded,
    'barrel': barrel,
    'eraser': eraser,
    'fingerInput': fingerInput,
  };

  PadSettings copyWith({
    int? rotation,
    String? pressureMode,
    double? pressureCurve,
    double? activeWidth,
    double? activeHeight,
    bool? leftHanded,
    bool? barrel,
    bool? eraser,
    bool? fingerInput,
  }) => PadSettings(
    rotation: rotation ?? this.rotation,
    pressureMode: pressureMode ?? this.pressureMode,
    pressureCurve: pressureCurve ?? this.pressureCurve,
    activeWidth: activeWidth ?? this.activeWidth,
    activeHeight: activeHeight ?? this.activeHeight,
    leftHanded: leftHanded ?? this.leftHanded,
    barrel: barrel ?? this.barrel,
    eraser: eraser ?? this.eraser,
    fingerInput: fingerInput ?? this.fingerInput,
  );

  static Future<PadSettings> load(SharedPreferences? prefs) async {
    prefs ??= await SharedPreferences.getInstance();
    return PadSettings(
      rotation: [0, 90, 180, 270].contains(prefs.getInt('pad.rotation'))
          ? prefs.getInt('pad.rotation')!
          : 0,
      pressureMode: prefs.getString('pad.pressureMode') == 'binary'
          ? 'binary'
          : 'auto',
      pressureCurve: _bounded(
        prefs.getDouble('pad.pressureCurve') ?? 1,
        .25,
        4,
      ),
      activeWidth: _bounded(prefs.getDouble('pad.activeWidth') ?? 1, .1, 1),
      activeHeight: _bounded(prefs.getDouble('pad.activeHeight') ?? 1, .1, 1),
      leftHanded: prefs.getBool('pad.leftHanded') ?? false,
      barrel: prefs.getBool('pad.barrel') ?? true,
      eraser: prefs.getBool('pad.eraser') ?? true,
      fingerInput: prefs.getBool('pad.fingerInput') ?? true,
    );
  }

  Future<void> save(SharedPreferences? prefs) async {
    prefs ??= await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setInt('pad.rotation', rotation),
      prefs.setString('pad.pressureMode', pressureMode),
      prefs.setDouble('pad.pressureCurve', pressureCurve),
      prefs.setDouble('pad.activeWidth', activeWidth),
      prefs.setDouble('pad.activeHeight', activeHeight),
      prefs.setBool('pad.leftHanded', leftHanded),
      prefs.setBool('pad.barrel', barrel),
      prefs.setBool('pad.eraser', eraser),
      prefs.setBool('pad.fingerInput', fingerInput),
    ]);
  }

  static double _bounded(double value, double low, double high) =>
      value.clamp(low, high).toDouble();
}

class PadHomePage extends StatefulWidget {
  const PadHomePage({super.key, required this.controller, this.preferences});
  final PadController controller;
  final SharedPreferences? preferences;

  @override
  State<PadHomePage> createState() => _PadHomePageState();
}

class _PadHomePageState extends State<PadHomePage> with WidgetsBindingObserver {
  late PadState _state = const PadState();
  PadSettings _settings = const PadSettings();
  StreamSubscription<Map<String, dynamic>>? _subscription;
  bool _loading = true;
  bool _working = false;
  bool _systemDialog = false;

  bool get _active => _state.registered || _state.connected;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscription = widget.controller.events.listen(
      _onEvent,
      onError: (Object error, StackTrace stackTrace) {
        if (mounted) {
          setState(() => _state = _state.copyWith(error: _readable(error)));
        }
      },
    );
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final results = await Future.wait([
        widget.controller.getState(),
        PadSettings.load(widget.preferences),
        widget.controller.capabilities(),
        widget.controller.pairedHosts(),
      ]);
      if (!mounted) return;
      setState(() {
        _state = (results[0] as PadState).copyWith(
          capabilities: results[2] as List<Map<String, dynamic>>,
          pairedHosts: results[3] as List<Map<String, dynamic>>,
        );
        _settings = results[1] as PadSettings;
        _loading = false;
      });
      await _settings.save(widget.preferences);
      await widget.controller.configure(_settings.toMap());
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _state = _state.copyWith(error: _readable(error));
        });
      }
    }
  }

  void _onEvent(Map<String, dynamic> event) {
    if (!mounted) return;
    setState(() {
      if (event['kind'] == 'sample') {
        _state = _state.copyWith(lastSample: event);
      } else if (event['kind'] == 'hosts') {
        _state = _state.copyWith(
          pairedHosts: (event['hosts'] as List<dynamic>? ?? const [])
              .whereType<Map>()
              .map((host) => Map<String, dynamic>.from(host))
              .toList(),
        );
      } else if (event['kind'] == 'state') {
        _state = PadState.fromMap(event, _state);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_systemDialog || !_active) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_run(() => widget.controller.stop()));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    if (_active) unawaited(widget.controller.stop());
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_working || !mounted) return;
    setState(() {
      _working = true;
      _state = _state.copyWith(clearError: true);
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(() => _state = _state.copyWith(error: _readable(error)));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  String _readable(Object error) {
    if (error is PlatformException) return error.message ?? error.code;
    if (error is MissingPluginException) {
      return 'Native control is unavailable on this device.';
    }
    return error.toString().replaceFirst('Exception: ', '');
  }

  Future<void> _selectTransport(String? value) async {
    if (value == null || value == _state.transport || _working || _active) {
      return;
    }
    await _run(() async {
      await widget.controller.selectTransport(value);
    });
  }

  Future<void> _start() =>
      _run(() => widget.controller.start(_state.transport));

  Future<void> _discover() async {
    _systemDialog = true;
    try {
      await _run(widget.controller.discoverable);
      final hosts = await widget.controller.pairedHosts();
      if (mounted) setState(() => _state = _state.copyWith(pairedHosts: hosts));
    } finally {
      _systemDialog = false;
    }
  }

  Future<void> _changeSettings(PadSettings value) async {
    final previous = _settings;
    setState(() => _settings = value);
    try {
      await value.save(widget.preferences);
      await widget.controller.configure(value.toMap());
    } catch (error) {
      if (mounted) {
        setState(() => _state = _state.copyWith(error: _readable(error)));
      }
      // Keep a usable in-memory setting even if a platform write fails.
      if (error is! PlatformException) setState(() => _settings = previous);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Graphics Pad'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.tune),
            onPressed: _loading ? null : () => _showSettings(context),
          ),
          IconButton(
            tooltip: 'Input diagnostics',
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showDiagnostics(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth > 760;
                  final canvas = Expanded(child: _buildCanvas(colors));
                  final controls = _buildControls(context);
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: wide
                        ? Row(
                            children: [
                              SizedBox(
                                width: 300,
                                child: SingleChildScrollView(child: controls),
                              ),
                              const SizedBox(width: 16),
                              canvas,
                            ],
                          )
                        : Column(
                            children: [
                              canvas,
                              const SizedBox(height: 12),
                              controls,
                            ],
                          ),
                  );
                },
              ),
      ),
    );
  }

  Widget _buildCanvas(ColorScheme colors) => ClipRRect(
    borderRadius: BorderRadius.circular(20),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (Platform.isAndroid)
            const _AndroidPadSurface()
          else
            const _SurfaceFallback(),
          Positioned(
            right: 12,
            top: 12,
            child: IconButton.filledTonal(
              tooltip: 'Clear surface',
              onPressed: _working ? null : () => _run(widget.controller.clear),
              icon: const Icon(Icons.layers_clear_outlined),
            ),
          ),
          Positioned(
            left: 14,
            right: 56,
            bottom: 12,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surface.withValues(alpha: .92),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                child: Text(
                  _state.connected
                      ? 'Sending pen input to ${_state.hostName ?? 'host'}'
                      : _state.registered
                      ? 'Ready • waiting for a host connection'
                      : 'Local drawing • start USB or Bluetooth to send to a host',
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _statusCard(BuildContext context) {
    final color = _state.error != null
        ? Theme.of(context).colorScheme.error
        : _state.connected
        ? Colors.green.shade700
        : Theme.of(context).colorScheme.secondary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(
              _state.connected ? Icons.link : Icons.tablet_android,
              color: color,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _state.error == null ? _state.status : 'Action failed',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    _state.error ??
                        (_state.connected
                            ? 'Connected to ${_state.hostName ?? 'host'}'
                            : 'Transport ${_active ? 'active' : 'stopped'}'),
                  ),
                ],
              ),
            ),
            if (_state.error != null && _state.transport == 'usb')
              TextButton(
                onPressed: _working
                    ? null
                    : () => _run(widget.controller.recoverUsb),
                child: const Text('Restore USB'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _statusCard(context),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              key: ValueKey('transport-${_state.transport}'),
              initialValue: _state.transport,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Transport',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'usb', child: Text('USB')),
                DropdownMenuItem(value: 'bluetooth', child: Text('Bluetooth')),
              ],
              onChanged: _active || _working || _state.busy
                  ? null
                  : _selectTransport,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              key: const ValueKey('transport-action'),
              onPressed: _working || _state.busy
                  ? null
                  : _active
                  ? () => _run(widget.controller.stop)
                  : _start,
              icon: Icon(
                _active ? Icons.stop_circle_outlined : Icons.play_arrow,
              ),
              label: Text(
                _working
                    ? 'Working…'
                    : _active
                    ? 'Stop'
                    : 'Start',
              ),
            ),
          ),
        ],
      ),
      if (_state.transport == 'usb') ...[
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _working ? null : () => _run(widget.controller.recoverUsb),
          icon: const Icon(Icons.settings_backup_restore),
          label: const Text('Restore Android USB / ADB'),
        ),
      ] else ...[
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _working ? null : _discover,
                icon: const Icon(Icons.bluetooth_searching),
                label: const Text('Pair host'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _working || !_state.connected
                    ? null
                    : () => _run(widget.controller.disconnect),
                icon: const Icon(Icons.link_off),
                label: const Text('Disconnect'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _hostPicker(),
      ],
      if (_state.error != null) ...[
        const SizedBox(height: 8),
        Text(
          _state.error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      ],
      const SizedBox(height: 8),
      Text(
        'Touch input provides contact only. Continuous stylus pressure requires a verified pen digitizer.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );

  Widget _hostPicker() {
    final hosts = _state.pairedHosts;
    final selected = hosts
        .where(
          (host) =>
              host['address'] == _state.hostName ||
              host['name'] == _state.hostName,
        )
        .map((host) => host['address'] as String)
        .firstOrNull;
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            key: ValueKey('host-$selected-${hosts.length}'),
            initialValue: selected,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Paired host',
              border: OutlineInputBorder(),
            ),
            items: hosts.map((host) {
              final address = '${host['address'] ?? ''}';
              return DropdownMenuItem(
                value: address,
                child: Text(
                  '${host['name'] ?? address}',
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
            onChanged: _working || hosts.isEmpty
                ? null
                : (address) {
                    if (address != null) {
                      _run(() => widget.controller.connect(address));
                    }
                  },
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'Connect selected host',
          onPressed: _working || selected == null
              ? null
              : () => _run(() => widget.controller.connect(selected)),
          icon: const Icon(Icons.link),
        ),
      ],
    );
  }

  Future<void> _showSettings(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              12,
              20,
              20 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pad settings',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    initialValue: _settings.rotation,
                    decoration: const InputDecoration(
                      labelText: 'Tablet rotation',
                    ),
                    items: const [0, 90, 180, 270]
                        .map(
                          (n) => DropdownMenuItem(value: n, child: Text('$n°')),
                        )
                        .toList(),
                    onChanged: (v) =>
                        _setSetting(refresh, _settings.copyWith(rotation: v)),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: _settings.pressureMode,
                    decoration: const InputDecoration(
                      labelText: 'Pressure handling',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'auto',
                        child: Text('Use device value'),
                      ),
                      DropdownMenuItem(
                        value: 'binary',
                        child: Text('Binary contact'),
                      ),
                    ],
                    onChanged: (v) => _setSetting(
                      refresh,
                      _settings.copyWith(pressureMode: v),
                    ),
                  ),
                  _slider(
                    'Pressure curve',
                    _settings.pressureCurve,
                    .25,
                    4,
                    (v) => _setSetting(
                      refresh,
                      _settings.copyWith(pressureCurve: v),
                    ),
                    '${_settings.pressureCurve.toStringAsFixed(2)}×',
                  ),
                  _slider(
                    'Active width',
                    _settings.activeWidth,
                    .1,
                    1,
                    (v) => _setSetting(
                      refresh,
                      _settings.copyWith(activeWidth: v),
                    ),
                    '${(_settings.activeWidth * 100).round()}%',
                  ),
                  _slider(
                    'Active height',
                    _settings.activeHeight,
                    .1,
                    1,
                    (v) => _setSetting(
                      refresh,
                      _settings.copyWith(activeHeight: v),
                    ),
                    '${(_settings.activeHeight * 100).round()}%',
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Restart the transport after rotation or active-area changes to update host geometry.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  SwitchListTile(
                    title: const Text('Left-handed layout'),
                    value: _settings.leftHanded,
                    onChanged: (v) =>
                        _setSetting(refresh, _settings.copyWith(leftHanded: v)),
                  ),
                  SwitchListTile(
                    title: const Text('Barrel button'),
                    value: _settings.barrel,
                    onChanged: (v) =>
                        _setSetting(refresh, _settings.copyWith(barrel: v)),
                  ),
                  SwitchListTile(
                    title: const Text('Eraser tool'),
                    value: _settings.eraser,
                    onChanged: (v) =>
                        _setSetting(refresh, _settings.copyWith(eraser: v)),
                  ),
                  SwitchListTile(
                    title: const Text('Allow finger input'),
                    subtitle: const Text(
                      'Touch contact does not provide real stylus pressure.',
                    ),
                    value: _settings.fingerInput,
                    onChanged: (v) => _setSetting(
                      refresh,
                      _settings.copyWith(fingerInput: v),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _setSetting(StateSetter refresh, PadSettings value) {
    refresh(() {});
    _changeSettings(value);
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
    String display,
  ) => Column(
    children: [
      Row(
        children: [
          Expanded(child: Text(label)),
          Text(display),
        ],
      ),
      Slider(value: value, min: min, max: max, onChanged: onChanged),
    ],
  );

  void _showDiagnostics(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Input diagnostics',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(
                  'Reports queued / sent: ${_state.txReports}  ·  Dropped: ${_state.droppedReports}',
                ),
                if (_state.transport == 'bluetooth')
                  const Text(
                    'Bluetooth count reflects reports accepted into its send queue.',
                  ),
                const SizedBox(height: 12),
                Text(
                  'Latest input sample',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (_state.lastSample == null)
                  const Text('Waiting for input.')
                else
                  _sampleSummary(_state.lastSample!),
                const SizedBox(height: 12),
                Text(
                  'Android input devices',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (_state.capabilities.isEmpty)
                  const Text('No device capability data reported.'),
                for (final device in _state.capabilities)
                  _capabilitySummary(device),
                const Text(
                  'Hardware pressure and host drawing compatibility require device and host testing.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sampleSummary(Map<String, dynamic> sample) {
    String number(Object? value) =>
        value is num ? value.toStringAsFixed(3) : '—';
    final contact = sample['tip'] == true ? 'contact down' : 'contact up';
    final range = sample['inRange'] == true ? 'in range' : 'out of range';
    final buttons = <String>[
      if (sample['barrel'] == true) 'barrel',
      if (sample['eraser'] == true) 'eraser',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _diagnosticLine(
          'Device',
          '${sample['deviceName'] ?? '—'}  ·  source ${sample['source'] ?? '—'}',
        ),
        _diagnosticLine(
          'Tool',
          '${sample['tool'] ?? '—'}  ·  $contact  ·  $range${buttons.isEmpty ? '' : '  ·  ${buttons.join(', ')}'}',
        ),
        _diagnosticLine(
          'Position',
          '${sample['x'] ?? '—'}, ${sample['y'] ?? '—'}',
        ),
        _diagnosticLine(
          'Pressure',
          'normalized ${number(sample['pressure'])}  ·  raw ${number(sample['rawPressure'])}',
        ),
        _diagnosticLine(
          'Device pressure range',
          sample['pressureSupported'] == true ? 'reported' : 'not reported',
        ),
      ],
    );
  }

  Widget _capabilitySummary(Map<String, dynamic> device) {
    final tools = (device['tools'] as List?)?.join(', ') ?? 'none reported';
    final pressure = device['pressureSupported'] == true
        ? 'pressure ${device['pressureMin'] ?? '—'}–${device['pressureMax'] ?? '—'}'
        : 'no continuous pressure range';
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text('${device['name'] ?? 'Input device'}'),
      subtitle: Text(
        'Device ${device['deviceId'] ?? '—'}  ·  $tools  ·  $pressure',
      ),
    );
  }

  Widget _diagnosticLine(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Text('$label: $value'),
  );
}

class _AndroidPadSurface extends StatelessWidget {
  const _AndroidPadSurface();

  @override
  Widget build(BuildContext context) => const AndroidView(
    viewType: 'graphics_pad/surface',
    creationParamsCodec: StandardMessageCodec(),
  );
}

class _SurfaceFallback extends StatelessWidget {
  const _SurfaceFallback();
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Center(
      child: constraints.maxHeight < 100
          ? const Icon(Icons.gesture, size: 30)
          : const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.gesture, size: 42),
                SizedBox(height: 8),
                Text('Native pen surface is available on Android'),
              ],
            ),
    ),
  );
}
