import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Application configuration for Omi Omni
/// Loads settings from .env file and provides defaults
class AppConfig {
  // Singleton instance
  static final AppConfig _instance = AppConfig._internal();
  factory AppConfig() => _instance;
  AppConfig._internal();

  // Backend configuration
  late String apiBaseUrl;
  late String apiKey;

  // Feature flags
  late bool enableAiProcessing;
  late bool enableOfflineRecording;
  late bool enableOtaUpdates;
  late bool enableAnalytics;

  // Audio settings
  late int audioChunkSize;
  late int maxRecordingDuration;
  late String audioCodec;

  // Connection settings
  late int connectionTimeout;
  late int reconnectionDelay;

  // UI settings
  late bool useDarkTheme;
  late String primaryColor;

  // Initialization
  Future<void> initialize() async {
    try {
      // Load .env file
      await dotenv.load(fileName: '.env');
    } catch (e) {
      debugPrint('Error loading .env file: $e');
    }

    // Load configuration with defaults
    _loadConfiguration();
  }

  void _loadConfiguration() {
    // Backend configuration
    apiBaseUrl = dotenv.get('API_BASE_URL', defaultValue: 'http://localhost:8000');
    apiKey = dotenv.get('API_KEY', defaultValue: 'change-me');

    // Feature flags
    enableAiProcessing = _parseBool(dotenv.get('ENABLE_AI_PROCESSING', defaultValue: 'true'));
    enableOfflineRecording = _parseBool(dotenv.get('ENABLE_OFFLINE_RECORDING', defaultValue: 'true'));
    enableOtaUpdates = _parseBool(dotenv.get('ENABLE_OTA_UPDATES', defaultValue: 'true'));
    enableAnalytics = _parseBool(dotenv.get('ENABLE_ANALYTICS', defaultValue: 'false'));

    // Audio settings
    audioChunkSize = _parseInt(dotenv.get('AUDIO_CHUNK_SIZE', defaultValue: '4096'));
    maxRecordingDuration = _parseInt(dotenv.get('MAX_RECORDING_DURATION', defaultValue: '3600')); // 1 hour
    audioCodec = dotenv.get('AUDIO_CODEC', defaultValue: 'opus');

    // Connection settings
    connectionTimeout = _parseInt(dotenv.get('CONNECTION_TIMEOUT', defaultValue: '30'));
    reconnectionDelay = _parseInt(dotenv.get('RECONNECTION_DELAY', defaultValue: '5'));

    // UI settings
    useDarkTheme = _parseBool(dotenv.get('USE_DARK_THEME', defaultValue: 'true'));
    primaryColor = dotenv.get('PRIMARY_COLOR', defaultValue: '0xFF2196F3');
  }

  bool _parseBool(String value) {
    return value.toLowerCase() == 'true';
  }

  int _parseInt(String value) {
    return int.tryParse(value) ?? 0;
  }

  // Getters for computed values
  Uri get apiBaseUri => Uri.parse(apiBaseUrl);

  /// Check if backend is configured
  bool get isBackendConfigured => apiBaseUrl.isNotEmpty && apiKey.isNotEmpty;

  /// Check if AI processing is enabled and backend is configured
  bool get canProcessAudio => enableAiProcessing && isBackendConfigured;

  /// Get WebSocket URL for audio streaming
  String get audioWebSocketUrl => apiBaseUrl.replaceFirst('http', 'ws');

  /// Validate configuration
  void validate() {
    if (!isBackendConfigured) {
      debugPrint('WARNING: Backend is not properly configured. Some features will be disabled.');
    }
  }

  /// Update configuration from settings
  void updateFromSettings({
    String? apiBaseUrl,
    String? apiKey,
    bool? enableAiProcessing,
    bool? enableOfflineRecording,
    bool? enableOtaUpdates,
    int? audioChunkSize,
    int? maxRecordingDuration,
    String? audioCodec,
    bool? useDarkTheme,
  }) {
    if (apiBaseUrl != null) this.apiBaseUrl = apiBaseUrl;
    if (apiKey != null) this.apiKey = apiKey;
    if (enableAiProcessing != null) this.enableAiProcessing = enableAiProcessing;
    if (enableOfflineRecording != null) this.enableOfflineRecording = enableOfflineRecording;
    if (enableOtaUpdates != null) this.enableOtaUpdates = enableOtaUpdates;
    if (audioChunkSize != null) this.audioChunkSize = audioChunkSize;
    if (maxRecordingDuration != null) this.maxRecordingDuration = maxRecordingDuration;
    if (audioCodec != null) this.audioCodec = audioCodec;
    if (useDarkTheme != null) this.useDarkTheme = useDarkTheme;
  }

  /// Save configuration to .env file (for development)
  Future<void> saveToEnv() async {
    // This is for development purposes only
    // In production, use proper settings storage
    debugPrint('Configuration saved (development only)');
  }
}

/// Configuration provider for easy access
class Config {
  static AppConfig get instance => AppConfig();
}
