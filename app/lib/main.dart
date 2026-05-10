import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';

import 'config/app_config.dart';
import 'backend/api/omi_api_client.dart';
import 'backend/schema/bt_device/bt_device.dart';
import 'services/models.dart';
import 'providers/device_provider.dart';
import 'providers/capture_provider.dart';
import 'providers/backend_provider.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/conversations_screen.dart';
import 'screens/memories_screen.dart';
import 'screens/chat_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set FlutterBluePlus log level
  FlutterBluePlus.setLogLevel(LogLevel.warning, color: true);

  // Initialize configuration
  await AppConfig().initialize();

  // Request permissions
  await _requestPermissions();

  // Initialize Opus codec
  try {
    await initOpus(await opus_flutter.load());
    debugPrint('Opus initialized successfully');
  } catch (e) {
    debugPrint('Error initializing Opus: $e');
  }

  // Run the app
  runApp(const OmiOmniApp());
}

/// Request necessary permissions
Future<void> _requestPermissions() async {
  Map<Permission, PermissionStatus> permissionsToRequest = {};

  if (Platform.isAndroid) {
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    if (androidInfo.version.sdkInt <= 30) {
      // Android 11 (API 30) or lower
      permissionsToRequest = {
        Permission.bluetooth: await Permission.bluetooth.status,
        Permission.locationWhenInUse: await Permission.locationWhenInUse.status,
        Permission.storage: await Permission.storage.status,
      };
    } else {
      // Android 12 (API 31) or higher
      permissionsToRequest = {
        Permission.bluetoothScan: await Permission.bluetoothScan.status,
        Permission.bluetoothConnect: await Permission.bluetoothConnect.status,
        Permission.locationWhenInUse: await Permission.locationWhenInUse.status,
        Permission.storage: await Permission.storage.status,
      };
    }
  } else if (Platform.isIOS) {
    permissionsToRequest = {
      Permission.bluetooth: await Permission.bluetooth.status,
    };
  }

  // Filter out already granted permissions
  final permissionsToRequestFiltered = Map<Permission, PermissionStatus>.fromEntries(
    permissionsToRequest.entries.where((entry) => !entry.value.isGranted),
  );

  if (permissionsToRequestFiltered.isNotEmpty) {
    final statuses = await permissionsToRequestFiltered.keys.request();
    
    for (final entry in statuses.entries) {
      if (!entry.value.isGranted) {
        debugPrint('Permission denied: ${entry.key}');
      }
    }
  }
}

/// Main application widget
class OmiOmniApp extends StatelessWidget {
  const OmiOmniApp({super.key});

  @override
  Widget build(BuildContext context) {
    final config = AppConfig();

    return MultiProvider(
      providers: [
        // Configuration
        Provider<AppConfig>.value(value: config),
        
        // API Client
        Provider<OmiApiClient>(
          create: (context) => OmiApiClient(
            baseUrl: config.apiBaseUrl,
            apiKey: config.apiKey,
          ),
        ),
        
        // Device Provider
        ChangeNotifierProvider(
          create: (context) => DeviceProvider(),
        ),
        
        // Capture Provider
        ChangeNotifierProvider(
          create: (context) => CaptureProvider(),
        ),
        
        // Backend Provider
        ChangeNotifierProvider(
          create: (context) => BackendProvider(),
        ),
      ],
      child: MaterialApp(
        title: 'Omi Omni',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: config.useDarkTheme ? Colors.blue : Colors.blue.shade800,
            brightness: config.useDarkTheme ? Brightness.dark : Brightness.light,
          ),
          useMaterial3: true,
          brightness: config.useDarkTheme ? Brightness.dark : Brightness.light,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
          brightness: Brightness.dark,
        ),
        themeMode: config.useDarkTheme ? ThemeMode.dark : ThemeMode.light,
        home: const MainScreen(),
        routes: {
          '/home': (context) => const MainScreen(),
          '/settings': (context) => const SettingsScreen(),
          '/conversations': (context) => const ConversationsScreen(),
          '/memories': (context) => const MemoriesScreen(),
          '/chat': (context) => const ChatScreen(),
        },
      ),
    );
  }
}

/// Main screen with navigation
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final config = Provider.of<AppConfig>(context);
    final deviceProvider = Provider.of<DeviceProvider>(context);
    final backendProvider = Provider.of<BackendProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Omi Omni'),
        actions: [
          // Backend status indicator
          Consumer<BackendProvider>(
            builder: (context, provider, child) {
              if (provider.isConnected) {
                return IconButton(
                  icon: const Icon(Icons.cloud_done, color: Colors.green),
                  tooltip: 'Backend connected',
                  onPressed: null,
                );
              } else if (provider.isConnecting) {
                return IconButton(
                  icon: const Icon(Icons.cloud_upload, color: Colors.orange),
                  tooltip: 'Connecting to backend...',
                  onPressed: null,
                );
              } else {
                return IconButton(
                  icon: const Icon(Icons.cloud_off, color: Colors.red),
                  tooltip: 'Backend disconnected',
                  onPressed: () => provider.connect(),
                );
              }
            },
          ),
          // Settings button
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          HomeScreen(),
          ConversationsScreen(),
          MemoriesScreen(),
          ChatScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Conversations',
          ),
          NavigationDestination(
            icon: Icon(Icons.memory_outlined),
            selectedIcon: Icon(Icons.memory),
            label: 'Memories',
          ),
          NavigationDestination(
            icon: Icon(Icons.smart_toy_outlined),
            selectedIcon: Icon(Icons.smart_toy),
            label: 'Chat',
          ),
        ],
      ),
    );
  }
}
