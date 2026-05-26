import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

void main() {
  runApp(const LuaSenderApp());
}

class LuaSenderApp extends StatelessWidget {
  const LuaSenderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lua Payload Sender',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00B4D8),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0A0E1A),
      ),
      home: const MainScreen(),
    );
  }
}

// ── Pantalla principal con pestañas ───────────────────────────────────────────
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          _buildHeader(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                LuaSenderTab(),
                NetcatTab(),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1224),
        border: Border(
          bottom: BorderSide(color: const Color(0xFF00B4D8).withOpacity(0.3)),
        ),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF00B4D8).withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.send_rounded,
                  color: Color(0xFF00B4D8), size: 24),
            ),
            const SizedBox(width: 12),
            const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Payload Sender',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                      color: Colors.white)),
              Text('PS4 / PS5 TCP Sender',
                  style: TextStyle(fontSize: 12, color: Color(0xFF00B4D8))),
            ]),
          ]),
        ),
        TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF00B4D8),
          indicatorWeight: 2,
          labelColor: const Color(0xFF00B4D8),
          unselectedLabelColor: Colors.white38,
          labelStyle: const TextStyle(
              fontWeight: FontWeight.w600, fontSize: 13),
          tabs: const [
            Tab(icon: Icon(Icons.code_rounded, size: 18), text: 'Lua Sender'),
            Tab(icon: Icon(Icons.terminal_rounded, size: 18), text: 'NetCat'),
          ],
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PESTAÑA 1 — LUA SENDER (igual que antes)
// ═══════════════════════════════════════════════════════════════════════════════
class LuaSenderTab extends StatefulWidget {
  const LuaSenderTab({super.key});

  @override
  State<LuaSenderTab> createState() => _LuaSenderTabState();
}

class _LuaSenderTabState extends State<LuaSenderTab> {
  final _ipController   = TextEditingController(text: '192.168.1.');
  final _portController = TextEditingController(text: '9026');
  final _logScrollCtrl  = ScrollController();

  String? _selectedFilePath;
  String? _selectedFileName;
  bool _isSending = false;
  final List<_LogEntry> _logs = [];

  Socket?          _socket;
  Completer<void>? _completer;

  static final Uint8List _magicValue = _u64LE(0x13371337);
  static const int _signalLen   = 16;
  static const int _mcontextLen = 0x100;

  static Uint8List _u64LE(int value) {
    final b = ByteData(8);
    b.setUint64(0, value, Endian.little);
    return b.buffer.asUint8List();
  }

  @override
  void initState() {
    super.initState();
    _initForegroundTask();
  }

