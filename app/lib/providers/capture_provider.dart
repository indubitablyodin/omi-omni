import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../backend/schema/bt_device/bt_device.dart';
import '../services/device_connection.dart';
import '../services/models.dart';
import '../utils/audio/wav_bytes.dart';

/// Capture Provider
/// Manages audio capture from the Omi device and streaming to backend
class CaptureProvider extends ChangeNotifier {
  DeviceConnection? _activeConnection;
  StreamSubscription? _audioBytesSubscription;
  StreamSubscription? _buttonSubscription;

  WavBytesUtil? _wavBytesUtil;
  bool _loggedFirstBytes = false;
  bool _isRecording = false;
  int _frameCount = 0;
  RecordingMode _currentMode = RecordingMode.standard;
  
  // Audio processing state
  AudioProcessingState _audioState = AudioProcessingState.idle;
  String? _currentRecordingPath;
  DateTime? _recordingStartTime;
  
  // Button event callback
  Function(String)? onButtonEvent;

  CaptureProvider();

  // ===========================================================================
  // Connection Management
  // ===========================================================================

  /// Set the active connection from DeviceProvider
  void setActiveConnection(DeviceConnection? connection) {
    _activeConnection = connection;
    _loggedFirstBytes = false;
    _audioBytesSubscription?.cancel();
    _buttonSubscription?.cancel();
    _audioBytesSubscription = null;
    _buttonSubscription = null;

    if (_activeConnection != null) {
      _wavBytesUtil = null;
      debugPrint('[CaptureProvider] Received active connection: ${_activeConnection!.bleDevice.remoteId}');
      _initializeForConnection(_activeConnection!);
    } else {
      debugPrint('[CaptureProvider] Received null connection (disconnected)');
      if (_isRecording) {
        stopRecordingAndSave();
      }
    }
    
    notifyListeners();
  }

  /// Initialize for a new connection
  Future<void> _initializeForConnection(DeviceConnection connection) async {
    debugPrint('[CaptureProvider] Initializing for connection...');
    
    try {
      // Determine the codec from the device
      final codec = await connection.performGetAudioCodec();
      debugPrint('[CaptureProvider] Determined Codec: $codec');

      // Initialize WavBytesUtil with the determined codec
      _wavBytesUtil = WavBytesUtil(codec: codec);
      debugPrint('[CaptureProvider] Initialized WavBytesUtil with codec $codec');

      // Start listening to audio bytes
      _startAudioStream(connection);

      // Start listening to button presses
      _startButtonStream(connection);
    } catch (e, stackTrace) {
      debugPrint('[CaptureProvider] Error during initialization: $e\n$stackTrace');
      setActiveConnection(null);
    }
  }

  // ===========================================================================
  // Audio Stream Management
  // ===========================================================================

  void _startAudioStream(DeviceConnection connection) async {
    debugPrint('[CaptureProvider] Attempting to start audio stream...');
    _audioBytesSubscription?.cancel();
    
    try {
      _audioBytesSubscription = await connection.performGetBleAudioBytesListener(
        onAudioBytesReceived: (bytes) {
          // Log first few bytes received once
          if (_wavBytesUtil != null && !_loggedFirstBytes) {
            debugPrint('[CaptureProvider] Received first audio bytes chunk (len=${bytes.length}): ${bytes.take(10).toList()}...');
            _loggedFirstBytes = true;
          }

          // Only store packet and increment count if actually recording
          if (_isRecording && _wavBytesUtil != null) {
            _wavBytesUtil!.storeFramePacket(bytes);
            _frameCount++;
            
            // Log occasionally
            if (_frameCount % 100 == 0) {
              debugPrint('[CaptureProvider] Processed packet #${_frameCount} while recording');
            }
          }
        },
      );

      // Handle errors
      _audioBytesSubscription?.onError((error) {
        debugPrint('[CaptureProvider] Audio stream error: $error');
        setActiveConnection(null);
      });

      _audioBytesSubscription?.onDone(() {
        debugPrint('[CaptureProvider] Audio stream closed');
      });

      if (_audioBytesSubscription == null) {
        debugPrint('[CaptureProvider] Error: Failed to get audio stream subscription');
        setActiveConnection(null);
      }
    } catch (e, stackTrace) {
      debugPrint('[CaptureProvider] Error setting up audio stream: $e\n$stackTrace');
      setActiveConnection(null);
    }
  }

  // ===========================================================================
  // Button Stream Management
  // ===========================================================================

