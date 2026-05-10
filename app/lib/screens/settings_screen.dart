import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../config/app_config.dart';
import '../providers/backend_provider.dart';
import '../providers/device_provider.dart';

/// Settings Screen
/// Application settings and configuration
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _appVersion;
  String? _buildNumber;

  @override
  void initState() {
    super.initState();
    _loadAppInfo();
  }

  Future<void> _loadAppInfo() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      setState(() {
        _appVersion = packageInfo.version;
        _buildNumber = packageInfo.buildNumber;
      });
    } catch (e) {
      debugPrint('Error loading package info: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = Provider.of<AppConfig>(context);
    final backendProvider = Provider.of<BackendProvider>(context);
    final deviceProvider = Provider.of<DeviceProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          // Backend Configuration Section
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Backend Configuration',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // API Base URL
                  Text(
                    'API Base URL',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    config.apiBaseUrl,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  
                  // Connection Status
                  Row(
                    children: [
                      Text(
                        'Status: ',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      Consumer<BackendProvider>(
                        builder: (context, provider, child) {
                          if (provider.isConnected) {
                            return const Text(
                              'Connected',
                              style: TextStyle(color: Colors.green),
                            );
                          } else if (provider.isConnecting) {
                            return const Text(
                              'Connecting...',
                              style: TextStyle(color: Colors.orange),
                            );
                          } else {
                            return const Text(
                              'Disconnected',
                              style: TextStyle(color: Colors.red),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  
                  // Connect/Disconnect buttons
                  Row(
                    children: [
                      if (backendProvider.isConnected)
                        ElevatedButton.icon(
                          icon: const Icon(Icons.link_off),
                          label: const Text('Disconnect'),
                          onPressed: () => backendProvider.disconnect(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                          ),
                        ),
                      if (!backendProvider.isConnected)
                        ElevatedButton.icon(
                          icon: const Icon(Icons.link),
                          label: const Text('Connect'),
                          onPressed: () => backendProvider.connect(),
                        ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: const Text('Refresh'),
                        onPressed: () => backendProvider.refreshStats(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          // Device Configuration Section
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Device Configuration',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Device Status
                  Row(
                    children: [
                      Text(
                        'Status: ',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      Consumer<DeviceProvider>(
                        builder: (context, provider, child) {
                          if (provider.isConnected) {
                            return const Text(
                              'Connected',
                              style: TextStyle(color: Colors.green),
                            );
                          } else if (provider.isConnecting) {
                            return const Text(
                              'Connecting...',
                              style: TextStyle(color: Colors.orange),
                            );
                          } else if (provider.isScanning) {
                            return const Text(
                              'Scanning...',
                              style: TextStyle(color: Colors.blue),
                            );
                          } else {
                            return const Text(
                              'Disconnected',
                              style: TextStyle(color: Colors.red),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  
                  // Connected Device Info
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
                          Text(
                            'Battery: ${deviceProvider.batteryLevel}%',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.link_off),
                          label: const Text('Disconnect Device'),
                          onPressed: () => deviceProvider.disconnect(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                          ),
                        ),
                      ],
                    ),
                  
                  // Scan for Devices button
                  if (!deviceProvider.isConnected)
                    ElevatedButton.icon(
                      icon: const Icon(Icons.bluetooth_searching),
                      label: const Text('Scan for Devices'),
                      onPressed: () => deviceProvider.startScan(),
                    ),
                ],
              ),
            ),
          ),
          
          // Feature Flags Section
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Feature Flags',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('AI Processing'),
                    subtitle: const Text('Enable real-time AI transcription and analysis'),
                    value: config.enableAiProcessing,
                    onChanged: (value) {
                      config.enableAiProcessing = value;
                      setState(() {});
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Offline Recording'),
                    subtitle: const Text('Save recordings locally when offline'),
                    value: config.enableOfflineRecording,
                    onChanged: (value) {
                      config.enableOfflineRecording = value;
                      setState(() {});
                    },
                  ),
                  SwitchListTile(
                    title: const Text('OTA Updates'),
                    subtitle: const Text('Enable over-the-air firmware updates'),
                    value: config.enableOtaUpdates,
                    onChanged: (value) {
                      config.enableOtaUpdates = value;
                      setState(() {});
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Dark Theme'),
                    subtitle: const Text('Use dark theme'),
                    value: config.useDarkTheme,
                    onChanged: (value) {
                      config.useDarkTheme = value;
                      setState(() {});
                    },
                  ),
                ],
              ),
            ),
          ),
          
          // Statistics Section
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Statistics',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Consumer<BackendProvider>(
            builder: (context, provider, child) {
              if (provider.stats == null) {
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Center(
                      child: Text(
                        'No statistics available',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ),
                );
              }
              
              final stats = provider.stats!;
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      _buildStatRow(context, 'Conversations', stats.conversations.toString()),
                      _buildStatRow(context, 'Memories', stats.memories.toString()),
                      _buildStatRow(context, 'Audio Files', stats.audioFiles.toString()),
                      _buildStatRow(context, 'Audio Storage', stats.formattedAudioSize),
                      _buildStatRow(context, 'Vectors', stats.vectors.toString()),
                    ],
                  ),
                ),
              );
            },
          ),
          
          // About Section
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'About',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Omi Omni',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Version: ${_appVersion ?? 'Unknown'} (${_buildNumber ?? 'Unknown'})',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'A self-hosted Omi AI wearable application with full local capabilities.',
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Your Omi, Your Data, Your Control',
                    style: TextStyle(fontStyle: FontStyle.italic),
                  ),
                  const SizedBox(height: 16),
                  TextButton.icon(
                    icon: const Icon(Icons.help_outline),
                    label: const Text('View Documentation'),
                    onPressed: () {
                      // TODO: Open documentation
                    },
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildStatRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
