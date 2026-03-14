import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const BTAudioCarApp());
}

class BTAudioCarApp extends StatelessWidget {
  const BTAudioCarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BT Audio Car',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1565C0),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _channel = MethodChannel('com.btaudiocar/sco');

  bool _scoEnabled = false;
  bool _loading = false;
  String _status = 'Desactivado';
  String? _deviceName;

  Future<void> _toggleSco() async {
    setState(() => _loading = true);
    try {
      if (_scoEnabled) {
        await _channel.invokeMethod('stopSco');
        setState(() {
          _scoEnabled = false;
          _status = 'Desactivado';
          _deviceName = null;
        });
      } else {
        final result = await _channel.invokeMethod<Map>('startSco');
        final success = result?['success'] == true;
        if (success) {
          setState(() {
            _scoEnabled = true;
            _status = 'Audio SCO activo';
            _deviceName = result?['deviceName'] as String?;
          });
        } else {
          final error = result?['error'] as String? ?? 'Error desconocido';
          setState(() => _status = error);
        }
      }
    } on PlatformException catch (e) {
      setState(() => _status = 'Error: ${e.message}');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    if (_scoEnabled) {
      _channel.invokeMethod('stopSco');
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'BT Audio Car',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Audio por manos libres Bluetooth',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[400],
                  ),
                ),
                const SizedBox(height: 60),

                // Big power button
                GestureDetector(
                  onTap: _loading ? null : _toggleSco,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _scoEnabled
                          ? const Color(0xFF1B5E20)
                          : const Color(0xFF37474F),
                      boxShadow: [
                        BoxShadow(
                          color: _scoEnabled
                              ? Colors.green.withValues(alpha: 0.4)
                              : Colors.black.withValues(alpha: 0.3),
                          blurRadius: 20,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: _loading
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 3,
                            ),
                          )
                        : Icon(
                            _scoEnabled
                                ? Icons.bluetooth_audio
                                : Icons.bluetooth,
                            size: 80,
                            color: _scoEnabled
                                ? Colors.greenAccent
                                : Colors.grey[300],
                          ),
                  ),
                ),
                const SizedBox(height: 40),

                // Status
                Text(
                  _status,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: _scoEnabled ? Colors.greenAccent : Colors.grey[400],
                  ),
                  textAlign: TextAlign.center,
                ),

                if (_deviceName != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.directions_car,
                          size: 18, color: Colors.grey[400]),
                      const SizedBox(width: 6),
                      Text(
                        _deviceName!,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[400],
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 60),

                // Info
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      _infoRow(Icons.bluetooth, 'Usa el perfil HFP (manos libres)'),
                      const SizedBox(height: 8),
                      _infoRow(Icons.volume_up, 'Audio mono, calidad de llamada'),
                      const SizedBox(height: 8),
                      _infoRow(Icons.music_note,
                          'Pon tu app de música y sonará por los altavoces del coche'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[500]),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        ),
      ],
    );
  }
}
