import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

// Service UUIDs
const String omiServiceUuid = '19b10000-e8f2-537e-4f6c-d104768a1214';
const String frameServiceUuid = '19b10000-e8f2-537e-4f6c-d104768a1215';
const String deviceInformationServiceUuid = '0000180a-0000-1000-8000-00805f9b34fb';
const String batteryServiceUuid = '0000180f-0000-1000-8000-00805f9b34fb';
const String batteryLevelCharacteristicUuid = '00002a19-0000-1000-8000-00805f9b34fb';
const String modelNumberCharacteristicUuid = '00002a24-0000-1000-8000-00805f9b34fb';
const String firmwareRevisionCharacteristicUuid = '00002a26-0000-1000-8000-00805f9b34fb';
const String hardwareRevisionCharacteristicUuid = '00002a27-0000-1000-8000-00805f9b34fb';
const String manufacturerNameCharacteristicUuid = '00002a29-0000-1000-8000-00805f9b34fb';

// Omi Service Characteristics
const String audioDataStreamCharacteristicUuid = '19b10001-e8f2-537e-4f6c-d104768a1214';
const String audioCodecCharacteristicUuid = '19b10002-e8f2-537e-4f6c-d104768a1214';
const String buttonServiceUuid = '23ba7924-0000-1000-7450-346eac492e92';
const String buttonTriggerCharacteristicUuid = '23ba7925-0000-1000-7450-346eac492e92';
const String storageDataStreamServiceUuid = '19b10003-e8f2-537e-4f6c-d104768a1214';
const String storageReadControlCharacteristicUuid = '19b10004-e8f2-537e-4f6c-d104768a1214';
const String storageDataStreamCharacteristicUuid = '19b10005-e8f2-537e-4f6c-d104768a1214';
const String speakerDataStreamServiceUuid = '19b10006-e8f2-537e-4f6c-d104768a1214';
const String speakerDataStreamCharacteristicUuid = '19b10007-e8f2-537e-4f6c-d104768a1214';
const String accelDataStreamServiceUuid = '19b10008-e8f2-537e-4f6c-d104768a1214';
const String accelDataStreamCharacteristicUuid = '19b10009-e8f2-537e-4f6c-d104768a1214';
const String imageServiceUuid = '19b1000a-e8f2-537e-4f6c-d104768a1214';
const String imageDataStreamCharacteristicUuid = '19b1000b-e8f2-537e-4f6c-d104768a1214';

// Frame Service Characteristics
const String frameAudioDataStreamCharacteristicUuid = '19b10001-e8f2-537e-4f6c-d104768a1215';
const String frameButtonServiceUuid = '23ba7924-0000-1000-7450-346eac492e93';
const String frameButtonTriggerCharacteristicUuid = '23ba7925-0000-1000-7450-346eac492e93';

// Button event types
const int BUTTON_SINGLE_TAP = 1;
const int BUTTON_DOUBLE_TAP = 2;
const int BUTTON_TRIPLE_TAP = 3;
const int BUTTON_LONG_PRESS = 4;
const int BUTTON_PRESS = 5;
const int BUTTON_RELEASE = 6;

enum BleAudioCodec {
  pcm16,
  pcm8,
  mulaw16,
  mulaw8,
  opus,
  unknown;

  @override
  String toString() => mapCodecToName(this);
}

String mapCodecToName(BleAudioCodec codec) {
  switch (codec) {
    case BleAudioCodec.opus:
      return 'opus';
    case BleAudioCodec.pcm16:
      return 'pcm16';
    case BleAudioCodec.pcm8:
      return 'pcm8';
    default:
      return 'pcm8';
  }
}

BleAudioCodec mapNameToCodec(String codec) {
  switch (codec) {
    case 'opus':
      return BleAudioCodec.opus;
    case 'pcm16':
      return BleAudioCodec.pcm16;
    case 'pcm8':
      return BleAudioCodec.pcm8;
    default:
      return BleAudioCodec.pcm8;
  }
}

int mapCodecToSampleRate(BleAudioCodec codec) {
  switch (codec) {
    case BleAudioCodec.opus:
      return 16000;
    case BleAudioCodec.pcm16:
      return 16000;
    case BleAudioCodec.pcm8:
      return 16000;
    default:
      return 16000;
  }
}

int mapCodecToBitDepth(BleAudioCodec codec) {
  switch (codec) {
    case BleAudioCodec.opus:
      return 16;
    case BleAudioCodec.pcm16:
      return 16;
    case BleAudioCodec.pcm8:
      return 8;
    default:
      return 16;
  }
}

