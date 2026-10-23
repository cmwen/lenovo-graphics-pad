import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lenovo_graphics_pad/main.dart';
import 'package:lenovo_graphics_pad/pad_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakePadController implements PadController {
  final StreamController<Map<String, dynamic>> eventStream =
      StreamController.broadcast();
  PadState state = const PadState();
  List<String> calls = [];
  bool emitErrorOnRecover = false;
  bool emitStreamErrorOnRecover = false;
  List<Map<String, dynamic>> hosts = [
    {'name': 'Studio laptop', 'address': '01:23:45:67:89:AB'},
  ];
  List<Map<String, dynamic>> devices = [];

  @override
  Stream<Map<String, dynamic>> get events => eventStream.stream;
  @override
  Future<PadState> getState() async => state;
  @override
  Future<void> selectTransport(String transport) async {
    calls.add('selectTransport:$transport');
    state = state.copyWith(transport: transport);
    eventStream.add({
      'kind': 'state',
      'transport': transport,
      'registered': state.registered,
      'connected': state.connected,
      'busy': false,
      'status': state.status,
      'hostName': state.hostName,
    });
  }

  @override
  Future<List<Map<String, dynamic>>> capabilities() async => devices;
  @override
  Future<List<Map<String, dynamic>>> pairedHosts() async => hosts;
  @override
  Future<void> start(String transport) async {
    calls.add('start:$transport');
  }

  @override
  Future<void> stop() async => calls.add('stop');
  @override
  Future<void> recoverUsb() async {
    calls.add('recoverUsb');
    if (emitErrorOnRecover) {
      eventStream.add({
        'kind': 'state',
        'transport': 'usb',
        'registered': false,
        'connected': false,
        'busy': false,
        'status': 'Recovery failed',
        'error': 'USB restore was rejected',
      });
    }
    if (emitStreamErrorOnRecover) {
      eventStream.addError(StateError('event stream failed'));
    }
  }

  @override
  Future<void> discoverable() async => calls.add('discoverable');
  @override
  Future<void> connect(String address) async => calls.add('connect:$address');
  @override
  Future<void> disconnect() async => calls.add('disconnect');
  @override
  Future<void> clear() async => calls.add('clear');
  @override
  Future<void> configure(Map<String, dynamic> values) async =>
      calls.add('configure');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('transport selection, start and stop use native control', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = FakePadController();
    await tester.pumpWidget(
      LenovoGraphicsPadApp(controller: controller, preferences: prefs),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bluetooth').last);
    await tester.pumpAndSettle();
    expect(controller.calls, contains('selectTransport:bluetooth'));
    expect(controller.calls, isNot(contains('stop')));

    expect(find.text('Start'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('transport-action')));
    await tester.pumpAndSettle();
    expect(controller.calls, contains('start:bluetooth'));
  });

  testWidgets('native state events gate transport changes until stopped', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = FakePadController();
    await tester.pumpWidget(
      LenovoGraphicsPadApp(controller: controller, preferences: prefs),
    );
    await tester.pumpAndSettle();

    controller.eventStream.add({
      'kind': 'state',
      'transport': 'usb',
      'registered': true,
      'connected': false,
      'busy': false,
      'status': 'USB active',
    });
    await tester.pumpAndSettle();
    expect(find.text('USB active'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
    final transportPicker = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>).first,
    );
    expect(transportPicker.onChanged, isNull);
    expect(
      controller.calls.where((call) => call.startsWith('start:')),
      isEmpty,
    );
  });

  testWidgets('native state errors emitted during an action remain visible', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = FakePadController()..emitErrorOnRecover = true;
    await tester.pumpWidget(
      LenovoGraphicsPadApp(controller: controller, preferences: prefs),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Restore Android USB / ADB'));
    await tester.pumpAndSettle();
    expect(find.text('USB restore was rejected'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('native event stream errors are displayed without escaping', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = FakePadController()..emitStreamErrorOnRecover = true;
    await tester.pumpWidget(
      LenovoGraphicsPadApp(controller: controller, preferences: prefs),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Restore Android USB / ADB'));
    await tester.pumpAndSettle();
    expect(find.text('Bad state: event stream failed'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('diagnostics summarize samples without dumping history maps', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = FakePadController()
      ..devices = [
        {
          'deviceId': 3,
          'name': 'Touchscreen',
          'tools': ['touchscreen-source'],
          'pressureSupported': false,
        },
      ];
    await tester.pumpWidget(
      LenovoGraphicsPadApp(controller: controller, preferences: prefs),
    );
    await tester.pumpAndSettle();
    controller.eventStream.add({
      'kind': 'sample',
      'deviceName': 'Touchscreen',
      'source': 4098,
      'tool': 'touch',
      'tip': true,
      'inRange': true,
      'x': 123,
      'y': 456,
      'pressure': 1.0,
      'rawPressure': 0.6,
      'pressureSupported': false,
      'historySamples': [
        {
          'x': 1,
          'y': 2,
          'nested': {'many': 'details'},
        },
      ],
    });
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Input diagnostics'));
    await tester.pumpAndSettle();
    expect(
      find.text('Reports queued / sent: 0  ·  Dropped: 0'),
      findsOneWidget,
    );
    expect(find.text('Position: 123, 456'), findsOneWidget);
    expect(
      find.textContaining('Device pressure range: not reported'),
      findsOneWidget,
    );
    expect(find.textContaining('Touchscreen'), findsWidgets);
    expect(find.textContaining('historySamples'), findsNothing);
    expect(find.textContaining('nested'), findsNothing);
  });

  testWidgets('settings are persisted within valid ranges and sent to native', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'pad.activeWidth': 4.0,
      'pad.pressureCurve': .01,
    });
    final prefs = await SharedPreferences.getInstance();
    final controller = FakePadController();
    await tester.pumpWidget(
      LenovoGraphicsPadApp(controller: controller, preferences: prefs),
    );
    await tester.pumpAndSettle();
    expect(prefs.getDouble('pad.activeWidth'), 1.0);
    expect(prefs.getDouble('pad.pressureCurve'), .25);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Pad settings'), findsOneWidget);
    await tester.tap(find.text('Left-handed layout'));
    await tester.pumpAndSettle();
    expect(prefs.getBool('pad.leftHanded'), isTrue);
    expect(controller.calls, contains('configure'));
    expect((await PadSettings.load(prefs)).pressureCurve, .25);
  });

  testWidgets('control surface fits compact portrait and landscape layouts', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = FakePadController();
    await tester.binding.setSurfaceSize(const Size(320, 568));
    await tester.pumpWidget(
      LenovoGraphicsPadApp(controller: controller, preferences: prefs),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.binding.setSurfaceSize(const Size(853, 533));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(null);
  });
}