  void _startButtonStream(DeviceConnection connection) async {
    debugPrint('[CaptureProvider] Setting up button stream...');
    _buttonSubscription?.cancel();
    
    try {
      _buttonSubscription = await connection.performGetBleButtonListener(
        onButtonReceived: (bytes) {
          if (bytes.length >= 2) {
            final buttonEvent = ButtonEvent.fromButtonData(bytes);
            debugPrint('[CaptureProvider] Button event received: ${buttonEvent.name}');
            
            // Notify UI about button event
            if (onButtonEvent != null) {
              onButtonEvent!(buttonEvent.name);
            }
            
            // Handle recording based on button event
            final mode = ButtonEvent.getRecordingMode(buttonEvent.type);
            if (_isRecording) {
              stopRecordingAndSave(mode: mode);
            } else {
              startRecording(mode: mode);
            }
          }
        },
      );
      
      debugPrint('[CaptureProvider] Button stream subscription established');
    } catch (e) {
      debugPrint('[CaptureProvider] Error setting up button stream: $e');
    }
  }

  // ===========================================================================
  // Recording Control
  // ===========================================================================

  void startRecording({RecordingMode mode = RecordingMode.standard}) {
    if (_activeConnection == null || _isRecording) return;
    
    debugPrint('[CaptureProvider] Starting recording in mode: $mode');
    _isRecording = true;
    _currentMode = mode;
    _frameCount = 0;
    _audioState = AudioProcessingState.recording;
    _recordingStartTime = DateTime.now();
    
    notifyListeners();
  }

  Future<void> stopRecordingAndSave({RecordingMode? mode}) async {
    if (!_isRecording) return;
    
    mode ??= _currentMode;
    debugPrint('[CaptureProvider] Stopping recording. Mode: $mode, Total packets: $_frameCount');
    
    _isRecording = false;
    _audioState = AudioProcessingState.processing;
    notifyListeners();

    // Check if we have any frames
    if (_frameCount <= 0 || _wavBytesUtil == null || _wavBytesUtil!.frames.isEmpty) {
      debugPrint('[CaptureProvider] No packets processed during recording, nothing to save');
      _wavBytesUtil?.clearAudioBytes();
      _audioState = AudioProcessingState.idle;
      notifyListeners();
      return;
    }

    try {
      // Finalize any pending frame data
      _wavBytesUtil!.finalizeCurrentFrame();
      
      // Get the assembled frames
      final framesToSave = List<List<int>>.from(_wavBytesUtil!.frames);
      _wavBytesUtil!.clearAudioBytes();
      
      // Generate filename
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final filenameStem = 'recording-$timestamp';
      
      // Save to WAV file
      final directory = await getApplicationDocumentsDirectory();
      final wavFile = await _wavBytesUtil!.createWavByCodec(
        framesToSave,
        filename: filenameStem,
      );
      
      _currentRecordingPath = wavFile.path;
      debugPrint('[CaptureProvider] Recording saved: ${_currentRecordingPath}');
      
      // Notify that recording is complete
      _audioState = AudioProcessingState.complete;
      notifyListeners();
      
      // Reset state after a delay
      Future.delayed(const Duration(seconds: 2), () {
        _audioState = AudioProcessingState.idle;
        _currentRecordingPath = null;
        notifyListeners();
      });
    } catch (e, stackTrace) {
      debugPrint('[CaptureProvider] Error saving recording: $e\n$stackTrace');
      _audioState = AudioProcessingState.error;
      notifyListeners();
      
      // Reset after error
      Future.delayed(const Duration(seconds: 2), () {
        _audioState = AudioProcessingState.idle;
        notifyListeners();
      });
    }
  }

  // ===========================================================================
  // Audio Streaming to Backend
  // ===========================================================================

  /// Start streaming audio to backend
  Future<void> startBackendStreaming() async {
    if (_activeConnection == null) {
      throw Exception('No active device connection');
    }
    
    if (_isRecording) {
      throw Exception('Already recording');
    }
    
    debugPrint('[CaptureProvider] Starting backend streaming');
    _isRecording = true;
    _frameCount = 0;
    _audioState = AudioProcessingState.recording;
    _recordingStartTime = DateTime.now();
    
    notifyListeners();
  }

  /// Stop streaming and send to backend
  Future<void> stopBackendStreaming() async {
    if (!_isRecording) return;
    
    debugPrint('[CaptureProvider] Stopping backend streaming');
    _isRecording = false;
    _audioState = AudioProcessingState.uploading;
    notifyListeners();
    
    // TODO: Implement actual streaming to backend
    // This will be connected to the BackendProvider
    
    _audioState = AudioProcessingState.complete;
    notifyListeners();
  }

  // ===========================================================================
  // Getters
  // ===========================================================================

  bool get isRecording => _isRecording;
  RecordingMode get currentMode => _currentMode;
  AudioProcessingState get audioState => _audioState;
  String? get currentRecordingPath => _currentRecordingPath;
  int get frameCount => _frameCount;
  
  bool get isProcessing => _audioState == AudioProcessingState.processing ||
      _audioState == AudioProcessingState.uploading;
  
  bool get hasActiveConnection => _activeConnection != null;

  // ===========================================================================
  // Cleanup
  // ===========================================================================

  @override
  void dispose() {
    _audioBytesSubscription?.cancel();
    _buttonSubscription?.cancel();
    super.dispose();
  }
}