  void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'lua_sender_channel',
        channelName: 'Lua Payload Sender',
        channelDescription: 'Manteniendo conexión activa',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
        allowWifiLock: true,
      ),
    );
  }

  Future<void> _startForegroundService() async {
    final perm = await FlutterForegroundTask.requestNotificationPermission();
    if (perm != NotificationPermission.granted) return;
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.restartService();
    } else {
      await FlutterForegroundTask.startService(
        serviceId: 256,
        notificationTitle: 'Lua Payload Sender',
        notificationText: 'Enviando payload… conexión activa',
      );
    }
  }

  Future<void> _stopForegroundService() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }

  void _log(String msg, LogType type) {
    if (!mounted) return;
    setState(() => _logs.add(_LogEntry(msg, type, DateTime.now())));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollCtrl.hasClients) {
        _logScrollCtrl.animateTo(
          _logScrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: false);
      if (result != null && result.files.single.path != null) {
        setState(() {
          _selectedFilePath = result.files.single.path;
          _selectedFileName = result.files.single.name;
        });
        _log('Archivo: ${result.files.single.name}', LogType.info);
      }
    } catch (e) {
      _log('Error al seleccionar: $e', LogType.error);
    }
  }

  Future<void> _stopPayload() async {
    _log('Deteniendo conexión…', LogType.warning);
    if (!(_completer?.isCompleted ?? true)) _completer!.complete();
    _socket?.destroy();
    _socket = null;
    await WakelockPlus.disable();
    await _stopForegroundService();
    setState(() => _isSending = false);
    _log('─── Conexión detenida manualmente ───', LogType.warning);
  }

  Future<void> _sendPayload() async {
    final ip      = _ipController.text.trim();
    final portStr = _portController.text.trim();

    if (ip.isEmpty) { _log('Ingresa una IP válida', LogType.error); return; }
    final port = int.tryParse(portStr);
    if (port == null || port < 1 || port > 65535) {
      _log('Puerto inválido', LogType.error); return;
    }
    if (_selectedFilePath == null) {
      _log('Selecciona un archivo primero', LogType.error); return;
    }

    setState(() => _isSending = true);

    try {
      final file = File(_selectedFilePath!);
      if (!await file.exists()) {
        _log('El archivo no existe en disco', LogType.error);
        setState(() => _isSending = false);
        return;
      }
      final fileBytes = await file.readAsBytes();
      _log('Archivo leído — ${fileBytes.length} bytes', LogType.info);

      await WakelockPlus.enable();
      _log('Conectando a $ip:$port …', LogType.info);
      _socket = await Socket.connect(ip, port,
          timeout: const Duration(seconds: 10));
      _log('✓ Conexión establecida', LogType.success);

      await _startForegroundService();

      final sizeBytes = ByteData(8);
      sizeBytes.setUint64(0, fileBytes.length, Endian.little);
      final packet = Uint8List(8 + fileBytes.length);
      packet.setRange(0, 8, sizeBytes.buffer.asUint8List());
      packet.setRange(8, packet.length, fileBytes);

      _socket!.add(packet);
      await _socket!.flush();
      _log('✓ Payload enviado — ${fileBytes.length} bytes', LogType.success);
      _log('Escuchando respuesta de la consola…', LogType.info);

      await _processIncomingData(_socket!);

    } on SocketException catch (e) {
      _log('Error de socket: ${e.message}', LogType.error);
      _log('Verifica IP, puerto y red local', LogType.warning);
    } on FileSystemException catch (e) {
      _log('Error de archivo: ${e.message}', LogType.error);
    } catch (e) {
      if (!e.toString().contains('cancelled')) {
        _log('Error: $e', LogType.error);
      }
    } finally {
      _socket?.destroy();
      _socket = null;
      await WakelockPlus.disable();
      await _stopForegroundService();
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _processIncomingData(Socket socket) async {
    var buffer = Uint8List(0);
    _completer = Completer<void>();

    socket.listen(
      (chunk) {
        buffer = _concat(buffer, Uint8List.fromList(chunk));
        buffer = _processBuffer(buffer);
      },
      onDone: () {
        if (buffer.isNotEmpty) {
          final text = _decodeLatin1(buffer).trim();
          if (text.isNotEmpty) _log(text, LogType.info);
        }
        _log('─── Conexión cerrada por la consola ───', LogType.warning);
        if (!(_completer?.isCompleted ?? true)) _completer!.complete();
      },
      onError: (e) {
        if (!(_completer?.isCompleted ?? true)) {
          _log('─── Conexión cerrada por la consola ───', LogType.warning);
          _completer!.complete();
        }
      },
      cancelOnError: true,
    );

    await _completer!.future;
  }

  Uint8List _processBuffer(Uint8List buffer) {
    while (true) {
      if (buffer.length < 8) break;
      final magicIndex = _findBytes(buffer, _magicValue);
      if (magicIndex == -1) break;
      final needed = magicIndex + 8 + _signalLen + _mcontextLen;
      if (buffer.length < needed) break;
      if (magicIndex > 0) {
        final text = _decodeLatin1(buffer.sublist(0, magicIndex)).trim();
        if (text.isNotEmpty) _log(text, LogType.info);
      }
      final start     = magicIndex + 8;
      final magicData = buffer.sublist(start, start + _signalLen);
      final mctxData  = buffer.sublist(
          start + _signalLen, start + _signalLen + _mcontextLen);
      _processCrashData(magicData, mctxData);
      buffer = buffer.sublist(start + _signalLen + _mcontextLen);
    }
    if (_findBytes(buffer, _magicValue) == -1 && buffer.isNotEmpty) {
      final text = _decodeLatin1(buffer).trim();
      if (text.isNotEmpty) _log(text, LogType.info);
      return Uint8List(0);
    }
    return buffer;
  }

  void _processCrashData(Uint8List magicData, Uint8List mctxData) {
    final bd = ByteData.sublistView(magicData);
    final crashCode    = bd.getUint64(0, Endian.little);
    final crashAddress = bd.getUint64(8, Endian.little);
    final signals      = {4: 'SIGILL', 10: 'SIGBUS', 11: 'SIGSEGV'};
    final sigName      = signals[crashCode] ?? 'Signal $crashCode';
    _log('💥 CRASH: $sigName en 0x${crashAddress.toRadixString(16).padLeft(16, '0')}',
        LogType.error);
  }

  static Uint8List _concat(Uint8List a, Uint8List b) {
    final r = Uint8List(a.length + b.length);
    r.setRange(0, a.length, a);
    r.setRange(a.length, r.length, b);
    return r;
  }

  static int _findBytes(Uint8List haystack, Uint8List needle) {
    outer:
    for (int i = 0; i <= haystack.length - needle.length; i++) {
      for (int j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) continue outer;
      }
      return i;
    }
    return -1;
  }

  static String _decodeLatin1(Uint8List bytes) => String.fromCharCodes(bytes);

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _logScrollCtrl.dispose();
    _socket?.destroy();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildConnectionCard(),
          const SizedBox(height: 16),
          _buildFileCard(),
          const SizedBox(height: 16),
          _buildButtons(),
          const SizedBox(height: 16),
          _buildLogCard(),
        ],
      ),
    );
  }

  Widget _buildConnectionCard() {
    return _Card(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(Icons.router_rounded, 'Conexión'),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(flex: 3, child: _Field(
            ctrl: _ipController, label: 'Dirección IP', hint: '192.168.1.x',
            icon: Icons.lan_rounded,
            inputType: const TextInputType.numberWithOptions(decimal: true),
            formatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          )),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: _Field(
            ctrl: _portController, label: 'Puerto', hint: '9026',
            icon: Icons.cable_rounded,
            inputType: TextInputType.number,
            formatters: [FilteringTextInputFormatter.digitsOnly],
          )),
        ]),
      ],
    ));
  }

  Widget _buildFileCard() {
    return _Card(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(Icons.code_rounded, 'Archivo Payload'),
        const SizedBox(height: 12),
        _FilePicker(
          fileName: _selectedFileName,
          filePath: _selectedFilePath,
          onTap: _isSending ? null : _pickFile,
        ),
      ],
    ));
  }

  Widget _buildButtons() {
    return Row(children: [
      Expanded(flex: 3, child: SizedBox(
        height: 54,
        child: ElevatedButton(
          onPressed: _isSending ? null : _sendPayload,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00B4D8),
            disabledBackgroundColor: const Color(0xFF00B4D8).withOpacity(0.3),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            shadowColor: const Color(0xFF00B4D8).withOpacity(0.4),
            elevation: _isSending ? 0 : 4,
          ),
          child: _isSending
              ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white)),
                  SizedBox(width: 8),
                  Text('Enviando…',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ])
              : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.rocket_launch_rounded, size: 18),
                  SizedBox(width: 8),
                  Text('Enviar Payload',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ]),
        ),
      )),
      const SizedBox(width: 12),
      Expanded(flex: 2, child: SizedBox(
        height: 54,
        child: ElevatedButton(
          onPressed: _isSending ? _stopPayload : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF4757),
            disabledBackgroundColor: const Color(0xFF1A1F30),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            elevation: _isSending ? 4 : 0,
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.stop_rounded, size: 18,
                color: _isSending ? Colors.white : Colors.white24),
            const SizedBox(width: 8),
            Text('Detener', style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600,
                color: _isSending ? Colors.white : Colors.white24)),
          ]),
        ),
      )),
    ]);
  }

  Widget _buildLogCard() {
    return _Card(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const _SectionTitle(Icons.terminal_rounded, 'Consola'),
          const Spacer(),
          if (_logs.isNotEmpty)
            InkWell(
              onTap: () => setState(() => _logs.clear()),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.delete_outline_rounded,
                    color: Colors.white.withOpacity(0.4), size: 18),
              ),
            ),
        ]),
        const SizedBox(height: 10),
        _LogBox(logs: _logs, scrollCtrl: _logScrollCtrl),
      ],
    ));
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PESTAÑA 2 — NETCAT
// ═══════════════════════════════════════════════════════════════════════════════
class NetcatTab extends StatefulWidget {
  const NetcatTab({super.key});

