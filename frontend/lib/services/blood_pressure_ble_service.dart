import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// Connexion BLE au tensiomètre HeadsApp-BP-Monitor (GATT Blood Pressure Service).
class BloodPressureBleReading {
  const BloodPressureBleReading({
    required this.systolic,
    required this.diastolic,
    this.meanArterialPressure,
    required this.measuredAt,
  });

  final int systolic;
  final int diastolic;
  final int? meanArterialPressure;
  final DateTime measuredAt;
}

class BloodPressureBleService {
  static const deviceName = 'HeadsApp-BP-Monitor';

  static final Guid serviceUuid = Guid('0000181A-0000-1000-8000-00805F9B34FB');
  static final Guid sbpUuid = Guid('00002A35-0000-1000-8000-00805F9B34FB');
  static final Guid dbpUuid = Guid('00002A36-0000-1000-8000-00805F9B34FB');
  static final Guid mapUuid = Guid('00002A37-0000-1000-8000-00805F9B34FB');

  final StreamController<BloodPressureBleReading> _readingsController =
      StreamController<BloodPressureBleReading>.broadcast();

  Stream<BloodPressureBleReading> get readings => _readingsController.stream;

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  final List<StreamSubscription<List<int>>> _notifySubs = [];

  BluetoothDevice? _device;
  int? _pendingSbp;
  int? _pendingDbp;
  int? _pendingMap;
  DateTime? _pendingAt;

  bool get isConnected =>
      _device != null &&
      _device!.isConnected;

