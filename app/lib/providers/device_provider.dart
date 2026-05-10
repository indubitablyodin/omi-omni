import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../backend/schema/bt_device/bt_device.dart';
import '../services/devices.dart';
import '../services/services.dart';
import '../services/models.dart';

/// Device Provider
/// Manages BLE device discovery, connection, and state
class DeviceProvider extends ChangeNotifier implements IDeviceServiceSubsciption {
  final IDeviceService _deviceService = ServiceManager.instance().device;
  
  // Device state
  List<BtDevice> _discoveredDevices = [];
  DeviceConnectionState _connectionState = DeviceConnectionState.disconnected;
  BtDevice? _connectedDevice;
  DeviceConnection? _activeConnection;
  
  // UI state
  bool _isScanning = false;
  bool _isConnecting = false;
  String? _errorMessage;
  
  // Battery level
  int _batteryLevel = -1;
  StreamSubscription? _batterySubscription;
  
  // Last connected device ID for auto-reconnect
  String? _lastConnectedDeviceId;
  static const String _lastConnectedDeviceIdKey = 'last_connected_omi_id';

  DeviceProvider() {
    _deviceService.subscribe(this, this);
    _loadLastDeviceAndAttemptConnect();
  }

  // ===========================================================================
  // Initialization
  // ===========================================================================

  Future<void> _loadLastDeviceAndAttemptConnect() async {
    final prefs = await SharedPreferences.getInstance();
    _lastConnectedDeviceId = prefs.getString(_lastConnectedDeviceIdKey);
    
    if (_lastConnectedDeviceId != null) {
      debugPrint('[DeviceProvider] Found last connected device ID: $_lastConnectedDeviceId');
      // Start scan to find the device
      startScan();
    } else {
      debugPrint('[DeviceProvider] No last connected device ID found');
    }
  }