  @override
  State<NetcatTab> createState() => _NetcatTabState();
}

class _NetcatTabState extends State<NetcatTab> {
  final _ipController   = TextEditingController(text: '192.168.1.');
  final _portController = TextEditingController(text: '9021');
  final _logScrollCtrl  = ScrollController();

  String? _selectedFilePath;
  String? _selectedFileName;
  bool _isSending = false;
  final List<_LogEntry> _logs = [];

  Socket?          _socket;
  Completer<void>? _completer;

  void _log(String msg, LogType type) {
    if (!mounted) return;
    setState(() => _logs.add(_LogEntry(msg, type, DateTime.now())));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollCtrl.hasClients) {
        _logScrollCtrl.animateTo(
          _logScrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: false);
      if (result != null && result.files.single.path != null) {
        setState(() {
          _selectedFilePath = result.files.single.path;
          _selectedFileName = result.files.single.name;
        });
        _log('Archivo: ${result.files.single.name}', LogType.info);
      }
    } catch (e) {
      _log('Error al seleccionar: $e', LogType.error);
    }
  }

  Future<void> _stopSending() async {
    _log('Deteniendo…', LogType.warning);
    if (!(_completer?.isCompleted ?? true)) _completer!.complete();
    _socket?.destroy();
    _socket = null;
    await WakelockPlus.disable();
    setState(() => _isSending = false);
    _log('─── Detenido manualmente ───', LogType.warning);
  }

  // Envío estilo NetCat: bytes raw sin ningún header (nc -w3 ip port < file)
  Future<void> _sendNetcat() async {
    final ip      = _ipController.text.trim();
    final portStr = _portController.text.trim();

    if (ip.isEmpty) { _log('Ingresa una IP válida', LogType.error); return; }
    final port = int.tryParse(portStr);
    if (port == null || port < 1 || port > 65535) {
      _log('Puerto inválido', LogType.error); return;
    }
    if (_selectedFilePath == null) {
      _log('Selecciona un archivo primero', LogType.error); return;
    }

    setState(() => _isSending = true);

    try {
      final file = File(_selectedFilePath!);
      if (!await file.exists()) {
        _log('El archivo no existe en disco', LogType.error);
        setState(() => _isSending = false);
        return;
      }

      final fileBytes = await file.readAsBytes();
      _log('Archivo leído — ${fileBytes.length} bytes', LogType.info);

      await WakelockPlus.enable();
      _log('Conectando a $ip:$port …', LogType.info);

      _socket = await Socket.connect(ip, port,
          timeout: const Duration(seconds: 10));
      _log('✓ Conexión establecida', LogType.success);

      // Envío raw sin headers — igual que NetCat
      _socket!.add(fileBytes);
      await _socket!.flush();
      _log('✓ Enviado — ${fileBytes.length} bytes', LogType.success);
      _log('Esperando respuesta…', LogType.info);

      // Escuchar respuesta
      _completer = Completer<void>();
      _socket!.listen(
        (chunk) {
          final text = String.fromCharCodes(chunk).trim();
          if (text.isNotEmpty) _log(text, LogType.info);
        },
        onDone: () {
          _log('─── Conexión cerrada ───', LogType.warning);
          if (!(_completer?.isCompleted ?? true)) _completer!.complete();
        },
        onError: (e) {
          if (!(_completer?.isCompleted ?? true)) {
            _log('─── Conexión cerrada ───', LogType.warning);
            _completer!.complete();
          }
        },
        cancelOnError: true,
      );

      await _completer!.future;

    } on SocketException catch (e) {
      _log('Error de socket: ${e.message}', LogType.error);
      _log('Verifica IP, puerto y red local', LogType.warning);
    } on FileSystemException catch (e) {
      _log('Error de archivo: ${e.message}', LogType.error);
    } catch (e) {
      if (!e.toString().contains('cancelled')) {
        _log('Error: $e', LogType.error);
      }
    } finally {
      _socket?.destroy();
      _socket = null;
      await WakelockPlus.disable();
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _logScrollCtrl.dispose();
    _socket?.destroy();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Card(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle(Icons.router_rounded, 'Conexión'),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(flex: 3, child: _Field(
                  ctrl: _ipController, label: 'Dirección IP', hint: '192.168.1.x',
                  icon: Icons.lan_rounded,
                  inputType: const TextInputType.numberWithOptions(decimal: true),
                  formatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                )),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: _Field(
                  ctrl: _portController, label: 'Puerto', hint: '9090',
                  icon: Icons.cable_rounded,
                  inputType: TextInputType.number,
                  formatters: [FilteringTextInputFormatter.digitsOnly],
                )),
              ]),
            ],
          )),
          const SizedBox(height: 16),
          _Card(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle(Icons.attach_file_rounded, 'Archivo'),
              const SizedBox(height: 12),
              _FilePicker(
                fileName: _selectedFileName,
                filePath: _selectedFilePath,
                onTap: _isSending ? null : _pickFile,
              ),
            ],
          )),
          const SizedBox(height: 16),
          // Botones
          Row(children: [
            Expanded(flex: 3, child: SizedBox(
              height: 54,
              child: ElevatedButton(
                onPressed: _isSending ? null : _sendNetcat,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00B4D8),
                  disabledBackgroundColor:
                      const Color(0xFF00B4D8).withOpacity(0.3),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: _isSending ? 0 : 4,
                ),
                child: _isSending
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(width: 16, height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white)),
                          SizedBox(width: 8),
                          Text('Enviando…',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w600)),
                        ])
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.upload_rounded, size: 18),
                          SizedBox(width: 8),
                          Text('Enviar',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w600)),
                        ]),
              ),
            )),
            const SizedBox(width: 12),
            Expanded(flex: 2, child: SizedBox(
              height: 54,
              child: ElevatedButton(
                onPressed: _isSending ? _stopSending : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF4757),
                  disabledBackgroundColor: const Color(0xFF1A1F30),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: _isSending ? 4 : 0,
                ),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  Icon(Icons.stop_rounded, size: 18,
                      color: _isSending ? Colors.white : Colors.white24),
                  const SizedBox(width: 8),
                  Text('Detener',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600,
                          color: _isSending ? Colors.white : Colors.white24)),
                ]),
              ),
            )),
          ]),
          const SizedBox(height: 16),
          _Card(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const _SectionTitle(Icons.terminal_rounded, 'Respuesta'),
                const Spacer(),
                if (_logs.isNotEmpty)
                  InkWell(
                    onTap: () => setState(() => _logs.clear()),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.delete_outline_rounded,
                          color: Colors.white.withOpacity(0.4), size: 18),
                    ),
                  ),
              ]),
              const SizedBox(height: 10),
              _LogBox(logs: _logs, scrollCtrl: _logScrollCtrl),
            ],
          )),
        ],
      ),
    );
  }
}

