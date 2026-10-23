import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'services/router_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MotoRouterApp());
}

class MotoRouterApp extends StatelessWidget {
  const MotoRouterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lan Router Management',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF2563EB),
          secondary: Color(0xFF6366F1),
          surface: Color(0xFF1E293B),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1E293B),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      home: const MainNavigationScreen(),
    );
  }
}

class MeshNode {
  String name;
  String ip;
  String password;
  int txPower;
  SatelliteQuality? quality;
  bool isChecking;

  MeshNode({
    required this.name,
    required this.ip,
    this.password = '',
    this.txPower = 23,
    this.quality,
    this.isChecking = false,
  });
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  bool _isConnected = false;
  String _currentIp = '192.168.1.1';
  String _currentPassword = '';
  RouterStatus? _status;
  int _currentIndex = 0;
  bool _isLoading = false;

  // Login
  final TextEditingController _ipController = TextEditingController(text: '192.168.1.1');
  final TextEditingController _passController = TextEditingController();

  // Tab 1: Router Principal & Wi-Fi State
  final TextEditingController _routerNameController = TextEditingController(text: 'Router Principal');
  bool _separateBands = false;
  final TextEditingController _ssid24Controller = TextEditingController(text: 'LanRouterWiFi');
  final TextEditingController _key24Controller = TextEditingController();
  String _enc24 = 'psk2';

  final TextEditingController _ssid5Controller = TextEditingController();
  final TextEditingController _key5Controller = TextEditingController();
  String _enc5 = 'psk2';

  int _txPower = 23; // 23 = Max (100%), 20 = Alta (75%), 17 = Media (50%), 14 = Baja (25%)
  bool _legacyMode = false; // Compatibilidad con clientes sin Wi-Fi 6 en 2.4 GHz
  bool _isPassObscure = true;

  // Red LAN & DHCP State
  bool _dhcpEnabled = true;
  final TextEditingController _lanIpController = TextEditingController(text: '192.168.1.1');
  final TextEditingController _lanNetmaskController = TextEditingController(text: '255.255.255.0');
  final TextEditingController _lanGatewayController = TextEditingController();
  final TextEditingController _dhcpStartController = TextEditingController(text: '100');
  final TextEditingController _dhcpLimitController = TextEditingController(text: '150');
  String _selectedDns = '1.1.1.1,1.0.0.1';

  // Tab 2: Agregar Satélites State (Plug & Mesh + Adopción Aérea)
  int _adoptionMode = 0; // 0: Plug & Mesh (Cable), 1: Aéreo (Wi-Fi / WPS)
  final TextEditingController _addSatMainSsidController = TextEditingController(text: 'Motorolamesh');
  final TextEditingController _addSatMainKeyController = TextEditingController();
  bool _addSatMainKeyObscure = true;
  final TextEditingController _addSatNameController = TextEditingController(text: 'Satélite 1');
  final TextEditingController _addSatPassController = TextEditingController();
  bool _addSatPassObscure = true;
  String _calculatedNextIp = '192.168.1.2';
  bool _isCalculatingIp = false;
  bool _isProvisioningSat = false;

  // Plug & Mesh (Cable)
  List<CableSatelliteCandidate> _cableCandidates = [];
  CableSatelliteCandidate? _selectedCableCandidate;
  bool _isScanningCable = false;

  // Modo Aéreo (Wi-Fi / WPS)
  List<WirelessScanResult> _detectedAirSatellites = [];
  WirelessScanResult? _selectedAirSatellite;
  bool _isScanningAir = false;
  bool _isTriggeringWps = false;

  int _mainChannel5 = 36;
  int _mainChannel24 = 6;
  String _mainBssid5 = '';
  String _mainBssid24 = '';