  Future<void> _saveLastConnectedDevice(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastConnectedDeviceIdKey, deviceId);
    _lastConnectedDeviceId = deviceId;
    debugPrint('[DeviceProvider] Saved last connected device ID: $deviceId');
  }

  Future<void> _clearLastConnectedDevice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastConnectedDeviceIdKey);
    _lastConnectedDeviceId = null;
    debugPrint('[DeviceProvider] Cleared last connected device ID');
  }

  // ===========================================================================
  // Device Discovery
  // ===========================================================================

  Future<void> startScan() async {
    if (_isScanning) return;
    
    _isScanning = true;
    _errorMessage = null;
    notifyListeners();
    
    try {
      debugPrint('[DeviceProvider] Starting scan...');
      await _deviceService.discover(
        desirableDeviceId: _lastConnectedDeviceId,
        timeout: 5,
      );
      debugPrint('[DeviceProvider] Scan completed');
    } catch (e) {
      debugPrint('[DeviceProvider] Scan error: $e');
      _errorMessage = 'Scan failed: $e';
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }

  Future<void> stopScan() async {
    if (!_isScanning) return;
    
    _isScanning = false;
    notifyListeners();
    
    try {
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
      }
    } catch (e) {
      debugPrint('[DeviceProvider] Error stopping scan: $e');
    }
  }

  // ===========================================================================
  // Device Connection
  // ===========================================================================

  Future<void> connectToDevice(String deviceId) async {
    if (_isConnecting) return;
    if (_connectionState == DeviceConnectionState.connected && 
        _activeConnection?.bleDevice.remoteId.toString() == deviceId) {
      debugPrint('[DeviceProvider] Already connected to device $deviceId');
      return;
    }
    
    _isConnecting = true;
    _errorMessage = null;
    notifyListeners();
    
    try {
      debugPrint('[DeviceProvider] Connecting to device $deviceId...');
      await _deviceService.ensureConnection(deviceId, force: true);
      debugPrint('[DeviceProvider] Connection request sent');
    } catch (e) {
      debugPrint('[DeviceProvider] Connection error: $e');
      _errorMessage = 'Connection failed: $e';
      _isConnecting = false;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    if (_activeConnection != null) {
      final deviceId = _activeConnection!.bleDevice.remoteId.toString();
      debugPrint('[DeviceProvider] Disconnecting from $deviceId');
      
      try {
        await _activeConnection!.disconnect();
        await _clearLastConnectedDevice();
      } catch (e) {
        debugPrint('[DeviceProvider] Error disconnecting: $e');
      }
    } else {
      debugPrint('[DeviceProvider] No active connection to disconnect');
    }
  }

  // ===========================================================================
  // Battery Monitoring
  // ===========================================================================

  Future<void> _startBatteryMonitoring() async {
    if (_activeConnection == null) return;
    
    // Cancel existing subscription
    await _batterySubscription?.cancel();
    
    try {
      _batterySubscription = await _activeConnection!.getBleBatteryLevelListener(
        onBatteryLevelChange: (level) {
          _batteryLevel = level;
          debugPrint('[DeviceProvider] Battery level updated: $_batteryLevel%');
          notifyListeners();
        },
      );
      
      // Get initial battery level
      _batteryLevel = await _activeConnection!.retrieveBatteryLevel();
      debugPrint('[DeviceProvider] Initial battery level: $_batteryLevel%');
      notifyListeners();
    } catch (e) {
      debugPrint('[DeviceProvider] Error starting battery monitoring: $e');
      _batteryLevel = -1;
    }
  }

  Future<void> _stopBatteryMonitoring() async {
    await _batterySubscription?.cancel();
    _batterySubscription = null;
    _batteryLevel = -1;
  }

  // ===========================================================================
  // IDeviceServiceSubsciption Implementation
  // ===========================================================================

  @override
  void onDevices(List<BtDevice> devices) {
    _discoveredDevices = devices;
    debugPrint('[DeviceProvider] Discovered ${devices.length} devices');
    notifyListeners();
  }

  @override
  void onDeviceConnectionStateChanged(String deviceId, DeviceConnectionState state) {
    debugPrint('[DeviceProvider] Connection state changed: $deviceId -> $state');
    
    _connectionState = state;
    _isConnecting = false;
    
    if (state == DeviceConnectionState.connected) {
      _activeConnection = _deviceService.activeConnection;
      if (_activeConnection != null) {
        _connectedDevice = _discoveredDevices.firstWhere(
          (d) => d.id == deviceId,
          orElse: () => _activeConnection!.device,
        );
        
        // Save as last connected device
        _saveLastConnectedDevice(deviceId);
        
        // Start battery monitoring
        _startBatteryMonitoring();
        
        debugPrint('[DeviceProvider] Connected to: ${_connectedDevice?.name}');
      }
    } else {
      _connectedDevice = null;
      _activeConnection = null;
      _stopBatteryMonitoring();
      debugPrint('[DeviceProvider] Disconnected from: $deviceId');
    }
    
    notifyListeners();
  }

  @override
  void onStatusChanged(DeviceServiceStatus status) {
    debugPrint('[DeviceProvider] Device service status: $status');
    
    if (status == DeviceServiceStatus.stop) {
      _discoveredDevices = [];
      _connectedDevice = null;
      _activeConnection = null;
      _stopBatteryMonitoring();
    }
    
    notifyListeners();
  }

  // ===========================================================================
  // Getters
  // ===========================================================================

  List<BtDevice> get discoveredDevices => _discoveredDevices;
  DeviceConnectionState get connectionState => _connectionState;
  BtDevice? get connectedDevice => _connectedDevice;
  DeviceConnection? get activeConnection => _activeConnection;
  
  bool get isScanning => _isScanning;
  bool get isConnecting => _isConnecting;
  bool get isConnected => _connectionState == DeviceConnectionState.connected;
  String? get errorMessage => _errorMessage;
  
  int get batteryLevel => _batteryLevel;
  bool get hasBatteryInfo => _batteryLevel >= 0;

  // ===========================================================================
  // Cleanup
  // ===========================================================================

  @override
  void dispose() {
    _deviceService.unsubscribe(this);
    _batterySubscription?.cancel();
    super.dispose();
  }
}