// ── Widgets compartidos ───────────────────────────────────────────────────────

class _FilePicker extends StatelessWidget {
  final String? fileName;
  final String? filePath;
  final VoidCallback? onTap;
  const _FilePicker({this.fileName, this.filePath, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF141929),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: fileName != null
                ? const Color(0xFF2DC653).withOpacity(0.5)
                : const Color(0xFF00B4D8).withOpacity(0.2),
          ),
        ),
        child: Row(children: [
          Icon(
            fileName != null
                ? Icons.check_circle_rounded : Icons.folder_open_rounded,
            color: fileName != null
                ? const Color(0xFF2DC653) : const Color(0xFF00B4D8),
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                fileName ?? 'Toca para seleccionar archivo',
                style: TextStyle(
                  color: fileName != null
                      ? Colors.white : Colors.white.withOpacity(0.4),
                  fontSize: 14,
                  fontWeight: fileName != null
                      ? FontWeight.w500 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              if (filePath != null)
                Text(filePath!,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.3), fontSize: 10),
                    overflow: TextOverflow.ellipsis),
            ],
          )),
          Icon(Icons.chevron_right_rounded,
              color: Colors.white.withOpacity(0.3)),
        ]),
      ),
    );
  }
}

class _LogBox extends StatelessWidget {
  final List<_LogEntry> logs;
  final ScrollController scrollCtrl;
  const _LogBox({required this.logs, required this.scrollCtrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 240,
      decoration: BoxDecoration(
        color: const Color(0xFF080D18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF00B4D8).withOpacity(0.1)),
      ),
      child: logs.isEmpty
          ? Center(child: Text('Sin actividad aún…',
              style: TextStyle(color: Colors.white.withOpacity(0.2),
                  fontFamily: 'monospace', fontSize: 13)))
          : ListView.builder(
              controller: scrollCtrl,
              padding: const EdgeInsets.all(10),
              itemCount: logs.length,
              itemBuilder: (_, i) {
                final e = logs[i];
                final t = e.time;
                final ts =
                    '[${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')}:${t.second.toString().padLeft(2,'0')}] ';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ts, style: TextStyle(
                          color: Colors.white.withOpacity(0.3),
                          fontFamily: 'monospace', fontSize: 11)),
                      Expanded(child: Text(e.message, style: TextStyle(
                          color: e.type.color,
                          fontFamily: 'monospace', fontSize: 11))),
                    ],
                  ),
                );
              }),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF0D1224),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFF00B4D8).withOpacity(0.15)),
    ),
    child: child,
  );
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String text;
  const _SectionTitle(this.icon, this.text);
  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, color: const Color(0xFF00B4D8), size: 18),
    const SizedBox(width: 8),
    Text(text, style: const TextStyle(
        color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
  ]);
}