  // Tab 3: Control de Satélites Mesh State
  final List<MeshNode> _meshNodes = [];
  bool _isCheckingAllNodes = false;

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
        backgroundColor: isError ? Colors.redAccent : const Color(0xFF2563EB),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // Login y desbloqueo automático en Router Principal
  Future<void> _login() async {
    final ip = _ipController.text.trim();
    final pass = _passController.text.trim();
    if (ip.isEmpty || pass.isEmpty) {
      return _showSnack('Ingresa IP y Contraseña del router', isError: true);
    }

    setState(() => _isLoading = true);
    try {
      _showSnack('1/2 Desbloqueando servicios locales del router...');
      await RouterService.unlockRouter(ip, pass);
      await Future.delayed(const Duration(seconds: 2));

      _showSnack('2/2 Conectando por SSH seguro...');
      final status = await RouterService.getStatus(ip, pass);

      setState(() {
        _isConnected = true;
        _currentIp = ip;
        _currentPassword = pass;
        _status = status;
        _routerNameController.text = status.hostname;
      });

      _loadWifiConfig();
      _loadDhcpConfig();
      _showSnack('¡Conexión establecida con éxito!');
    } catch (e) {
      _showSnack('Error de conexión: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadWifiConfig() async {
    try {
      final wifi = await RouterService.getWifiConfig(_currentIp, _currentPassword);
      setState(() {
        _separateBands = wifi.separateBands;
        if (wifi.ssid24.isNotEmpty) {
          _ssid24Controller.text = wifi.ssid24;
          if (_addSatMainSsidController.text.isEmpty || _addSatMainSsidController.text == 'Motorolamesh') {
            _addSatMainSsidController.text = wifi.ssid24;
          }
        }
        if (wifi.key24.isNotEmpty) {
          _key24Controller.text = wifi.key24;
          if (_addSatMainKeyController.text.isEmpty) {
            _addSatMainKeyController.text = wifi.key24;
          }
        }
        _enc24 = wifi.enc24.isNotEmpty ? wifi.enc24 : 'psk2';

        if (wifi.ssid5.isNotEmpty) _ssid5Controller.text = wifi.ssid5;
        if (wifi.key5.isNotEmpty) _key5Controller.text = wifi.key5;
        _enc5 = wifi.enc5.isNotEmpty ? wifi.enc5 : 'psk2';

        _txPower = wifi.txPower;
        _legacyMode = wifi.legacyMode;
        _mainChannel5 = wifi.channel5;
        _mainChannel24 = wifi.channel24;
        _mainBssid5 = wifi.bssid5;
        _mainBssid24 = wifi.bssid24;
      });
    } catch (_) {}
  }

  Future<void> _loadDhcpConfig() async {
    try {
      final dhcp = await RouterService.getDhcpConfig(_currentIp, _currentPassword);
      setState(() {
        _dhcpEnabled = dhcp.dhcpEnabled;
        _dhcpStartController.text = dhcp.start.toString();
        _dhcpLimitController.text = dhcp.limit.toString();
        _selectedDns = dhcp.dns;
        if (dhcp.lanIp.isNotEmpty) _lanIpController.text = dhcp.lanIp;
        if (dhcp.netmask.isNotEmpty) _lanNetmaskController.text = dhcp.netmask;
        _lanGatewayController.text = dhcp.gateway;
      });
    } catch (_) {}
  }

  // Guardar Nombre del Equipo (Hostname)
  Future<void> _saveRouterName() async {
    final name = _routerNameController.text.trim();
    if (name.isEmpty) return _showSnack('Ingresa un nombre para el equipo', isError: true);
    setState(() => _isLoading = true);
    try {
      await RouterService.setHostname(_currentIp, _currentPassword, name);
      _showSnack('Nombre del router actualizado a "$name"');
      final s = await RouterService.getStatus(_currentIp, _currentPassword);
      setState(() => _status = s);
    } catch (e) {
      _showSnack('Error al cambiar nombre: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Apagar Minim Cloud
  Future<void> _disableMinimCloud() async {
    setState(() => _isLoading = true);
    try {
      await RouterService.disableMinim(_currentIp, _currentPassword);
      _showSnack('Agente Minim en la nube DESACTIVADO. El router opera 100% local');
      final s = await RouterService.getStatus(_currentIp, _currentPassword);
      setState(() => _status = s);
    } catch (e) {
      _showSnack('Error al apagar Minim: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Diagnóstico en vivo de hardware Broadcom y Cloud Daemon
  Future<void> _showDiagnosticDialog() async {
    _showSnack('Consultando estado interno de hardware y NVRAM...');
    try {
      final diag = await RouterService.getDiagnosticInfo(_currentIp, _currentPassword);
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.analytics_outlined, color: Colors.amberAccent),
              SizedBox(width: 8),
              Expanded(
                child: Text('Diagnóstico de Hardware', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDiagRow('Agente Minim / Unum:', diag['UNUM'] ?? 'N/A',
                    isOk: (diag['UNUM'] ?? '').contains('DETENIDO_OK')),
                _buildDiagRow('NVRAM 2.4G SSID:', diag['NVRAM_SSID'] ?? 'N/A'),
                _buildDiagRow('NVRAM 5G SSID:', diag['NVRAM_SSID5'] ?? 'N/A'),
                _buildDiagRow('Broadcom wl0 (2.4G):', diag['WL0_SSID'] ?? 'N/A'),
                _buildDiagRow('Broadcom wl1 (5G):', diag['WL1_SSID'] ?? 'N/A'),
                _buildDiagRow('OpenWrt UCI SSID:', diag['UCI_SSID'] ?? 'N/A'),
                _buildDiagRow('Hostname en Kernel:', diag['HOSTNAME'] ?? 'N/A'),
              ],
            ),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB)),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    } catch (e) {
      _showSnack('Error al obtener diagnóstico: $e', isError: true);
    }
  }

  Widget _buildDiagRow(String title, String val, {bool? isOk}) {
    Color color = Colors.white;
    if (isOk != null) {
      color = isOk ? const Color(0xFF34D399) : Colors.redAccent;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(val, style: TextStyle(fontSize: 12, color: color, fontFamily: 'monospace')),
          const Divider(color: Colors.white12, height: 10),
        ],
      ),
    );
  }

  // Cuenta regresiva animada para reinicio limpio del router
  Future<void> _showRebootCountdownDialog(String reason) async {
    int secondsLeft = 40;
    Timer? timer;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            timer ??= Timer.periodic(const Duration(seconds: 1), (t) {
              if (secondsLeft > 0) {
                setDialogState(() => secondsLeft--);
              } else {
                t.cancel();
                Navigator.of(ctx).pop();
              }
            });

            final progress = (40 - secondsLeft) / 40.0;

            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.restart_alt, color: Color(0xFF38BDF8), size: 26),
                  SizedBox(width: 10),
                  Text(
                    'Reiniciando Router',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 10),
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 90,
                        height: 90,
                        child: CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 6,
                          backgroundColor: Colors.white12,
                          color: const Color(0xFF2563EB),
                        ),
                      ),
                      Text(
                        '${secondsLeft}s',
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    reason,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'El router guardó los cambios en NVRAM y se está reiniciando de forma segura para activar el chip Broadcom sin colgarse. La app se reconectará sola.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ],
              ),
              actions: [
                if (secondsLeft == 0)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB)),
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Reconectar Ahora'),
                  ),
              ],
            );
          },
        );
      },
    );
    timer?.cancel();
    _showSnack('Reconectando al router principal...');
    await _login();
  }

  // Guardar Wi-Fi
  Future<void> _saveWifi() async {
    setState(() => _isLoading = true);
    try {
      final cfg = WifiConfigData(
        separateBands: _separateBands,
        ssid24: _ssid24Controller.text.trim(),
        key24: _key24Controller.text.trim(),
        enc24: _enc24,
        ssid5: _separateBands ? _ssid5Controller.text.trim() : _ssid24Controller.text.trim(),
        key5: _separateBands ? _key5Controller.text.trim() : _key24Controller.text.trim(),
        enc5: _separateBands ? _enc5 : _enc24,
        txPower: _txPower,
        legacyMode: _legacyMode,
      );

      await RouterService.saveWifiConfig(_currentIp, _currentPassword, cfg);
      setState(() => _isLoading = false);

      if (mounted) {
        await _showRebootCountdownDialog('Configuración Wi-Fi guardada en NVRAM');
      }
    } catch (e) {
      _showSnack('Error al guardar Wi-Fi: $e', isError: true);
      setState(() => _isLoading = false);
    }
  }

  // Guardar DHCP
  Future<void> _saveDhcp() async {
    setState(() => _isLoading = true);
    try {
      final cfg = DhcpConfigData(
        dhcpEnabled: _dhcpEnabled,
        start: int.tryParse(_dhcpStartController.text.trim()) ?? 100,
        limit: int.tryParse(_dhcpLimitController.text.trim()) ?? 150,
        dns: _selectedDns,
      );
      await RouterService.saveDhcpConfig(_currentIp, _currentPassword, cfg);
      _showSnack(_dhcpEnabled
          ? 'Servidor DHCP guardado y activado'
          : 'Servidor DHCP APAGADO correctamente');
    } catch (e) {
      _showSnack('Error al guardar DHCP: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Guardar IP LAN
  Future<void> _saveLanIp() async {
    final newIp = _lanIpController.text.trim();
    final netmask = _lanNetmaskController.text.trim();
    final gateway = _lanGatewayController.text.trim();

    if (newIp.isEmpty || netmask.isEmpty) {
      return _showSnack('La IP y la máscara son obligatorias', isError: true);
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('¿Cambiar IP LAN del router?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'El router cambiará su IP a $newIp y reiniciará su red.\n\n'
          'Deberás reconectar la app a la nueva dirección: $newIp',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar Cambio'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      await RouterService.saveLanIpConfig(
        _currentIp,
        _currentPassword,
        newIp: newIp,
        netmask: netmask,
        gateway: gateway,
        dns: gateway.isNotEmpty ? gateway : _selectedDns,
      );

      _showSnack('IP cambiada a $newIp. Reconectando...');
      setState(() {
        _currentIp = newIp;
        _ipController.text = newIp;
      });
      await Future.delayed(const Duration(seconds: 4));
      await _login();
    } catch (e) {
      _showSnack('IP guardada. Por favor conéctate a $newIp.');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // TAB 2: Calcula la siguiente IP disponible (.2, .3, .4)
  Future<void> _calculateNextIp() async {
    setState(() => _isCalculatingIp = true);
    try {
      final existingIps = _meshNodes.map((n) => n.ip).toList();
      final nextIp = await RouterService.getNextAvailableSatelliteIp(_currentIp, _currentPassword, existingIps);
      setState(() {
        _calculatedNextIp = nextIp;
        final num = nextIp.split('.').last;
        final satIndex = (int.tryParse(num) ?? 2) - 1;
        _addSatNameController.text = 'Satélite $satIndex';
      });
    } catch (_) {
      final existing = _meshNodes.map((n) => n.ip).toSet();
      for (final ip in ['192.168.1.2', '192.168.1.3', '192.168.1.4', '192.168.1.5']) {
        if (!existing.contains(ip)) {
          setState(() {
            _calculatedNextIp = ip;
            final num = ip.split('.').last;
            final satIndex = (int.tryParse(num) ?? 2) - 1;
            _addSatNameController.text = 'Satélite $satIndex';
          });
          break;
        }
      }
    } finally {
      setState(() => _isCalculatingIp = false);
    }
  }

  // TAB 2: Detectar satélites por cable conectado al router principal
  Future<void> _scanCableSatellites() async {
    setState(() => _isScanningCable = true);
    try {
      await _calculateNextIp();
      final candidates = await RouterService.findCableSatellites(_currentIp, _currentPassword);
      setState(() {
        _cableCandidates = candidates;
        if (candidates.isNotEmpty) {
          _selectedCableCandidate = candidates.first;
        }
      });
      if (candidates.isEmpty) {
        _showSnack('No se detectaron satélites conectados por cable. Verifica que el cable esté en el puerto WAN (azul) del satélite.', isError: true);
      } else {
        _showSnack('✔ ${candidates.length} dispositivo(s) detectado(s) por cable.');
      }
    } catch (e) {
      _showSnack('Error al consultar router principal: $e', isError: true);
    } finally {
      setState(() => _isScanningCable = false);
    }
  }

  // TAB 2: Buscar satélites Motorola en el aire desde el router principal
  Future<void> _scanAirSatellitesFromMain() async {
    setState(() => _isScanningAir = true);
    try {
      await _calculateNextIp();
      final nets = await RouterService.scanWirelessAir(_currentIp, _currentPassword);
      final motoNets = nets.where((n) => n.isMotorola || n.ssid.toLowerCase().contains('moto') || n.ssid.startsWith('Motorola-')).toList();
      setState(() {
        _detectedAirSatellites = motoNets.isNotEmpty ? motoNets : nets.take(6).toList();
        if (_detectedAirSatellites.isNotEmpty) {
          _selectedAirSatellite = _detectedAirSatellites.first;
        }
      });
      if (motoNets.isEmpty) {
        _showSnack('No se detectó la baliza de fábrica Motorola. Enciende el satélite cerca del principal.');
      } else {
        _showSnack('✔ ${motoNets.length} satélite(s) detectado(s) en el aire.');
      }
    } catch (e) {
      _showSnack('Error al escanear desde router principal: $e', isError: true);
    } finally {
      setState(() => _isScanningAir = false);
    }
  }

  // TAB 2: Aprovisionar por Plug & Mesh (Cable)
  Future<void> _runProvisionPlugAndMesh() async {
    if (_selectedCableCandidate == null) {
      return _showSnack('Primero pulsa "Detectar Satélite por Cable" para encontrar el equipo', isError: true);
    }
    final satPass = _addSatPassController.text.trim();
    if (satPass.isEmpty) {
      return _showSnack('Ingresa o escanea el QR de la contraseña de etiqueta del satélite', isError: true);
    }
    final satName = _addSatNameController.text.trim().isNotEmpty ? _addSatNameController.text.trim() : 'Satélite Sala';
    final mainSsid = _addSatMainSsidController.text.trim().isNotEmpty
        ? _addSatMainSsidController.text.trim()
        : (_ssid24Controller.text.trim().isNotEmpty ? _ssid24Controller.text.trim() : 'Motorolamesh');
    final mainKey = _addSatMainKeyController.text.trim().isNotEmpty
        ? _addSatMainKeyController.text.trim()
        : _key24Controller.text.trim();
    final targetIp = _calculatedNextIp;
    final tempIp = _selectedCableCandidate!.ip;

    setState(() => _isProvisioningSat = true);
    try {
      _showSnack('Sincronizando satélite en $tempIp con IP final $targetIp...');
      await RouterService.provisionSatelliteOverCable(
        tempSatIp: tempIp,
        satPassword: satPass,
        targetIp: targetIp,
        mainGateway: _currentIp,
        mainSsid: mainSsid,
        mainKey: mainKey,
        satName: satName,
        channel5: _mainChannel5,
        channel24: _mainChannel24,
      );

      final existingIdx = _meshNodes.indexWhere((n) => n.ip == targetIp);
      if (existingIdx != -1) {
        _meshNodes[existingIdx].name = satName;
        _meshNodes[existingIdx].password = satPass;
      } else {
        _meshNodes.add(MeshNode(name: satName, ip: targetIp, password: satPass));
      }

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Color(0xFF10B981), size: 28),
                SizedBox(width: 10),
                Expanded(child: Text('¡Satélite Vinculado!', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold))),
              ],
            ),
            content: Text(
              '🎉 ¡Malla Mesh creada con éxito!\n\n'
              '• Equipo: $satName\n'
              '• IP Asignada: $targetIp\n'
              '• Red Wi-Fi: $mainSsid\n'
              '• Modo: Switch Universal (1 Gbps) + Backhaul Wi-Fi 5 GHz\n\n'
              '🔌 ¿QUÉ HACER AHORA?\n'
              'Ya puedes DESCONECTAR el cable de red del satélite y ubicarlo en la sala, habitación o donde quieras.\n\n'
              'Al encenderlo en su lugar definitivo, se enlazará al router principal 100% de forma inalámbrica.',
              style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() => _currentIndex = 2); // Ir a Control Satélites
                },
                child: const Text('Entendido, Ver en Malla', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      _showSnack('Error al aprovisionar: $e', isError: true);
    } finally {
      setState(() => _isProvisioningSat = false);
    }
  }

  // TAB 2: Disparar Emparejamiento WPS en el Router Principal
  Future<void> _triggerWpsPairing() async {
    setState(() => _isTriggeringWps = true);
    try {
      _showSnack('Activando ventana de enlace WPS en Router Principal por 2 minutos...');
      final ok = await RouterService.triggerWps(_currentIp, _currentPassword);
      if (ok) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.wifi_protected_setup, color: Color(0xFF38BDF8), size: 28),
                SizedBox(width: 10),
                Text('WPS Activado', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ],
            ),
            content: const Text(
              'La ventana de emparejamiento WPS está ABIERTA en tu Router Principal.\n\n'
              '👉 Presiona el botón WPS en el satélite Motorola ahora.\n\n'
              'Ambos routers negociarán las credenciales de tu red Wi-Fi y se enlazarán automáticamente.',
              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar', style: TextStyle(color: Color(0xFF60A5FA))),
              ),
            ],
          ),
        );
      } else {
        _showSnack('No se pudo activar WPS en el router principal', isError: true);
      }
    } catch (e) {
      _showSnack('Error activando WPS: $e', isError: true);
    } finally {
      setState(() => _isTriggeringWps = false);
    }
  }

  // Escáner QR para etiquetas de router
  Map<String, String> _parseRouterQr(String raw) {
    final result = <String, String>{};
    final trimmed = raw.trim();

    // 1. Estándar Wi-Fi Alliance: WIFI:S:ssid;T:WPA;P:password;;
    if (trimmed.toUpperCase().startsWith('WIFI:')) {
      final body = trimmed.substring(5);
      final tokens = body.split(';');
      for (final tok in tokens) {
        if (tok.toUpperCase().startsWith('S:')) {
          result['ssid'] = tok.substring(2).trim();
        } else if (tok.toUpperCase().startsWith('P:')) {
          result['password'] = tok.substring(2).trim();
        } else if (tok.toUpperCase().startsWith('T:')) {
          result['encryption'] = tok.substring(2).trim();
        }
      }
      return result;
    }

    // 2. Formato JSON
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      try {
        final map = jsonDecode(trimmed) as Map<String, dynamic>;
        if (map.containsKey('password')) result['password'] = map['password'].toString();
        if (map.containsKey('key')) result['password'] = map['key'].toString();
        if (map.containsKey('ssid')) result['ssid'] = map['ssid'].toString();
        return result;
      } catch (_) {}
    }

    // 3. Delimitadores clave=valor
    if (trimmed.contains(';') || trimmed.contains('&') || trimmed.contains(',')) {
      final pMatch = RegExp(r'(?:pass|pwd|password|key|wpa_psk)=([^;,&]+)', caseSensitive: false).firstMatch(trimmed);
      if (pMatch != null) result['password'] = pMatch.group(1)!.trim();

      final sMatch = RegExp(r'(?:ssid|net|name)=([^;,&]+)', caseSensitive: false).firstMatch(trimmed);
      if (sMatch != null) result['ssid'] = sMatch.group(1)!.trim();

      if (result.isNotEmpty) return result;
    }

    // 4. Clave directa
    result['password'] = trimmed;
    return result;
  }

  void _openQrScanner() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _buildQrScannerModal(ctx),
    );
  }

  Widget _buildQrScannerModal(BuildContext sheetCtx) {
    final MobileScannerController controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
    bool hasDetected = false;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.qr_code_scanner, color: Color(0xFF60A5FA), size: 24),
                    SizedBox(width: 8),
                    Text(
                      'Escanear QR de la Etiqueta',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () {
                    controller.dispose();
                    Navigator.of(sheetCtx).pop();
                  },
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Apunta la cámara al código QR impreso debajo del equipo Motorola para cargar la clave de forma automática.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  MobileScanner(
                    controller: controller,
                    onDetect: (capture) {
                      if (hasDetected) return;
                      final List<Barcode> barcodes = capture.barcodes;
                      for (final barcode in barcodes) {
                        final raw = barcode.rawValue;
                        if (raw != null && raw.trim().isNotEmpty) {
                          hasDetected = true;
                          final parsed = _parseRouterQr(raw);
                          final pass = parsed['password'] ?? '';
                          final ssid = parsed['ssid'] ?? '';

                          setState(() {
                            if (pass.isNotEmpty) {
                              _addSatPassController.text = pass;
                            }
                            if (ssid.isNotEmpty && _addSatNameController.text == 'Equipo Sala') {
                              _addSatNameController.text = 'Satélite $ssid';
                            }
                          });

                          controller.dispose();
                          Navigator.of(sheetCtx).pop();
                          _showSnack(
                            pass.isNotEmpty
                                ? '✔ QR detectado con éxito: Contraseña cargada'
                                : '✔ Código QR escaneado',
                          );
                          break;
                        }
                      }
                    },
                  ),
                  Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFF3B82F6), width: 3),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton.filledTonal(
                  onPressed: () => controller.toggleTorch(),
                  icon: const Icon(Icons.flash_on, color: Colors.white),
                  tooltip: 'Linterna',
                ),
                IconButton.filledTonal(
                  onPressed: () => controller.switchCamera(),
                  icon: const Icon(Icons.flip_camera_ios, color: Colors.white),
                  tooltip: 'Cambiar Cámara',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // TAB 3: Comprobar Calidad de un Nodo Satélite
  Future<void> _checkNodeQuality(MeshNode node) async {
    setState(() => node.isChecking = true);
    try {
      final q = await RouterService.checkSatelliteQuality(_currentIp, _currentPassword, node.ip);
      setState(() => node.quality = q);
    } catch (_) {
      setState(() {
        node.quality = SatelliteQuality(
          isOnline: false,
          latencyMs: 0,
          signalDbm: -100,
          qualityPercent: 0,
          linkType: 'Desconectado',
          statusText: 'No responde en ${node.ip}',
        );
      });
    } finally {
      setState(() => node.isChecking = false);
    }
  }

  // TAB 3: Comprobar Calidad de todos los Satélites
  Future<void> _checkAllNodes() async {
    setState(() => _isCheckingAllNodes = true);
    try {
      for (var node in _meshNodes) {
        await _checkNodeQuality(node);
      }
      _showSnack('Estado de la red Mesh actualizado');
    } finally {
      setState(() => _isCheckingAllNodes = false);
    }
  }

  // TAB 3: Cambiar Potencia en Satélite
  Future<void> _setNodeTxPower(MeshNode node, int power) async {
    final pass = node.password.isNotEmpty ? node.password : _currentPassword;
    _showSnack('Ajustando potencia en ${node.name} (${node.ip})...');
    try {
      await RouterService.setSatelliteTxPower(node.ip, pass, power);
      setState(() => node.txPower = power);
      _showSnack('Potencia ajustada a $power dBm en ${node.name}');
    } catch (e) {
      _showSnack('Error al ajustar potencia en ${node.name}: $e', isError: true);
    }
  }

  // TAB 3: Cambiar Nombre de Satélite (Hostname)
  Future<void> _renameNode(MeshNode node) async {
    final ctrl = TextEditingController(text: node.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text('Renombrar ${node.name}', style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: ctrl,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Nuevo nombre del satélite',
            hintText: 'Ej: Equipo Sala, Estudio, etc.',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB)),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty) {
      final pass = node.password.isNotEmpty ? node.password : _currentPassword;
      try {
        await RouterService.setHostname(node.ip, pass, newName);
        setState(() => node.name = newName);
        _showSnack('Nombre cambiado a "$newName" en ${node.ip}');
      } catch (e) {
        _showSnack('Error al cambiar nombre: $e', isError: true);
      }
    }
  }

  // TAB 3: Reiniciar Satélite
  Future<void> _rebootNode(MeshNode node) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text('¿Reiniciar ${node.name}?', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('El equipo en ${node.ip} se reiniciará. Tomará unos 60 segundos en reconectarse.', style: const TextStyle(color: Colors.white70, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reiniciar Ahora'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final pass = node.password.isNotEmpty ? node.password : _currentPassword;
    try {
      await RouterService.rebootRouter(node.ip, pass);
      _showSnack('Reinicio enviado a ${node.name}');
    } catch (_) {
      _showSnack('Reinicio iniciado en ${node.name}');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isConnected) {
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
            ),
          ),
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Card(
                color: const Color(0xFF1E293B),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.wifi_tethering, size: 56, color: Color(0xFF3B82F6)),
                      const SizedBox(height: 12),
                      const Text(
                        'Lan Router Management',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Gestión Local Directa Motorola MH7601 (Sin Minim Cloud)',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _ipController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'IP del Router Principal',
                          hintText: '192.168.1.1',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.dns, color: Color(0xFF3B82F6)),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _passController,
                        obscureText: true,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Contraseña de fábrica (Etiqueta)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.key, color: Color(0xFF3B82F6)),
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: _isLoading ? null : _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                              )
                            : const Text(
                                'Conectar al Router Principal',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final pages = [
      _buildCreateWifiTab(),
      _buildAddSatelliteTab(),
      _buildControlSatellitesTab(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_status?.hostname ?? 'Router Principal', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            Text('${_status?.model ?? "Motorola MH7601"} • $_currentIp', style: const TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
        backgroundColor: const Color(0xFF1E293B),
        actions: [
          IconButton(
            tooltip: 'Diagnóstico de Hardware (NVRAM/Drivers)',
            icon: const Icon(Icons.analytics_outlined, color: Colors.amberAccent),
            onPressed: _showDiagnosticDialog,
          ),
          IconButton(
            tooltip: 'Cerrar Sesión',
            icon: const Icon(Icons.logout, color: Colors.white70),
            onPressed: () => setState(() => _isConnected = false),
          ),
        ],
      ),
      body: pages[_currentIndex],
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF0F172A),
        indicatorColor: const Color(0xFF2563EB).withOpacity(0.3),
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.wifi_outlined),
            selectedIcon: Icon(Icons.wifi, color: Color(0xFF60A5FA)),
            label: 'Crea tus Redes Wi-Fi',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline),
            selectedIcon: Icon(Icons.add_circle, color: Color(0xFF60A5FA)),
            label: 'Agregar Satélite',
          ),
          NavigationDestination(
            icon: Icon(Icons.hub_outlined),
            selectedIcon: Icon(Icons.hub, color: Color(0xFF60A5FA)),
            label: 'Control Satélites',
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // PESTAÑA 1: CREA TUS REDES WI-FI & AJUSTES DEL ROUTER PRINCIPAL
  // =========================================================================
  Widget _buildCreateWifiTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Card 1: Identidad del Equipo & Minim Cloud
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.badge, color: Color(0xFF60A5FA), size: 22),
                    SizedBox(width: 8),
                    Text('Nombre del Equipo', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                ),
                const SizedBox(height: 6),
                const Text('Asigna un nombre para identificar este equipo (ej: Router Habitación, Principal, etc.)', style: TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _routerNameController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Nombre del Router',
                          hintText: 'Router Habitación',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _saveRouterName,
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Guardar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                // Minim Cloud Status & Switch
                Row(
                  children: [
                    const Icon(Icons.cloud_off, color: Colors.amberAccent, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Agente en la Nube Minim (Motosync)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                          Text(
                            _status?.minimStopped == true
                                ? 'Desactivado (100% Offline y seguro ante caídas)'
                                : 'Activo en segundo plano (Puede sobreescribir cambios)',
                            style: TextStyle(
                              fontSize: 11,
                              color: _status?.minimStopped == true ? const Color(0xFF34D399) : Colors.amberAccent,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _disableMinimCloud,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _status?.minimStopped == true ? const Color(0xFF0F766E) : Colors.amber.shade800,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      child: Text(
                        _status?.minimStopped == true ? '✓ Apagado' : 'Apagar Minim',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 14),

        // Card 2: Configuración Wi-Fi
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(Icons.wifi, color: Color(0xFF60A5FA), size: 22),
                    SizedBox(width: 8),
                    Text('Emisión Wi-Fi Principal', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                ),
                const SizedBox(height: 6),
                const Text('Configura el nombre de tu red, contraseña, seguridad y potencia de cobertura', style: TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 14),

                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Separar bandas (2.4 GHz y 5 GHz)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
                  subtitle: Text(
                    _separateBands ? 'Dos nombres de red independientes' : 'Un solo nombre inteligente (Mesh Smart Steering)',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  value: _separateBands,
                  onChanged: (val) => setState(() => _separateBands = val),
                ),
                const Divider(height: 20),

                // Banda 2.4 GHz o Unificada
                Text(
                  _separateBands ? 'Banda 2.4 GHz' : 'Red Wi-Fi Principal (2.4 & 5 GHz)',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF3B82F6)),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _ssid24Controller,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Nombre de red (SSID)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _key24Controller,
                  obscureText: _isPassObscure,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Contraseña Wi-Fi',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_isPassObscure ? Icons.visibility : Icons.visibility_off, color: Colors.grey),
                      onPressed: () => setState(() => _isPassObscure = !_isPassObscure),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _enc24,
                  dropdownColor: const Color(0xFF1E293B),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: const InputDecoration(labelText: 'Tipo de Cifrado (Seguridad)', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'psk2', child: Text('WPA2-PSK (Máxima compatibilidad - Recomendado)')),
                    DropdownMenuItem(value: 'sae-mixed', child: Text('WPA2 / WPA3 Mixto (Moderno)')),
                    DropdownMenuItem(value: 'sae', child: Text('WPA3-SAE (Estricto)')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _enc24 = v);
                  },
                ),

                if (_separateBands) ...[
                  const SizedBox(height: 18),
                  const Text('Banda 5 GHz (Alta Velocidad)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigoAccent)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _ssid5Controller,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(labelText: 'Nombre de red 5 GHz (SSID)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _key5Controller,
                    obscureText: _isPassObscure,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(labelText: 'Contraseña 5 GHz', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: _enc5,
                    dropdownColor: const Color(0xFF1E293B),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(labelText: 'Cifrado 5 GHz', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'psk2', child: Text('WPA2-PSK (Compatible)')),
                      DropdownMenuItem(value: 'sae-mixed', child: Text('WPA2 / WPA3 Mixto')),
                      DropdownMenuItem(value: 'sae', child: Text('WPA3-SAE')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _enc5 = v);
                    },
                  ),
                ],

                const Divider(height: 28),

                // Control de Potencia (Tx Power)
                const Text('Potencia de Señal / Cobertura (Tx Power)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orangeAccent)),
                const SizedBox(height: 4),
                const Text('Aumenta el alcance de las antenas para cubrir habitaciones lejanas', style: TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  value: _txPower,
                  dropdownColor: const Color(0xFF1E293B),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: const InputDecoration(labelText: 'Nivel de Potencia', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 23, child: Text('⚡ 23 dBm (100% - Máxima Potencia y Cobertura)')),
                    DropdownMenuItem(value: 20, child: Text('🟢 20 dBm (75% - Cobertura Alta)')),
                    DropdownMenuItem(value: 17, child: Text('🟡 17 dBm (50% - Media / Espacios pequeños)')),
                    DropdownMenuItem(value: 14, child: Text('🔵 14 dBm (25% - Baja / Ahorro energético)')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _txPower = v);
                  },
                ),

                const SizedBox(height: 14),

                // Switch Modo Compatibilidad Wi-Fi 6
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Modo Compatibilidad Dispositivos Antiguos / IoT', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
                  subtitle: const Text(
                    'Desactiva 802.11ax en 2.4 GHz para que bombillos inteligentes, TVs viejas e impresoras se conecten sin fallos',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  value: _legacyMode,
                  onChanged: (val) => setState(() => _legacyMode = val),
                ),

                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _saveWifi,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Guardar Cambios y Reiniciar Router Limpiamente', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 14),

        // Card 3: Red LAN & Personalización DHCP
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded: false,
              leading: const Icon(Icons.lan, color: Color(0xFF60A5FA)),
              title: const Text('Personalización de Red LAN & DHCP', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
              subtitle: const Text('Rango de IPs, servidores DNS, servidor DHCP y dirección IP local', style: TextStyle(fontSize: 11, color: Colors.grey)),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Switch Servidor DHCP
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Servidor DHCP Automático (ON / OFF)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                        subtitle: Text(
                          _dhcpEnabled ? 'Activado: Asigna direcciones IP a celulares y PCs' : 'APAGADO: Útil cuando este router es usado como satélite en LAN a LAN',
                          style: TextStyle(fontSize: 11, color: _dhcpEnabled ? const Color(0xFF34D399) : Colors.redAccent),
                        ),
                        value: _dhcpEnabled,
                        onChanged: (val) => setState(() => _dhcpEnabled = val),
                      ),
                      const SizedBox(height: 12),

                      if (_dhcpEnabled) ...[
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _dhcpStartController,
                                keyboardType: TextInputType.number,
                                style: const TextStyle(color: Colors.white),
                                decoration: const InputDecoration(
                                  labelText: 'IP Inicial DHCP',
                                  hintText: '100',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _dhcpLimitController,
                                keyboardType: TextInputType.number,
                                style: const TextStyle(color: Colors.white),
                                decoration: const InputDecoration(
                                  labelText: 'Límite de IPs',
                                  hintText: '150',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: _selectedDns.contains('1.1.1.1') ? '1.1.1.1,1.0.0.1' : (_selectedDns.contains('8.8.8.8') ? '8.8.8.8,8.8.4.4' : 'manual'),
                          dropdownColor: const Color(0xFF1E293B),
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: const InputDecoration(labelText: 'Servidores DNS', border: OutlineInputBorder(), isDense: true),
                          items: const [
                            DropdownMenuItem(value: '1.1.1.1,1.0.0.1', child: Text('Cloudflare Rápido (1.1.1.1, 1.0.0.1)')),
                            DropdownMenuItem(value: '8.8.8.8,8.8.4.4', child: Text('Google DNS (8.8.8.8, 8.8.4.4)')),
                            DropdownMenuItem(value: 'manual', child: Text('DNS Personalizado')),
                          ],
                          onChanged: (v) {
                            if (v != null && v != 'manual') setState(() => _selectedDns = v);
                          },
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _isLoading ? null : _saveDhcp,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0284C7),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text('Guardar Rango DHCP y DNS', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],

                      const Divider(height: 28),

                      // IP Estática LAN
                      const Text('Dirección IP Local Estática (LAN)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _lanIpController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'IP Local del Router',
                          hintText: '192.168.1.1',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _lanNetmaskController,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                labelText: 'Máscara',
                                hintText: '255.255.255.0',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _lanGatewayController,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                labelText: 'Gateway (Opcional)',
                                hintText: '192.168.1.1',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _isLoading ? null : _saveLanIp,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF334155),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('Actualizar IP Estática LAN (Reinicia Red)', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // PESTAÑA 2: AGREGAR SATÉLITES A TU RED MESH (FLUJO 100% INALÁMBRICO)
  // =========================================================================
  Widget _buildAddSatelliteTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Selector de Modo (Plug & Mesh vs Adopción Aérea)
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _adoptionMode = 0),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _adoptionMode == 0 ? const Color(0xFF2563EB) : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.cable, size: 18, color: _adoptionMode == 0 ? Colors.white : Colors.white60),
                        const SizedBox(width: 8),
                        Text(
                          'Plug & Mesh (Cable)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: _adoptionMode == 0 ? Colors.white : Colors.white60,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _adoptionMode = 1),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _adoptionMode == 1 ? const Color(0xFF2563EB) : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.wifi_tethering, size: 18, color: _adoptionMode == 1 ? Colors.white : Colors.white60),
                        const SizedBox(width: 8),
                        Text(
                          'Aéreo (Wi-Fi / WPS)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: _adoptionMode == 1 ? Colors.white : Colors.white60,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Card Datos de Malla y Asignación de IP
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(Icons.hub, color: Color(0xFF38BDF8), size: 22),
                    SizedBox(width: 8),
                    Text('Datos de tu Red Mesh', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                ),
                const SizedBox(height: 14),

                // Red Wi-Fi a Clonar
                TextField(
                  controller: _addSatMainSsidController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Red Wi-Fi que repetirá el Satélite (SSID)',
                    hintText: 'Ej: Motorolamesh',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.wifi, color: Color(0xFF3B82F6)),
                  ),
                ),

                const SizedBox(height: 12),

                // Contraseña Wi-Fi
                TextField(
                  controller: _addSatMainKeyController,
                  obscureText: _addSatMainKeyObscure,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Contraseña de tu Red Wi-Fi',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock, color: Color(0xFF3B82F6)),
                    suffixIcon: IconButton(
                      icon: Icon(_addSatMainKeyObscure ? Icons.visibility : Icons.visibility_off, color: Colors.grey),
                      onPressed: () => setState(() => _addSatMainKeyObscure = !_addSatMainKeyObscure),
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                // Asignación de IP Automática inteligente
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF0284C7), width: 1.2),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.dns, color: Color(0xFF38BDF8), size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Siguiente IP disponible calculada:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                            const SizedBox(height: 2),
                            Text(
                              _calculatedNextIp,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF38BDF8)),
                            ),
                            Text(
                              _calculatedNextIp == '192.168.1.2' ? 'Nodo Satélite 1' : (_calculatedNextIp == '192.168.1.3' ? 'Nodo Satélite 2' : 'Nodo Satélite 3'),
                              style: const TextStyle(fontSize: 10, color: Colors.white60),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: _isCalculatingIp
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.refresh, color: Color(0xFF60A5FA)),
                        tooltip: 'Recalcular IP libre',
                        onPressed: _isCalculatingIp ? null : _calculateNextIp,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // Nombre personalizado del Satélite
                TextField(
                  controller: _addSatNameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Nombre para identificar este Satélite',
                    hintText: 'Ej: Satélite 1, Equipo Sala, etc.',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.edit, color: Color(0xFF3B82F6)),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // SECCIÓN MODO 0: PLUG & MESH (POR CABLE)
        if (_adoptionMode == 0) ...[
          Card(
            color: const Color(0xFF0F2B48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFF0284C7), width: 1.5),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.cable, color: Color(0xFF38BDF8), size: 24),
                      SizedBox(width: 8),
                      Text('1. Conectar Cable Temporal (30 seg)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '• Conecta un cable de red desde cualquier puerto LAN del router principal hacia el puerto WAN (azul) del satélite nuevo.\n'
                    '• Enciende el satélite y espera 30 segundos a que arranque.',
                    style: TextStyle(fontSize: 12, color: Colors.white70, height: 1.4),
                  ),
                  const SizedBox(height: 14),

                  ElevatedButton.icon(
                    onPressed: _isScanningCable ? null : _scanCableSatellites,
                    icon: _isScanningCable
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.search),
                    label: Text(_isScanningCable ? 'Buscando en puertos LAN...' : 'Detectar Satélite Conectado por Cable'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),

                  if (_cableCandidates.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Text('Equipos detectados en la red por cable:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70)),
                    const SizedBox(height: 6),
                    ..._cableCandidates.map((c) {
                      final isSelected = _selectedCableCandidate?.mac == c.mac;
                      return InkWell(
                        onTap: () => setState(() => _selectedCableCandidate = c),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFF1E3A8A) : const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: isSelected ? const Color(0xFF60A5FA) : (c.isMotorola ? const Color(0xFF10B981) : Colors.white12), width: 1.5),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.router, color: c.isMotorola ? const Color(0xFF34D399) : Colors.grey, size: 22),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(c.hostname, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13)),
                                        if (c.isMotorola) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                            decoration: BoxDecoration(color: const Color(0xFF065F46), borderRadius: BorderRadius.circular(4)),
                                            child: const Text('MOTOROLA', style: TextStyle(fontSize: 9, color: Color(0xFF34D399), fontWeight: FontWeight.bold)),
                                          ),
                                        ],
                                      ],
                                    ),
                                    Text('IP Temporal: ${c.ip} • MAC: ${c.mac}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                  ],
                                ),
                              ),
                              if (isSelected) const Icon(Icons.check_circle, color: Color(0xFF60A5FA), size: 20),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Card Autorización y Creación de Malla
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('2. Autorizar y Crear Malla', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 12),

                  OutlinedButton.icon(
                    onPressed: _openQrScanner,
                    icon: const Icon(Icons.qr_code_scanner, color: Color(0xFF60A5FA), size: 22),
                    label: const Text('Escanear QR de la Etiqueta del Satélite', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF60A5FA), fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: Color(0xFF3B82F6), width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      backgroundColor: const Color(0xFF1E3A8A).withOpacity(0.2),
                    ),
                  ),

                  const SizedBox(height: 12),

                  TextField(
                    controller: _addSatPassController,
                    obscureText: _addSatPassObscure,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Contraseña de la etiqueta del Satélite',
                      helperText: 'Clave impresa abajo o escaneada por QR',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.key, color: Color(0xFF3B82F6)),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.qr_code_scanner, color: Color(0xFF60A5FA)),
                            tooltip: 'Escanear QR',
                            onPressed: _openQrScanner,
                          ),
                          IconButton(
                            icon: Icon(_addSatPassObscure ? Icons.visibility : Icons.visibility_off, color: Colors.grey),
                            onPressed: () => setState(() => _addSatPassObscure = !_addSatPassObscure),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  ElevatedButton.icon(
                    onPressed: _isProvisioningSat ? null : _runProvisionPlugAndMesh,
                    icon: _isProvisioningSat
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                        : const Icon(Icons.hub),
                    label: Text(
                      _isProvisioningSat ? 'Sincronizando Malla...' : 'Sincronizar y Crear Malla Mesh',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '💡 Al finalizar, podrás desconectar el cable de red y ubicar el satélite donde quieras; operará 100% de forma inalámbrica.',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],

        // SECCIÓN MODO 1: ADOPCIÓN AÉREA (WI-FI / WPS)
        if (_adoptionMode == 1) ...[
          // Opción WPS por Hardware
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.wifi_protected_setup, color: Color(0xFF38BDF8), size: 24),
                      SizedBox(width: 8),
                      Text('Opción 1: Emparejamiento por Botón WPS', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '1. Pulsa el botón abajo para abrir la ventana de enlace WPS en tu router principal (el LED parpadeará).\n'
                    '2. Presiona el botón WPS en el satélite que quieres agregar.\n'
                    'Ambos equipos se sincronizarán por radio automáticamente.',
                    style: TextStyle(fontSize: 12, color: Colors.white70, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    onPressed: _isTriggeringWps ? null : _triggerWpsPairing,
                    icon: _isTriggeringWps
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.wifi_protected_setup),
                    label: Text(_isTriggeringWps ? 'Abriendo WPS...' : 'Abrir Ventana WPS en Router Principal (2 min)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Opción Escaneo de Balizas en el Aire
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.radar, color: Color(0xFF60A5FA), size: 22),
                      SizedBox(width: 8),
                      Text('Opción 2: Buscar Señal del Satélite en el Aire', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'El router principal buscará con sus propias antenas las señales de fábrica emitidas por satélites Motorola cercanos.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _isScanningAir ? null : _scanAirSatellitesFromMain,
                    icon: _isScanningAir
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.radar),
                    label: Text(_isScanningAir ? 'Escaneando el aire...' : 'Escanear Satélites Cercanos'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),

                  if (_detectedAirSatellites.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    ..._detectedAirSatellites.map((net) {
                      final isSelected = _selectedAirSatellite?.mac == net.mac;
                      return InkWell(
                        onTap: () => setState(() => _selectedAirSatellite = net),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFF1E3A8A) : const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: isSelected ? const Color(0xFF60A5FA) : (net.isMotorola ? const Color(0xFF10B981) : Colors.white12), width: 1.5),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.wifi, color: net.signal >= -65 ? Colors.greenAccent : Colors.orangeAccent, size: 22),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(net.ssid, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13)),
                                    Text('Canal ${net.channel} • Señal: ${net.signal} dBm • MAC: ${net.mac}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                  ],
                                ),
                              ),
                              if (isSelected) const Icon(Icons.check_circle, color: Color(0xFF60A5FA), size: 20),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  // =========================================================================
  // PESTAÑA 3: CONTROL DE SATÉLITES CONECTADOS Y MONITOREO MESH
  // =========================================================================
  Widget _buildControlSatellitesTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Header de acción
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Satélites Mesh Activos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                Text('Monitoreo en vivo y control individual de nodos', style: TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
            ElevatedButton.icon(
              onPressed: _isCheckingAllNodes ? null : _checkAllNodes,
              icon: _isCheckingAllNodes
                  ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.refresh, size: 18),
              label: const Text('Comprobar', style: TextStyle(fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Lista de Satélites
        if (_meshNodes.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text('No hay satélites registrados. Ve a la pestaña "Agregar Satélite".', style: TextStyle(color: Colors.grey)),
              ),
            ),
          )
        else
          ..._meshNodes.map((node) => _buildSatelliteCard(node)),
      ],
    );
  }

  Widget _buildSatelliteCard(MeshNode node) {
    final q = node.quality;
    final isOnline = q?.isOnline ?? false;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isOnline ? const Color(0xFF10B981).withOpacity(0.4) : Colors.white12,
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabecera del Nodo
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isOnline ? const Color(0xFF10B981).withOpacity(0.2) : Colors.white10,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.router,
                    color: isOnline ? const Color(0xFF34D399) : Colors.grey,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(node.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                          IconButton(
                            icon: const Icon(Icons.edit, size: 16, color: Color(0xFF60A5FA)),
                            tooltip: 'Cambiar Nombre',
                            onPressed: () => _renameNode(node),
                          ),
                        ],
                      ),
                      Text('IP: ${node.ip}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isOnline ? const Color(0xFF10B981).withOpacity(0.2) : Colors.redAccent.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    isOnline ? 'En Línea' : 'Desconectado',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isOnline ? const Color(0xFF34D399) : Colors.redAccent,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Métricas de Enlace
            if (q != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Tipo de enlace:', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        Text(q.linkType, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Latencia (Ping):', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        Text('${q.latencyMs} ms', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF60A5FA))),
                      ],
                    ),
                    if (q.linkType.contains('Wi-Fi')) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Señal Wi-Fi Mesh:', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          Text('${q.signalDbm} dBm (${q.qualityPercent}%)', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF34D399))),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: (q.qualityPercent / 100).clamp(0.0, 1.0),
                        backgroundColor: Colors.white12,
                        color: q.qualityPercent > 70 ? const Color(0xFF10B981) : Colors.orangeAccent,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],

            // Controles Individuales: Potencia de Transmisión & Reinicio
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: node.txPower,
                    dropdownColor: const Color(0xFF1E293B),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: const InputDecoration(
                      labelText: 'Potencia Satélite',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 23, child: Text('⚡ 23 dBm (100% Máx)')),
                      DropdownMenuItem(value: 20, child: Text('🟢 20 dBm (75%)')),
                      DropdownMenuItem(value: 17, child: Text('🟡 17 dBm (50%)')),
                      DropdownMenuItem(value: 14, child: Text('🔵 14 dBm (25%)')),
                    ],
                    onChanged: (p) {
                      if (p != null) _setNodeTxPower(node, p);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filled(
                  tooltip: 'Comprobar Enlace',
                  style: IconButton.styleFrom(backgroundColor: const Color(0xFF2563EB)),
                  onPressed: node.isChecking ? null : () => _checkNodeQuality(node),
                  icon: node.isChecking
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.network_check, size: 20),
                ),
                const SizedBox(width: 6),
                IconButton.filled(
                  tooltip: 'Reiniciar Satélite',
                  style: IconButton.styleFrom(backgroundColor: Colors.redAccent.withOpacity(0.8)),
                  onPressed: () => _rebootNode(node),
                  icon: const Icon(Icons.restart_alt, size: 20),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