Future<DeviceType?> getTypeOfBluetoothDevice(BluetoothDevice device) async {
  if (cachedDevicesMap.containsKey(device.remoteId.toString())) {
    return cachedDevicesMap[device.remoteId.toString()];
  }
  DeviceType? deviceType;
  await device.discoverServices();
  if (device.servicesList.where((s) => s.uuid == Guid(omiServiceUuid)).isNotEmpty) {
    // Check if the device has the image data stream characteristic
    final hasImageStream = device.servicesList
        .where((s) => s.uuid == Guid.fromString(omiServiceUuid))
        .expand((s) => s.characteristics)
        .any((c) => c.uuid.toString().toLowerCase() == imageDataStreamCharacteristicUuid.toLowerCase());
    deviceType = hasImageStream ? DeviceType.openglass : DeviceType.omi;
  } else if (device.servicesList.where((s) => s.uuid == Guid(frameServiceUuid)).isNotEmpty) {
    deviceType = DeviceType.frame;
  }
  if (deviceType != null) {
    cachedDevicesMap[device.remoteId.toString()] = deviceType;
  }
  return deviceType;
}

enum DeviceType {
  omi,
  openglass,
  frame,
}

Map<String, DeviceType> cachedDevicesMap = {};

class BtDevice {
  String name;
  String id;
  DeviceType type;
  int rssi;
  String? _modelNumber;
  String? _firmwareRevision;
  String? _hardwareRevision;
  String? _manufacturerName;

  BtDevice({
    required this.name,
    required this.id,
    required this.type,
    required this.rssi,
    String? modelNumber,
    String? firmwareRevision,
    String? hardwareRevision,
    String? manufacturerName,
  }) {
    _modelNumber = modelNumber;
    _firmwareRevision = firmwareRevision;
    _hardwareRevision = hardwareRevision;
    _manufacturerName = manufacturerName;
  }

  // create an empty device
  BtDevice.empty()
      : name = '',
        id = '',
        type = DeviceType.omi,
        rssi = 0,
        _modelNumber = '',
        _firmwareRevision = '',
        _hardwareRevision = '',
        _manufacturerName = '';

  // getters
  String get modelNumber => _modelNumber ?? 'Unknown';
  String get firmwareRevision => _firmwareRevision ?? 'Unknown';
  String get hardwareRevision => _hardwareRevision ?? 'Unknown';
  String get manufacturerName => _manufacturerName ?? 'Unknown';

  // set details
  set modelNumber(String modelNumber) => _modelNumber = modelNumber;
  set firmwareRevision(String firmwareRevision) => _firmwareRevision = firmwareRevision;
  set hardwareRevision(String hardwareRevision) => _hardwareRevision = hardwareRevision;
  set manufacturerName(String manufacturerName) => _manufacturerName = manufacturerName;

  String getShortId() => BtDevice.shortId(id);

  static String shortId(String id) {
    try {
      return id.replaceAll(':', '').split('-').last.substring(0, 6);
    } catch (e) {
      return id.length > 6 ? id.substring(0, 6) : id;
    }
  }

  BtDevice copyWith({
    String? name,
    String? id,
    DeviceType? type,
    int? rssi,
    String? modelNumber,
    String? firmwareRevision,
    String? hardwareRevision,
    String? manufacturerName,
  }) {
    return BtDevice(
      name: name ?? this.name,
      id: id ?? this.id,
      type: type ?? this.type,
      rssi: rssi ?? this.rssi,
      modelNumber: modelNumber ?? _modelNumber,
      firmwareRevision: firmwareRevision ?? _firmwareRevision,
      hardwareRevision: hardwareRevision ?? _hardwareRevision,
      manufacturerName: manufacturerName ?? _manufacturerName,
    );
  }

  Future<BtDevice> getDeviceInfo(BluetoothDevice device) async {
    try {
      await device.discoverServices();
      
      if (type == DeviceType.omi || type == DeviceType.openglass) {
        return await _getDeviceInfoFromOmi(device);
      } else if (type == DeviceType.frame) {
        return await _getDeviceInfoFromFrame(device);
      }
    } catch (e) {
      debugPrint('Error getting device info: $e');
    }
    return this;
  }

