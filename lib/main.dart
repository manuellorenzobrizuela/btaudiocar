import 'dart:async';
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
  static const _mediaChannel = MethodChannel('com.btaudiocar/media');

  bool _scoEnabled = false;
  bool _loading = false;
  String _status = 'Desactivado';
  String? _deviceName;
  String? _codec;

  // Media info
  String? _mediaTitle;
  String? _mediaArtist;
  bool _mediaPlaying = false;
  Timer? _mediaTimer;

  Future<void> _toggleSco() async {
    setState(() => _loading = true);
    try {
      if (_scoEnabled) {
        await _channel.invokeMethod('stopSco');
        _mediaTimer?.cancel();
        setState(() {
          _scoEnabled = false;
          _status = 'Desactivado';
          _deviceName = null;
          _codec = null;
          _mediaTitle = null;
          _mediaArtist = null;
          _mediaPlaying = false;
        });
      } else {
        final result = await _channel.invokeMethod<Map>('startSco');
        final success = result?['success'] == true;
        if (success) {
          setState(() {
            _scoEnabled = true;
            _codec = result?['codec'] as String?;
            _status = _codec != null ? 'Audio HFP activo ($_codec)' : 'Audio HFP activo';
            _deviceName = result?['deviceName'] as String?;
          });
          _startMediaPolling();
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

  void _startMediaPolling() {
    _fetchMediaInfo();
    _mediaTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _fetchMediaInfo(),
    );
  }

  Future<void> _fetchMediaInfo() async {
    try {
      final info = await _mediaChannel.invokeMethod<Map>('getNowPlaying');
      if (info != null && mounted) {
        setState(() {
          _mediaTitle = info['title'] as String?;
          _mediaArtist = info['artist'] as String?;
          _mediaPlaying = info['playing'] == true;
        });
      }
    } catch (_) {}
  }

  Future<void> _mediaCommand(String command) async {
    try {
      await _mediaChannel.invokeMethod(command);
      // Refresh info after command
      await Future.delayed(const Duration(milliseconds: 300));
      _fetchMediaInfo();
    } catch (_) {}
  }

  @override
  void dispose() {
    _mediaTimer?.cancel();
    if (_scoEnabled) {
      _channel.invokeMethod('stopSco');
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              children: [
                const SizedBox(height: 20),
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
                const SizedBox(height: 40),

                // Big power button
                GestureDetector(
                  onTap: _loading ? null : _toggleSco,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 160,
                    height: 160,
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
                            size: 70,
                            color: _scoEnabled
                                ? Colors.greenAccent
                                : Colors.grey[300],
                          ),
                  ),
                ),
                const SizedBox(height: 24),

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

                const SizedBox(height: 32),

                // Media controls (always visible when SCO active)
                if (_scoEnabled) ...[
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        // Now playing info
                        Icon(
                          Icons.music_note,
                          size: 20,
                          color: _mediaTitle != null
                              ? Colors.white70
                              : Colors.grey[600],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _mediaTitle ?? 'Sin reproducción',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: _mediaTitle != null
                                ? Colors.white
                                : Colors.grey[600],
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (_mediaArtist != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            _mediaArtist!,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[400],
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 20),

                        // Transport controls
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              onPressed: () => _mediaCommand('previous'),
                              icon: const Icon(Icons.skip_previous_rounded),
                              iconSize: 40,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 16),
                            Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: 0.15),
                              ),
                              child: IconButton(
                                onPressed: () => _mediaCommand('playPause'),
                                icon: Icon(
                                  _mediaPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                ),
                                iconSize: 48,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 16),
                            IconButton(
                              onPressed: () => _mediaCommand('next'),
                              icon: const Icon(Icons.skip_next_rounded),
                              iconSize: 40,
                              color: Colors.white,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // Info box
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      _infoRow(
                          Icons.bluetooth, 'Usa el perfil HFP (manos libres)'),
                      const SizedBox(height: 8),
                      _infoRow(
                          Icons.volume_up, 'Audio mono, calidad de llamada'),
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