class _Field extends StatelessWidget {
  final TextEditingController ctrl;
  final String label, hint;
  final IconData icon;
  final TextInputType? inputType;
  final List<TextInputFormatter>? formatters;
  const _Field({
    required this.ctrl, required this.label,
    required this.hint,  required this.icon,
    this.inputType, this.formatters,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(
          color: Color(0xFF8B9DC3), fontSize: 12, fontWeight: FontWeight.w500)),
      const SizedBox(height: 6),
      TextField(
        controller: ctrl,
        keyboardType: inputType,
        inputFormatters: formatters,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.2)),
          prefixIcon: Icon(icon, color: const Color(0xFF00B4D8), size: 18),
          filled: true, fillColor: const Color(0xFF141929),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                  color: const Color(0xFF00B4D8).withOpacity(0.2))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                  color: const Color(0xFF00B4D8).withOpacity(0.2))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(
                  color: Color(0xFF00B4D8), width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(
              vertical: 12, horizontal: 12),
        ),
      ),
    ],
  );
}

// ── Modelos ───────────────────────────────────────────────────────────────────

enum LogType {
  info, success, warning, error;
  Color get color => switch (this) {
    LogType.info    => const Color(0xFF8B9DC3),
    LogType.success => const Color(0xFF2DC653),
    LogType.warning => const Color(0xFFFFB703),
    LogType.error   => const Color(0xFFFF4757),
  };
}

class _LogEntry {
  final String message;
  final LogType type;
  final DateTime time;
  const _LogEntry(this.message, this.type, this.time);
}