  Future<BtDevice> _getDeviceInfoFromOmi(BluetoothDevice device) async {
    var modelNumber = 'Omi Device';
    var firmwareRevision = 'Unknown';
    var hardwareRevision = 'Seeed Xiao BLE Sense';
    var manufacturerName = 'Based Hardware';
    var deviceType = DeviceType.omi;

    try {
      final deviceInfoService = device.servicesList.firstWhere(
        (s) => s.uuid == Guid(deviceInformationServiceUuid),
        orElse: () => null,
      );

      if (deviceInfoService != null) {
        final modelNumberChar = deviceInfoService.characteristics.firstWhere(
          (c) => c.uuid == Guid(modelNumberCharacteristicUuid),
          orElse: () => null,
        );
        if (modelNumberChar != null) {
          modelNumber = String.fromCharCodes(await modelNumberChar.read());
        }

        final firmwareChar = deviceInfoService.characteristics.firstWhere(
          (c) => c.uuid == Guid(firmwareRevisionCharacteristicUuid),
          orElse: () => null,
        );
        if (firmwareChar != null) {
          firmwareRevision = String.fromCharCodes(await firmwareChar.read());
        }

        final hardwareChar = deviceInfoService.characteristics.firstWhere(
          (c) => c.uuid == Guid(hardwareRevisionCharacteristicUuid),
          orElse: () => null,
        );
        if (hardwareChar != null) {
          hardwareRevision = String.fromCharCodes(await hardwareChar.read());
        }

        final manufacturerChar = deviceInfoService.characteristics.firstWhere(
          (c) => c.uuid == Guid(manufacturerNameCharacteristicUuid),
          orElse: () => null,
        );
        if (manufacturerChar != null) {
          manufacturerName = String.fromCharCodes(await manufacturerChar.read());
        }
      }

      // Check for image capture characteristic to determine if it's openglass
      final omiService = device.servicesList.firstWhere(
        (s) => s.uuid == Guid(omiServiceUuid),
        orElse: () => null,
      );
      if (omiService != null) {
        final imageChar = omiService.characteristics.firstWhere(
          (c) => c.uuid == Guid(imageDataStreamCharacteristicUuid),
          orElse: () => null,
        );
        if (imageChar != null) {
          deviceType = DeviceType.openglass;
        }
      }
    } on PlatformException catch (e) {
      debugPrint('PlatformException in _getDeviceInfoFromOmi: ${e.code} - ${e.message}');
    } catch (e) {
      debugPrint('Exception in _getDeviceInfoFromOmi: $e');
    }

    return copyWith(
      modelNumber: modelNumber,
      firmwareRevision: firmwareRevision,
      hardwareRevision: hardwareRevision,
      manufacturerName: manufacturerName,
      type: deviceType,
    );
  }

  Future<BtDevice> _getDeviceInfoFromFrame(BluetoothDevice device) async {
    // For Frame devices, we'll use the same approach as Omi for now
    return await _getDeviceInfoFromOmi(device);
  }

  // from BluetoothDevice
  static Future<BtDevice> fromBluetoothDevice(BluetoothDevice device) async {
    var rssi = 0;
    try {
      rssi = await device.readRssi();
    } catch (e) {
      debugPrint('Error reading RSSI: $e');
    }
    return BtDevice(
      name: device.platformName,
      id: device.remoteId.str,
      type: DeviceType.omi,
      rssi: rssi,
    );
  }

  // from ScanResult
  static BtDevice fromScanResult(ScanResult result) {
    DeviceType? deviceType;
    if (result.advertisementData.serviceUuids.contains(Guid(omiServiceUuid))) {
      deviceType = DeviceType.omi;
    } else if (result.advertisementData.serviceUuids.contains(Guid(frameServiceUuid))) {
      deviceType = DeviceType.frame;
    }
    if (deviceType != null) {
      cachedDevicesMap[result.device.remoteId.toString()] = deviceType;
    } else if (cachedDevicesMap.containsKey(result.device.remoteId.toString())) {
      deviceType = cachedDevicesMap[result.device.remoteId.toString()];
    }
    return BtDevice(
      name: result.device.platformName,
      id: result.device.remoteId.str,
      type: deviceType ?? DeviceType.omi,
      rssi: result.rssi,
    );
  }

  // from json
  static BtDevice fromJson(Map<String, dynamic> json) {
    return BtDevice(
      name: json['name'] ?? '',
      id: json['id'] ?? '',
      type: json['type'] != null ? DeviceType.values[json['type']] : DeviceType.omi,
      rssi: json['rssi'] ?? 0,
      modelNumber: json['modelNumber'],
      firmwareRevision: json['firmwareRevision'],
      hardwareRevision: json['hardwareRevision'],
      manufacturerName: json['manufacturerName'],
    );
  }

  // to json
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'id': id,
      'type': type.index,
      'rssi': rssi,
      'modelNumber': _modelNumber,
      'firmwareRevision': _firmwareRevision,
      'hardwareRevision': _hardwareRevision,
      'manufacturerName': _manufacturerName,
    };
  }
}

// Basic SharedPreferences wrapper
class SharedPreferencesUtil {
  static SharedPreferences? _prefs;

  static Future init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  // Minimal implementation for btDevice persistence
  BtDevice get btDevice {
    final String? jsonString = _prefs?.getString('btDevice');
    if (jsonString != null) {
      try {
        return BtDevice.fromJson(jsonDecode(jsonString));
      } catch (e) {
        debugPrint("Error decoding stored btDevice: $e");
        return BtDevice.empty();
      }
    } else {
      return BtDevice.empty();
    }
  }

  set btDevice(BtDevice device) {
    try {
      _prefs?.setString('btDevice', jsonEncode(device.toJson()));
    } catch (e) {
      debugPrint("Error encoding btDevice for storage: $e");
    }
  }

  // Additional getters/setters
  String get deviceName => _prefs?.getString('deviceName') ?? '';
  set deviceName(String name) => _prefs?.setString('deviceName', name);

  String get fullName => _prefs?.getString('fullName') ?? '';
  String get uid => _prefs?.getString('uid') ?? '';
}
