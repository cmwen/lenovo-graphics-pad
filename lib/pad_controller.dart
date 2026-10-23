import 'dart:async';

import 'package:flutter/services.dart';

class PadState {
  const PadState({
    this.transport = 'usb',
    this.registered = false,
    this.connected = false,
    this.busy = false,
    this.status = 'Stopped',
    this.error,
    this.hostName,
    this.txReports = 0,
    this.droppedReports = 0,
    this.lastSample,
    this.capabilities = const [],
    this.pairedHosts = const [],
  });

  final String transport;
  final bool registered;
  final bool connected;
  final bool busy;
  final String status;
  final String? error;
  final String? hostName;
  final int txReports;
  final int droppedReports;
  final Map<String, dynamic>? lastSample;
  final List<Map<String, dynamic>> capabilities;
  final List<Map<String, dynamic>> pairedHosts;

  PadState copyWith({
    String? transport,
    bool? registered,
    bool? connected,
    bool? busy,
    String? status,
    String? error,
    bool clearError = false,
    String? hostName,
    bool clearHostName = false,
    int? txReports,
    int? droppedReports,
    Map<String, dynamic>? lastSample,
    List<Map<String, dynamic>>? capabilities,
    List<Map<String, dynamic>>? pairedHosts,
  }) => PadState(
    transport: transport ?? this.transport,
    registered: registered ?? this.registered,
    connected: connected ?? this.connected,
    busy: busy ?? this.busy,
    status: status ?? this.status,
    error: clearError ? null : error ?? this.error,
    hostName: clearHostName ? null : hostName ?? this.hostName,
    txReports: txReports ?? this.txReports,
    droppedReports: droppedReports ?? this.droppedReports,
    lastSample: lastSample ?? this.lastSample,
    capabilities: capabilities ?? this.capabilities,
    pairedHosts: pairedHosts ?? this.pairedHosts,
  );

  factory PadState.fromMap(Map<dynamic, dynamic> map, [PadState? previous]) {
    final old = previous ?? const PadState();
    return old.copyWith(
      transport: map['transport'] as String?,
      registered: map['registered'] as bool?,
      connected: map['connected'] as bool?,
      busy: map['busy'] as bool?,
      status: map['status'] as String?,
      error: map['error'] as String?,
      clearError: map['error'] == null,
      hostName: map['hostName'] as String?,
      clearHostName: map.containsKey('hostName') && map['hostName'] == null,
      txReports: (map['txReports'] as num?)?.toInt(),
      droppedReports: (map['droppedReports'] as num?)?.toInt(),
    );
  }
}

abstract interface class PadController {
  Stream<Map<String, dynamic>> get events;
  Future<PadState> getState();
  Future<void> selectTransport(String transport);
  Future<void> start(String transport);
  Future<void> stop();
  Future<void> recoverUsb();
  Future<void> discoverable();
  Future<List<Map<String, dynamic>>> pairedHosts();
  Future<void> connect(String address);
  Future<void> disconnect();
  Future<void> configure(Map<String, dynamic> values);
  Future<void> clear();
  Future<List<Map<String, dynamic>>> capabilities();
}

class NativePadController implements PadController {
  NativePadController({MethodChannel? methods, EventChannel? eventChannel})
    : _methods = methods ?? const MethodChannel('graphics_pad/control'),
      _eventChannel = eventChannel ?? const EventChannel('graphics_pad/events');

  final MethodChannel _methods;
  final EventChannel _eventChannel;

  @override
  Stream<Map<String, dynamic>> get events => _eventChannel
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .map((event) => Map<String, dynamic>.from(event as Map));

  @override
  Future<PadState> getState() async => PadState.fromMap(
    Map<dynamic, dynamic>.from(await _methods.invokeMethod('getState') as Map),
  );

  @override
  Future<void> selectTransport(String transport) =>
      _methods.invokeMethod<void>('selectTransport', {'transport': transport});

  @override
  Future<void> start(String transport) =>
      _methods.invokeMethod<void>('start', {'transport': transport});

  @override
  Future<void> stop() => _methods.invokeMethod<void>('stop');

  @override
  Future<void> recoverUsb() => _methods.invokeMethod<void>('recoverUsb');

  @override
  Future<void> discoverable() => _methods.invokeMethod<void>('discoverable');

  @override
  Future<List<Map<String, dynamic>>> pairedHosts() async =>
      _maps(await _methods.invokeMethod<List<dynamic>>('pairedHosts'));

  @override
  Future<void> connect(String address) =>
      _methods.invokeMethod<void>('connect', {'address': address});

  @override
  Future<void> disconnect() => _methods.invokeMethod<void>('disconnect');

  @override
  Future<void> configure(Map<String, dynamic> values) =>
      _methods.invokeMethod<void>('configure', values);

  @override
  Future<void> clear() => _methods.invokeMethod<void>('clear');

  @override
  Future<List<Map<String, dynamic>>> capabilities() async =>
      _maps(await _methods.invokeMethod<List<dynamic>>('capabilities'));

  List<Map<String, dynamic>> _maps(List<dynamic>? value) => (value ?? const [])
      .whereType<Map>()
      .map(Map<String, dynamic>.from)
      .toList();
}
