import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// Connexion BLE au tensiomètre ESP32 (source `ble_esp32` côté backend).
class BloodPressureBleService {
  BloodPressureBleService._();

  static final BloodPressureBleService instance = BloodPressureBleService._();

  /// Service / caractéristique HeadsApp (ESP32).
  static final Guid serviceUuid = Guid('4fafc201-1fb5-459e-8fcc-c5c9c331914b');
  static final Guid measurementCharUuid =
      Guid('beb5483e-36e1-4688-b7f5-ea07361b26a8');

  static const List<String> _deviceNameHints = [
    'headsapp',
    'esp32',
    'tensiometre',
    'tensiomètre',
    'tensiometer',
    'blood pressure',
  ];

  final StreamController<Map<String, int>> _measurementController =
      StreamController<Map<String, int>>.broadcast();

  Stream<Map<String, int>> get measurements => _measurementController.stream;

  bool connecting = false;
  bool connected = false;
  String? deviceName;
  String? statusMessage;

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  StreamSubscription<List<int>>? _notifySub;
  BluetoothDevice? _device;

  Future<void> connect() async {
    if (kIsWeb) {
      throw Exception(
        'La connexion Bluetooth nécessite un téléphone Android ou iOS.',
      );
    }
    if (connecting || connected) return;

    connecting = true;
    statusMessage = 'Recherche du tensiomètre…';
    try {
      await _ensurePermissions();

      final adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState != BluetoothAdapterState.on) {
        throw Exception('Activez le Bluetooth sur votre téléphone.');
      }

      await FlutterBluePlus.stopScan();
      final completer = Completer<BluetoothDevice>();
      late final StreamSubscription<List<ScanResult>> sub;

      sub = FlutterBluePlus.onScanResults.listen((results) {
        for (final result in results) {
          final name = _readableName(result);
          if (_matchesDevice(name)) {
            if (!completer.isCompleted) {
              completer.complete(result.device);
            }
            break;
          }
        }
      });

      _scanSub = sub;
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 12),
        withServices: [serviceUuid],
      );

      BluetoothDevice device;
      try {
        device = await completer.future.timeout(const Duration(seconds: 12));
      } on TimeoutException {
        final fallback = await _pickFromVisibleDevices();
        if (fallback == null) {
          throw Exception(
            'Tensiomètre introuvable. Allumez l\'appareil et réessayez.',
          );
        }
        device = fallback;
      } finally {
        await FlutterBluePlus.stopScan();
        await sub.cancel();
        _scanSub = null;
      }

      statusMessage = 'Connexion en cours…';
      await device.connect(timeout: const Duration(seconds: 15));
      _device = device;
      deviceName = _readableNameFromDevice(device);

      _connectionSub = device.connectionState.listen((state) {
        final isConnected = state == BluetoothConnectionState.connected;
        connected = isConnected;
        if (!isConnected) {
          statusMessage = 'Tensiomètre déconnecté';
          _notifySub?.cancel();
          _notifySub = null;
        }
      });

      await _subscribeMeasurement(device);
      connected = true;
      statusMessage = 'Tensiomètre connecté';
    } finally {
      connecting = false;
    }
  }

  Future<void> disconnect() async {
    await _notifySub?.cancel();
    _notifySub = null;
    await _connectionSub?.cancel();
    _connectionSub = null;
    if (_device != null) {
      try {
        await _device!.disconnect();
      } catch (_) {}
    }
    _device = null;
    connected = false;
    deviceName = null;
    statusMessage = null;
  }

  Future<void> dispose() async {
    await disconnect();
    await _scanSub?.cancel();
    await _measurementController.close();
  }

  Future<void> _ensurePermissions() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();
    }
  }

  Future<BluetoothDevice?> _pickFromVisibleDevices() async {
    final visible = <String, BluetoothDevice>{};
    final sub = FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        final name = _readableName(r);
        if (_matchesDevice(name)) {
          visible[name] = r.device;
        }
      }
    });
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    await sub.cancel();
    if (visible.isEmpty) return null;
    return visible.values.first;
  }

  Future<void> _subscribeMeasurement(BluetoothDevice device) async {
    final services = await device.discoverServices();
    BluetoothCharacteristic? target;

    for (final service in services) {
      for (final char in service.characteristics) {
        if (char.uuid == measurementCharUuid ||
            char.properties.notify ||
            char.properties.indicate) {
          target = char;
          break;
        }
      }
      if (target != null) break;
    }

    if (target == null) {
      throw Exception('Caractéristique de mesure introuvable sur l\'appareil.');
    }

    await target.setNotifyValue(true);
    _notifySub = target.onValueReceived.listen(_onMeasurementBytes);
  }

  void _onMeasurementBytes(List<int> bytes) {
    final parsed = _parsePayload(bytes);
    if (parsed == null) return;
    if (!_measurementController.isClosed) {
      _measurementController.add(parsed);
    }
  }

  Map<String, int>? _parsePayload(List<int> bytes) {
    if (bytes.isEmpty) return null;
    final raw = utf8.decode(bytes, allowMalformed: true).trim();
    if (raw.isEmpty) return null;

    try {
      final json = jsonDecode(raw);
      if (json is Map) {
        final sys = _asPositiveInt(json['systolic'] ?? json['pas'] ?? json['sys']);
        final dia = _asPositiveInt(json['diastolic'] ?? json['pad'] ?? json['dia']);
        final hr = _asPositiveInt(json['heartRate'] ?? json['fc'] ?? json['bpm']);
        if (sys != null && dia != null) {
          return {
            'systolic': sys,
            'diastolic': dia,
            if (hr != null) 'heartRate': hr,
          };
        }
      }
    } catch (_) {}

    final slash = RegExp(r'(\d{2,3})\s*/\s*(\d{2,3})');
    final slashMatch = slash.firstMatch(raw);
    if (slashMatch != null) {
      final sys = int.tryParse(slashMatch.group(1)!);
      final dia = int.tryParse(slashMatch.group(2)!);
      if (sys != null && dia != null) {
        return {'systolic': sys, 'diastolic': dia};
      }
    }
    return null;
  }

  int? _asPositiveInt(dynamic value) {
    final n = value is int ? value : int.tryParse(value?.toString() ?? '');
    if (n == null || n <= 0) return null;
    return n;
  }

  bool _matchesDevice(String name) {
    final lower = name.toLowerCase();
    if (lower.isEmpty) return false;
    return _deviceNameHints.any(lower.contains);
  }

  String _readableName(ScanResult result) {
    return result.advertisementData.advName.isNotEmpty
        ? result.advertisementData.advName
        : result.device.platformName;
  }

  String _readableNameFromDevice(BluetoothDevice device) {
    final name = device.platformName;
    return name.isNotEmpty ? name : 'Tensiomètre BLE';
  }
}