  BluetoothDevice? get connectedDevice => _device;

  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  static String get platformLabel {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return 'téléphone';
      case TargetPlatform.windows:
        return 'PC Windows';
      case TargetPlatform.macOS:
        return 'Mac';
      case TargetPlatform.linux:
        return 'PC Linux';
      default:
        return 'appareil';
    }
  }

  Future<void> connect() async {
    if (!isSupported) {
      throw Exception(
        'La connexion Bluetooth n\'est pas disponible sur cette plateforme.',
      );
    }

    await disconnect();
    await _ensureBlePermissions();

    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      throw Exception(
        'Activez le Bluetooth sur votre $platformLabel (Paramètres système).',
      );
    }

    final device = await _scanForDevice();
    _device = device;

    await device.connect(
      license: License.nonprofit,
      timeout: const Duration(seconds: 15),
    );
    await _waitForConnection(device);

    _connectionSub = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        _clearPending();
      }
    });

    await _subscribeCharacteristics(device);
  }

  Future<void> disconnect() async {
    await _scanSub?.cancel();
    _scanSub = null;
    await _connectionSub?.cancel();
    _connectionSub = null;

    for (final sub in _notifySubs) {
      await sub.cancel();
    }
    _notifySubs.clear();

    final device = _device;
    _device = null;
    _clearPending();

    if (device != null) {
      try {
        await device.disconnect();
      } catch (_) {
        // ignore
      }
    }
  }

  Future<BluetoothDevice> _scanForDevice() async {
    final completer = Completer<BluetoothDevice>();
    final seen = <String>{};

    Future<void> listenResults() async {
      await _scanSub?.cancel();
      _scanSub = FlutterBluePlus.scanResults.listen((results) {
        for (final result in results) {
          final id = result.device.remoteId.str;
          if (seen.contains(id)) continue;
          if (!_matchesDevice(result)) continue;
          seen.add(id);
          if (!completer.isCompleted) {
            completer.complete(result.device);
          }
          return;
        }
      });
    }

    await listenResults();
    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 20),
      withServices: [serviceUuid],
    );

    try {
      return await completer.future.timeout(
        const Duration(seconds: 20),
        onTimeout: () async {
          if (defaultTargetPlatform != TargetPlatform.windows) {
            throw Exception(
              'Tensiomètre « $deviceName » introuvable. Vérifiez qu\'il est allumé et à proximité.',
            );
          }
          // Windows : certains adaptateurs n'exposent pas les UUID en scan filtré.
          await FlutterBluePlus.stopScan();
          await listenResults();
          await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
          return completer.future.timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw Exception(
              'Tensiomètre « $deviceName » introuvable. Vérifiez qu\'il est allumé, à proximité, et que le Bluetooth Windows est activé.',
            ),
          );
        },
      );
    } finally {
      await FlutterBluePlus.stopScan();
      await _scanSub?.cancel();
      _scanSub = null;
    }
  }

  bool _matchesDevice(ScanResult result) {
    final name = _readableName(result);
    if (name == deviceName) return true;
    return result.advertisementData.serviceUuids.contains(serviceUuid);
  }

  String _readableName(ScanResult result) {
    final adv = result.advertisementData.advName.trim();
    if (adv.isNotEmpty) return adv;
    return result.device.platformName.trim();
  }

  Future<void> _ensureBlePermissions() async {
    if (!Platform.isAndroid) return;

    final scan = await Permission.bluetoothScan.request();
    final connect = await Permission.bluetoothConnect.request();
    if (!scan.isGranted || !connect.isGranted) {
      throw Exception(
        'Autorisez le Bluetooth dans les paramètres de l\'application.',
      );
    }
  }

  Future<void> _waitForConnection(BluetoothDevice device) async {
    if (device.isConnected) return;
    await device.connectionState
        .firstWhere((s) => s == BluetoothConnectionState.connected)
        .timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw Exception('Connexion au tensiomètre expirée.'),
        );
  }

  Future<void> _subscribeCharacteristics(BluetoothDevice device) async {
    final services = await device.discoverServices();
    BluetoothService? bpService;
    for (final service in services) {
      if (service.uuid == serviceUuid) {
        bpService = service;
        break;
      }
    }

    if (bpService == null) {
      throw Exception('Service tension (181A) introuvable sur l\'appareil.');
    }

    BluetoothCharacteristic? sbpChar;
    BluetoothCharacteristic? dbpChar;
    BluetoothCharacteristic? mapChar;

    for (final char in bpService.characteristics) {
      if (char.uuid == sbpUuid) sbpChar = char;
      if (char.uuid == dbpUuid) dbpChar = char;
      if (char.uuid == mapUuid) mapChar = char;
    }

    if (sbpChar == null || dbpChar == null) {
      throw Exception('Caractéristiques PAS/PAD introuvables.');
    }

    await _enableNotify(sbpChar, _onSbp);
    await _enableNotify(dbpChar, _onDbp);
    if (mapChar != null) {
      await _enableNotify(mapChar, _onMap);
    }
  }

  Future<void> _enableNotify(
    BluetoothCharacteristic char,
    void Function(List<int> value) onData,
  ) async {
    await char.setNotifyValue(true);
    final sub = char.onValueReceived.listen(onData);
    _notifySubs.add(sub);
    if (char.lastValue.isNotEmpty) {
      onData(char.lastValue);
    }
  }

  void _onSbp(List<int> data) {
    final value = _parseUint16Le(data);
    if (value == null || value <= 0) return;
    _pendingSbp = value;
    _pendingAt ??= DateTime.now();
    _tryEmitReading();
  }

  void _onDbp(List<int> data) {
    final value = _parseUint16Le(data);
    if (value == null || value <= 0) return;
    _pendingDbp = value;
    _pendingAt ??= DateTime.now();
    _tryEmitReading();
  }

  void _onMap(List<int> data) {
    final value = _parseUint16Le(data);
    if (value == null || value <= 0) return;
    _pendingMap = value;
    _pendingAt ??= DateTime.now();
    _tryEmitReading();
  }

  void _tryEmitReading() {
    final sbp = _pendingSbp;
    final dbp = _pendingDbp;
    if (sbp == null || dbp == null) return;

    final reading = BloodPressureBleReading(
      systolic: sbp,
      diastolic: dbp,
      meanArterialPressure: _pendingMap,
      measuredAt: _pendingAt ?? DateTime.now(),
    );

    if (!_readingsController.isClosed) {
      _readingsController.add(reading);
    }

    _clearPending();
  }

  void _clearPending() {
    _pendingSbp = null;
    _pendingDbp = null;
    _pendingMap = null;
    _pendingAt = null;
  }

  int? _parseUint16Le(List<int> data) {
    if (data.length < 2) return null;
    return data[0] | (data[1] << 8);
  }

  Future<void> dispose() async {
    await disconnect();
    await _readingsController.close();
  }
}
