import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/device_provider.dart';
import '../providers/capture_provider.dart';
import '../providers/backend_provider.dart';
import '../services/models.dart';
import '../backend/schema/bt_device/bt_device.dart';

/// Home Screen
/// Main screen showing device connection status and recording controls
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _lastButtonEvent;
  DateTime? _lastButtonEventTime;

  @override
  void initState() {
    super.initState();
    
    // Set up button event listener
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final captureProvider = Provider.of<CaptureProvider>(context, listen: false);
      captureProvider.onButtonEvent = (String eventName) {
        _updateButtonEvent(eventName);
      };
    });
  }

  void _updateButtonEvent(String eventName) {
    setState(() {
      _lastButtonEvent = eventName;
      _lastButtonEventTime = DateTime.now();
    });

    // Auto-clear the event after 2 seconds
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _lastButtonEventTime != null && 
          DateTime.now().difference(_lastButtonEventTime!).inSeconds >= 2) {
        setState(() {
          _lastButtonEvent = null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final deviceProvider = Provider.of<DeviceProvider>(context);
    final captureProvider = Provider.of<CaptureProvider>(context);
    final backendProvider = Provider.of<BackendProvider>(context);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Device Connection Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          deviceProvider.isConnected && deviceProvider.connectedDevice != null
                              ? 'Connected to: ${deviceProvider.connectedDevice!.name}'
                              : deviceProvider.isConnecting
                                  ? 'Connecting...'
                                  : deviceProvider.isScanning
                                      ? 'Scanning...'
                                      : 'Disconnected',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        // Scan Button
                        IconButton(
                          icon: Icon(
                            deviceProvider.isScanning 
                                ? Icons.bluetooth_searching 
                                : Icons.bluetooth,
                          ),
                          tooltip: 'Scan for Devices',
                          onPressed: deviceProvider.isScanning || deviceProvider.isConnecting
                              ? null
                              : () => deviceProvider.startScan(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (deviceProvider.isConnected && deviceProvider.connectedDevice != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Device: ${deviceProvider.connectedDevice!.name}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          Text(
                            'ID: ${deviceProvider.connectedDevice!.getShortId()}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (deviceProvider.hasBatteryInfo)
                            Row(
                              children: [
                                const Icon(Icons.battery_full, size: 16),
                                const SizedBox(width: 4),
                                Text(
                                  '${deviceProvider.batteryLevel}%',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.link_off),
                            label: const Text('Disconnect'),
                            onPressed: () => deviceProvider.disconnect(),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange.shade800,
                            ),
                          ),
                        ],
                      ),
                    if (deviceProvider.connectionState == DeviceConnectionState.disconnected &&
                        !deviceProvider.isScanning &&
                        deviceProvider.discoveredDevices.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Found Devices:', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 150,
                            child: ListView.builder(
                              itemCount: deviceProvider.discoveredDevices.length,
                              itemBuilder: (context, index) {
                                final device = deviceProvider.discoveredDevices[index];
                                return ListTile(
                                  title: Text(device.name.isEmpty ? '(Unknown Device)' : device.name),
                                  subtitle: Text(device.getShortId()),
                                  trailing: ElevatedButton(
                                    child: const Text('Connect'),
                                    onPressed: deviceProvider.isConnecting 
                                        ? null 
                                        : () => deviceProvider.connectToDevice(device.id),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Button Event Indicator
            if (_lastButtonEvent != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.touch_app, color: Colors.blue),
                      const SizedBox(width: 8),
                      Text(
                        'Button Event: $_lastButtonEvent',
                        style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            if (_lastButtonEvent != null)
              const SizedBox(height: 16),

            // Recording Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recording Controls',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          icon: Icon(
                            captureProvider.isRecording 
                                ? Icons.stop 
                                : Icons.mic,
                          ),
                          label: Text(
                            captureProvider.isRecording 
                                ? 'Stop Recording' 
                                : 'Start Recording',
                          ),
                          onPressed: deviceProvider.isConnected
                              ? () {
                                  if (captureProvider.isRecording) {
                                    captureProvider.stopRecordingAndSave();
                                  } else {
                                    captureProvider.startRecording();
                                  }
                                }
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: captureProvider.isRecording 
                                ? Colors.red 
                                : Colors.green,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Recording state
                    if (captureProvider.isRecording)
                      Column(
                        children: [
                          LinearProgressIndicator(
                            value: null, // Indeterminate
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Recording... (${captureProvider.frameCount} frames)',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    if (captureProvider.audioState == AudioProcessingState.processing)
                      Column(
                        children: [
                          LinearProgressIndicator(
                            value: null,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Processing recording...',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    if (captureProvider.audioState == AudioProcessingState.complete &&
                        captureProvider.currentRecordingPath != null)
                      Column(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.green),
                          const SizedBox(height: 8),
                          Text(
                            'Recording saved: ${captureProvider.currentRecordingPath!.split('/').last}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    if (captureProvider.audioState == AudioProcessingState.error)
                      Column(
                        children: [
                          const Icon(Icons.error, color: Colors.red),
                          const SizedBox(height: 8),
                          Text(
                            'Error saving recording',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.red,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Backend Status Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Backend Status',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Consumer<BackendProvider>(
                      builder: (context, provider, child) {
                        if (provider.isConnected) {
                          return Row(
                            children: [
                              const Icon(Icons.cloud_done, color: Colors.green),
                              const SizedBox(width: 8),
                              Text(
                                'Connected to backend',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          );
                        } else if (provider.isConnecting) {
                          return Row(
                            children: [
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Connecting to backend...',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          );
                        } else {
                          return Row(
                            children: [
                              const Icon(Icons.cloud_off, color: Colors.red),
                              const SizedBox(width: 8),
                              Text(
                                'Backend disconnected',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: () => provider.connect(),
                                child: const Text('Connect'),
                              ),
                            ],
                          );
                        }
                      },
                    ),
                    if (backendProvider.hasError && backendProvider.errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          'Error: ${backendProvider.errorMessage}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.red,
                          ),
                        ),
                      ),
                    if (backendProvider.stats != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Statistics:',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            Text(
                              '  Conversations: ${backendProvider.stats!.conversations}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            Text(
                              '  Memories: ${backendProvider.stats!.memories}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            Text(
                              '  Audio Files: ${backendProvider.stats!.audioFiles}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Audio Streaming Controls (when backend is connected)
            if (backendProvider.isConnected)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Real-time AI Processing',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Stream audio directly to your backend for real-time transcription and AI analysis.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            icon: Icon(
                              captureProvider.isRecording 
                                  ? Icons.stop 
                                  : Icons.mic,
                            ),
                            label: Text(
                              captureProvider.isRecording 
                                  ? 'Stop Streaming' 
                                  : 'Start Streaming',
                            ),
                            onPressed: deviceProvider.isConnected
                                ? () {
                                    if (captureProvider.isRecording) {
                                      captureProvider.stopBackendStreaming();
                                    } else {
                                      captureProvider.startBackendStreaming();
                                    }
                                  }
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: captureProvider.isRecording 
                                  ? Colors.red 
                                  : Colors.blue,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            ),
                          ),
                        ],
                      ),
                      if (captureProvider.isRecording)
                        Padding(
                          padding: const EdgeInsets.only(top: 12.0),
                          child: Column(
                            children: [
                              LinearProgressIndicator(value: null),
                              const SizedBox(height: 8),
                              Text(
                                'Streaming audio to backend...',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}
