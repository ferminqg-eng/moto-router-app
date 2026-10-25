import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
          onPrimary: Colors.white,
          secondary: Color(0xFF6366F1),
          surface: Color(0xFF1E293B),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            foregroundColor: Colors.white,
            disabledForegroundColor: Colors.white70,
          ),
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
  String mac;
  String password;
  String backhaulBand;
  int txPower;
  SatelliteQuality? quality;
  bool isChecking;

  MeshNode({
    required this.name,
    required this.ip,
    this.mac = '',
    this.password = '',
    this.backhaulBand = '2.4 GHz',
    this.txPower = 23,
    this.quality,
    this.isChecking = false,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'ip': ip,
    'mac': mac,
    'password': password,
    'backhaulBand': backhaulBand,
    'txPower': txPower,
  };

  factory MeshNode.fromJson(Map<String, dynamic> json) => MeshNode(
    name: json['name'] ?? 'Satélite',
    ip: json['ip'] ?? '192.168.1.2',
    mac: json['mac'] ?? '',
    password: json['password'] ?? '',
    backhaulBand: json['backhaulBand'] ?? '2.4 GHz',
    txPower: json['txPower'] ?? 23,
  );
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  bool _isConnected = false;
  bool _loginPassObscure = true;
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

  int _txPower = 23;
  int _channel24 = 0;
  int _channel5 = 0; // 23 = Max (100%), 20 = Alta (75%), 17 = Media (50%), 14 = Baja (25%)
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
  String _selectedBackhaulBand = '2.4 GHz';
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
  bool _isDiscoveringSatellites = false;

  // DHCP Leases State
  List<DhcpLeaseEntry> _dhcpLeases = [];
  bool _isLoadingLeases = false;

  @override
  void initState() {
    super.initState();
    _loadSavedMeshNodes();
  }

  Future<void> _loadSavedMeshNodes() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final str = sp.getString('saved_mesh_nodes');
      if (str != null && str.isNotEmpty) {
        final List decoded = jsonDecode(str);
        setState(() {
          _meshNodes.clear();
          for (final item in decoded) {
            _meshNodes.add(MeshNode.fromJson(item));
          }
        });
        _calculateNextIp();
      }
    } catch (_) {}
  }

  Future<void> _persistMeshNodes() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final list = _meshNodes.map((n) => n.toJson()).toList();
      await sp.setString('saved_mesh_nodes', jsonEncode(list));
    } catch (_) {}
  }

  Future<void> _loadDhcpLeases() async {
    setState(() => _isLoadingLeases = true);
    try {
      final leases = await RouterService.getDhcpLeases(_currentIp, _currentPassword);
      setState(() {
        _dhcpLeases = leases;
      });
      _showSnack('✔ ${leases.length} concesión(es) DHCP detectadas');
    } catch (e) {
      _showSnack('Error al consultar concesiones DHCP: $e', isError: true);
    } finally {
      setState(() => _isLoadingLeases = false);
    }
  }

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

      await _loadWifiConfig();
      _loadDhcpConfig();
      // Habilitar automáticamente DWDS Nativo Broadcom + STP rápido en el Router Principal al iniciar sesión
      RouterService.prepareMainRouterForWds(ip, pass).catchError((_) {});
      // Auto-descubrir satélites activos (inalámbricos DWDS o cableados) en segundo plano
      _autoDiscoverSatellites(silent: true);
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
          final cleanS = wifi.ssid24.replaceAll('Current SSID:', '').replaceAll('"', '').trim();
          _ssid24Controller.text = cleanS;
          _addSatMainSsidController.text = cleanS;
        }
        if (wifi.key24.isNotEmpty) {
          _key24Controller.text = wifi.key24.trim();
          _addSatMainKeyController.text = wifi.key24.trim();
        }
        _enc24 = wifi.enc24.isNotEmpty ? wifi.enc24 : 'psk2';

        if (wifi.ssid5.isNotEmpty) {
          final clean5 = wifi.ssid5.replaceAll('Current SSID:', '').replaceAll('"', '').trim();
          _ssid5Controller.text = clean5;
        }
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
        channel24: _mainChannel24,
        channel5: _mainChannel5,
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

  // TAB 2: Aprovisionamiento Guiado Directo Wi-Fi (100% Real y Verificado)
  Future<void> _runProvisionDirectSatellite() async {
    final satPass = _addSatPassController.text.trim();
    if (satPass.isEmpty) {
      return _showSnack('Ingresa o escanea la contraseña de etiqueta del satélite', isError: true);
    }

    final satName = _addSatNameController.text.trim().isNotEmpty
        ? _addSatNameController.text.trim()
        : 'Satélite 1';
    String mainSsid = _addSatMainSsidController.text.trim();
    if (mainSsid.isEmpty || mainSsid == 'Motorolamesh') {
      mainSsid = _ssid24Controller.text.trim();
    }
    mainSsid = mainSsid.replaceAll('Current SSID:', '').replaceAll('"', '').trim();
    if (mainSsid.isEmpty) mainSsid = 'MotorolaQP';

    String mainKey = _addSatMainKeyController.text.trim();
    if (mainKey.isEmpty) {
      mainKey = _key24Controller.text.trim();
    }
    final targetIp = _calculatedNextIp;

    double progressVal = 0.15;
    String progressStep = 'Localizando satélite Motorola (10.10.11.1 / 192.168.1.1)...';

    setState(() => _isProvisioningSat = true);

    StateSetter? setModalState;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateModal) {
          setModalState = setStateModal;
          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF10B981)),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text('Configurando Satélite Mesh...', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Mantén tu teléfono conectado a la red Wi-Fi de fábrica de este satélite.',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: progressVal,
                  backgroundColor: Colors.white12,
                  color: const Color(0xFF10B981),
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 12),
                Text(
                  progressStep,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF34D399), fontWeight: FontWeight.w500),
                ),
              ],
            ),
          );
        },
      ),
    );

    try {
      final selectedBssid = _selectedBackhaulBand.contains('5')
          ? (_mainBssid5.isNotEmpty ? _mainBssid5 : _mainBssid24)
          : (_mainBssid24.isNotEmpty ? _mainBssid24 : _mainBssid5);

      String targetSatGateway = '192.168.1.1';
      try {
        final detected = await RouterService.detectSatelliteGateway();
        if (detected.isNotEmpty) targetSatGateway = detected;
      } catch (_) {}

      // Si el satélite está en 10.10.11.1 (cable WAN conectado al principal), podemos asegurar DWDS en 192.168.1.1 también aquí
      if (targetSatGateway != _currentIp) {
        try {
          await RouterService.prepareMainRouterForWds(_currentIp, _currentPassword);
        } catch (_) {}
      }

      final satMac = await RouterService.provisionSatelliteDirect(
        satIp: targetSatGateway,
        satPassword: satPass,
        targetIp: targetIp,
        mainGateway: _currentIp,
        mainSsid: mainSsid,
        mainKey: mainKey,
        satName: satName,
        channel5: _mainChannel5,
        channel24: _mainChannel24,
        mainBssid: selectedBssid,
        backhaulBand: _selectedBackhaulBand,
        onProgress: (step, percent) {
          if (mounted && setModalState != null) {
            setModalState!(() {
              progressStep = step;
              progressVal = percent;
            });
          }
        },
      );

      final effectiveNodePass = mainKey.isNotEmpty ? mainKey : satPass;
      final existingIdx = _meshNodes.indexWhere((n) => n.ip == targetIp || (satMac.isNotEmpty && n.mac.toUpperCase() == satMac.toUpperCase()));
      if (existingIdx != -1) {
        _meshNodes[existingIdx].ip = targetIp;
        _meshNodes[existingIdx].name = satName;
        _meshNodes[existingIdx].mac = satMac;
        _meshNodes[existingIdx].password = effectiveNodePass;
        _meshNodes[existingIdx].backhaulBand = _selectedBackhaulBand;
      } else {
        _meshNodes.add(MeshNode(name: satName, ip: targetIp, mac: satMac, password: effectiveNodePass, backhaulBand: _selectedBackhaulBand));
      }
      await _persistMeshNodes();
      await _calculateNextIp();

      if (mounted) {
        Navigator.pop(context); // Cerrar diálogo de progreso

        await _showSatelliteAdoptionCountdownDialog(
          satName: satName,
          targetIp: targetIp,
          mainSsid: mainSsid,
        );

        if (mounted) {
          setState(() => _currentIndex = 2); // Ir a Control Satélites tras los 40s
          await _autoDiscoverSatellites();
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Cerrar diálogo de progreso
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.error_outline, color: Colors.redAccent, size: 26),
                SizedBox(width: 10),
                Expanded(
                  child: Text('Fallo en la Adopción', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            content: Text(
              '$e\n\n'
              'Verificaciones:\n'
              '1. Conecta un cable de red desde LAN del Router Principal al puerto WAN (azul) del Satélite durante la adopción.\n'
              '2. Conéctate al Wi-Fi de fábrica del satélite o verifica su IP detectada.\n'
              '3. Confirma que la contraseña de etiqueta coincida exactamente.',
              style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Aceptar', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      }
    } finally {
      setState(() => _isProvisioningSat = false);
    }
  }

  // Barra de progreso y cuenta regresiva de 40 segundos tras adoptar un Satélite
  Future<void> _showSatelliteAdoptionCountdownDialog({
    required String satName,
    required String targetIp,
    required String mainSsid,
  }) async {
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
                if (Navigator.of(ctx).canPop()) {
                  Navigator.of(ctx).pop();
                }
              }
            });

            final progress = (40 - secondsLeft) / 40.0;
            final percent = (progress * 100).round();

            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.check_circle, color: Color(0xFF10B981), size: 26),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '¡Satélite Adoptado! Iniciando...',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 6),
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 84,
                          height: 84,
                          child: CircularProgressIndicator(
                            value: progress,
                            strokeWidth: 6,
                            backgroundColor: Colors.white12,
                            color: const Color(0xFF10B981),
                          ),
                        ),
                        Text(
                          '${secondsLeft}s',
                          style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                        backgroundColor: Colors.white12,
                        color: const Color(0xFF38BDF8),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Sincronizando malla inalámbrica ($percent%) — Espera ${secondsLeft}s',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF38BDF8), fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Text(
                        '• Satélite: $satName ($targetIp)\n'
                        '• Red Wi-Fi Clonada: $mainSsid\n\n'
                        '🔌 PASOS MIENTRAS TERMINA LA ESPERA:\n'
                        '1. Desconecta AHORA el cable de red entre el Router Principal y el Satélite.\n'
                        '2. Verifica que tu teléfono esté conectado a tu Wi-Fi principal ($mainSsid).\n'
                        '3. Al llegar a 0s se mostrará automáticamente el estatus de conexión del satélite.',
                        style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                if (secondsLeft == 0)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Ver Estatus del Satélite', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
              ],
            );
          },
        );
      },
    );
    timer?.cancel();
  }

  // TAB 3: Eliminar Satélite (Quitar de la app o Hard Reset de fábrica)
  Future<void> _removeSatellite(MeshNode node) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.delete_forever, color: Colors.redAccent, size: 26),
            const SizedBox(width: 10),
            Expanded(child: Text('Eliminar ${node.name}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('¿Qué acción deseas realizar con este satélite (${node.ip})?', style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• Solo Quitar de la Malla:', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF60A5FA), fontSize: 12)),
                  Text('Elimina el nodo de la app y libera la IP ${node.ip} para futuros equipos.', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                  const SizedBox(height: 10),
                  const Text('• Restablecer a Fábrica y Quitar:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent, fontSize: 12)),
                  const Text('Restaura el satélite a su configuración original (volverá a emitir su red Motorola-XXXX en 192.168.1.1) y lo elimina de la app.', style: TextStyle(color: Colors.grey, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white60)),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFF3B82F6)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() {
                _meshNodes.removeWhere((n) => n.ip == node.ip);
              });
              await _persistMeshNodes();
              await _calculateNextIp();
              _showSnack('Satélite ${node.name} (${node.ip}) removido de la lista');
            },
            child: const Text('Solo Quitar', style: TextStyle(color: Color(0xFF60A5FA))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.pop(ctx);
              _showSnack('Restableciendo ${node.name} a valores de fábrica...');
              try {
                await RouterService.factoryResetSatellite(
                  node.ip,
                  node.password.isNotEmpty ? node.password : _currentPassword,
                  fallbackPasswords: _nodeFallbackPasswords,
                );
              } catch (_) {}
              setState(() {
                _meshNodes.removeWhere((n) => n.ip == node.ip);
              });
              await _persistMeshNodes();
              await _calculateNextIp();
              _showSnack('✔ Satélite restablecido a fábrica y eliminado');
            },
            child: const Text('Restablecer y Quitar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // Modal para ver Concesiones (Leases) DHCP Activas
  Future<void> _openDhcpLeasesSheet() async {
    await _loadDhcpLeases();
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          return DraggableScrollableSheet(
            initialChildSize: 0.75,
            minChildSize: 0.45,
            maxChildSize: 0.95,
            expand: false,
            builder: (_, scrollController) => Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E293B),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.devices, color: Color(0xFF38BDF8), size: 24),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Concesiones DHCP (Leases)',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            Text(
                              'Dispositivos con IP asignada por el Router Principal',
                              style: TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Actualizar Leases',
                        icon: _isLoadingLeases
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.refresh, color: Color(0xFF60A5FA)),
                        onPressed: _isLoadingLeases
                            ? null
                            : () async {
                                setSheetState(() => _isLoadingLeases = true);
                                await _loadDhcpLeases();
                                setSheetState(() => _isLoadingLeases = false);
                              },
                      ),
                    ],
                  ),
                ),

                // Lista de Dispositivos y Leases
                Expanded(
                  child: _isLoadingLeases
                      ? const Center(child: CircularProgressIndicator(color: Color(0xFF2563EB)))
                      : _dhcpLeases.isEmpty
                          ? const Center(
                              child: Text(
                                'No se encontraron concesiones DHCP activas.\nPresiona el botón de actualizar.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey),
                              ),
                            )
                          : ListView.separated(
                              controller: scrollController,
                              padding: const EdgeInsets.all(16),
                              itemCount: _dhcpLeases.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (_, idx) {
                                final l = _dhcpLeases[idx];
                                return Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1E293B),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.white12),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF2563EB).withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: const Icon(Icons.devices, color: Color(0xFF60A5FA), size: 20),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              l.hostname,
                                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'IP: ${l.ip} • MAC: ${l.mac}',
                                              style: const TextStyle(fontSize: 11, color: Colors.grey),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              '⏱ ${l.expirationFormatted}',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: l.isStatic ? const Color(0xFF38BDF8) : const Color(0xFF34D399),
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF10B981).withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Text(
                                          'ACTIVO',
                                          style: TextStyle(color: Color(0xFF34D399), fontSize: 9, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                ),
              ],
            ),
          );
        },
      ),
    );
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

  void _openQrScanner({bool forLogin = false}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _buildQrScannerModal(ctx, forLogin: forLogin),
    );
  }

  Widget _buildQrScannerModal(BuildContext sheetCtx, {bool forLogin = false}) {
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
                            if (forLogin) {
                              if (pass.isNotEmpty) _passController.text = pass;
                            } else {
                              if (pass.isNotEmpty) _addSatPassController.text = pass;
                              if (ssid.isNotEmpty && _addSatNameController.text == 'Equipo Sala') {
                                _addSatNameController.text = 'Satélite $ssid';
                              }
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

  List<String> get _nodeFallbackPasswords => [
        _key24Controller.text.trim(),
        _currentPassword,
        _addSatMainKeyController.text.trim(),
        _addSatPassController.text.trim(),
        ..._meshNodes.map((n) => n.password),
      ];

  // TAB 3: Auto-detección dinámica de Satélites en la Red (DWDS Inalámbrico + Cable + ARP)
  Future<void> _autoDiscoverSatellites({bool silent = false}) async {
    setState(() => _isDiscoveringSatellites = true);
    if (!silent) {
      _showSnack('Escaneando la malla Mesh (DWDS y LAN) en busca de satélites activos...');
    }
    try {
      final discovered = await RouterService.discoverActiveMeshSatellites(
        _currentIp,
        _currentPassword,
        candidatePasswords: _nodeFallbackPasswords,
      );

      bool changed = false;
      for (final d in discovered) {
        final existingIdx = _meshNodes.indexWhere(
          (n) => (n.mac.isNotEmpty && d.mac.isNotEmpty && n.mac.toUpperCase() == d.mac.toUpperCase()) || n.ip == d.ip,
        );
        if (existingIdx != -1) {
          final existing = _meshNodes[existingIdx];
          if (existing.ip != d.ip) {
            existing.ip = d.ip;
            changed = true;
          }
          if (existing.mac.isEmpty && d.mac.isNotEmpty) {
            existing.mac = d.mac;
            changed = true;
          }
          if (d.hostname.isNotEmpty && (existing.name.startsWith('Satélite (') || existing.name == 'Satélite')) {
            existing.name = d.hostname;
            changed = true;
          }
          if (existing.backhaulBand != d.backhaulBand) {
            existing.backhaulBand = d.backhaulBand;
            changed = true;
          }
        } else {
          final defaultPass = _key24Controller.text.trim().isNotEmpty ? _key24Controller.text.trim() : _currentPassword;
          setState(() {
            _meshNodes.add(MeshNode(
              name: d.hostname,
              ip: d.ip,
              mac: d.mac,
              password: defaultPass,
              backhaulBand: d.backhaulBand,
            ));
          });
          changed = true;
        }
      }

      if (changed) {
        await _persistMeshNodes();
        await _calculateNextIp();
      }

      // Probar conectividad y calidad (incluyendo RSSI DWDS real) de todos los nodos guardados
      for (var n in _meshNodes) {
        await _checkNodeQuality(n);
      }
      if (!silent) {
        _showSnack('✔ Escaneo completado (${_meshNodes.length} satélite(s) en malla).');
      }
    } catch (e) {
      if (!silent) {
        _showSnack('Error al verificar satélites: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isDiscoveringSatellites = false);
      }
    }
  }

  // TAB 3: Cambiar Banda de Enlace Backhaul (2.4 GHz vs 5 GHz)
  Future<void> _switchNodeBackhaulBand(MeshNode node) async {
    final currentIs24 = !node.backhaulBand.contains('5');
    final targetBand = currentIs24 ? '5 GHz' : '2.4 GHz';
    final explanation = currentIs24
        ? 'Cambiar a 5 GHz brindará MAYOR VELOCIDAD, pero tiene MENOR PENETRACIÓN a través de paredes de concreto.\n\nIdeal si el satélite está en línea de vista o a corta distancia.'
        : 'Cambiar a 2.4 GHz brindará MÁXIMO ALCANCE Y ATRAVIESA PAREDES de concreto con alta estabilidad.\n\nIdeal para casas y habitaciones separadas por muros gruesos.';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text('Cambiar Enlace a $targetBand', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        content: Text(
          '$explanation\n\n¿Deseas aplicar el cambio en ${node.name} (${node.ip}) ahora?',
          style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: currentIs24 ? const Color(0xFF6366F1) : const Color(0xFF10B981),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Cambiar a $targetBand', style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final pass = node.password.isNotEmpty ? node.password : _currentPassword;
      final mainSsid = _ssid24Controller.text.trim().isNotEmpty ? _ssid24Controller.text.trim() : 'Motorolamesh';
      final mainKey = _key24Controller.text.trim();

      _showSnack('Reconfigurando enlace a $targetBand en ${node.name}...');
      try {
        await RouterService.switchSatelliteBackhaulBand(
          satIp: node.ip,
          satPassword: pass,
          mainGateway: _currentIp,
          mainSsid: mainSsid,
          mainKey: mainKey,
          targetBand: targetBand,
          fallbackPasswords: _nodeFallbackPasswords,
        );
        setState(() => node.backhaulBand = targetBand);
        await _persistMeshNodes();
        _showSnack('✔ Enlace cambiado a $targetBand. El satélite se está reiniciando...');
      } catch (e) {
        _showSnack('Error al cambiar enlace: $e', isError: true);
      }
    }
  }

    // TAB 3: Editar IP manualmente
  Future<void> _editNodeIp(MeshNode node) async {
    final ctrl = TextEditingController(text: node.ip);
    final newIp = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text('Cambiar IP de ${node.name}', style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ingresa la dirección IP real asignada al satélite (ej: 192.168.1.91):', style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Dirección IP',
                hintText: '192.168.1.91',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.router, color: Color(0xFF3B82F6)),
              ),
            ),
          ],
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

    if (newIp != null && newIp.isNotEmpty && newIp != node.ip) {
      setState(() => node.ip = newIp);
      await _persistMeshNodes();
      await _checkNodeQuality(node);
      _showSnack('IP actualizada a $newIp en ${node.name}');
    }
  }

  // TAB 3: Fijar IP a 192.168.1.2 en Router Principal y Satélite
  Future<void> _fixNodeIpToTarget(MeshNode node, String targetIp) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Fijar IP Estática en Satélite', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Text(
          '¿Deseas fijar la IP ${node.ip} a $targetIp permanentemente?\n\n'
          'La app creará una reserva fija en el Router Principal y reconfigurará el satélite.',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Fijar IP'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final pass = node.password.isNotEmpty ? node.password : _currentPassword;
      _showSnack('Configurando reserva y asignando $targetIp al satélite...');
      try {
        await RouterService.fixSatelliteIp(
          currentSatIp: node.ip,
          satPassword: pass,
          mainIp: _currentIp,
          mainPassword: _currentPassword,
          targetIp: targetIp,
          satName: node.name,
          satMac: node.mac,
          extraPasswords: _nodeFallbackPasswords,
        );
        setState(() => node.ip = targetIp);
        await _persistMeshNodes();
        _showSnack('✔ Satélite configurado en $targetIp. Reiniciando equipo...');
      } catch (e) {
        _showSnack('Error al fijar IP: $e', isError: true);
      }
    }
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
      await RouterService.setSatelliteTxPower(node.ip, pass, power, fallbackPasswords: _nodeFallbackPasswords);
      setState(() => node.txPower = power);
      await _persistMeshNodes();
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
        await RouterService.setHostname(node.ip, pass, newName, fallbackPasswords: _nodeFallbackPasswords);
        setState(() => node.name = newName);
        await _persistMeshNodes();
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
    _showSnack('Enviando reinicio a ${node.name} (${node.ip})...');
    try {
      await RouterService.rebootRouter(
        node.ip,
        pass,
        fallbackPassword: _currentPassword,
        extraPasswords: _nodeFallbackPasswords,
      );
      _showSnack('✔ Reinicio ejecutado en ${node.name}. Reconectando en ~60s...');
    } catch (e) {
      _showSnack('Error al reiniciar ${node.name}: $e', isError: true);
    }
  }

  void _showExitAppDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.power_settings_new, color: Colors.redAccent, size: 24),
            SizedBox(width: 8),
            Text('¿Qué deseas hacer?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: const Text(
          'Puedes cerrar la sesión actual para volver a la pantalla de login o salir y cerrar la aplicación completamente.',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFF38BDF8))),
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _isConnected = false);
            },
            child: const Text('Cerrar Sesión', style: TextStyle(color: Color(0xFF38BDF8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.pop(ctx);
              SystemNavigator.pop();
            },
            child: const Text('Salir de la App', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
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
                        obscureText: _loginPassObscure,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Contraseña de fábrica (Etiqueta)',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.key, color: Color(0xFF3B82F6)),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.qr_code_scanner, color: Color(0xFF60A5FA)),
                                tooltip: 'Escanear QR de la Etiqueta',
                                onPressed: () => _openQrScanner(forLogin: true),
                              ),
                              IconButton(
                                icon: Icon(_loginPassObscure ? Icons.visibility : Icons.visibility_off, color: Colors.grey),
                                onPressed: () => setState(() => _loginPassObscure = !_loginPassObscure),
                              ),
                            ],
                          ),
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
            tooltip: 'Concesiones DHCP (Leases)',
            icon: const Icon(Icons.devices, color: Color(0xFF38BDF8)),
            onPressed: _openDhcpLeasesSheet,
          ),
          IconButton(
            tooltip: 'Diagnóstico de Hardware (NVRAM/Drivers)',
            icon: const Icon(Icons.analytics_outlined, color: Colors.amberAccent),
            onPressed: _showDiagnosticDialog,
          ),
          IconButton(
            tooltip: 'Salir',
            icon: const Icon(Icons.power_settings_new, color: Colors.white70),
            onPressed: _showExitAppDialog,
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
                      icon: const Icon(Icons.check, size: 18, color: Colors.white),
                      label: const Text(
                        'Guardar',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        disabledForegroundColor: Colors.white70,
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
                  isExpanded: true,
                  dropdownColor: const Color(0xFF1E293B),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: const InputDecoration(labelText: 'Tipo de Cifrado (Seguridad)', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(
                      value: 'psk2',
                      child: Text('WPA2-PSK (Recomendado)', overflow: TextOverflow.ellipsis),
                    ),
                    DropdownMenuItem(
                      value: 'sae-mixed',
                      child: Text('WPA2 / WPA3 Mixto (Moderno)', overflow: TextOverflow.ellipsis),
                    ),
                    DropdownMenuItem(
                      value: 'sae',
                      child: Text('WPA3-SAE (Estricto)', overflow: TextOverflow.ellipsis),
                    ),
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
                    isExpanded: true,
                    dropdownColor: const Color(0xFF1E293B),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(labelText: 'Cifrado 5 GHz', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(
                        value: 'psk2',
                        child: Text('WPA2-PSK (Recomendado)', overflow: TextOverflow.ellipsis),
                      ),
                      DropdownMenuItem(
                        value: 'sae-mixed',
                        child: Text('WPA2 / WPA3 Mixto', overflow: TextOverflow.ellipsis),
                      ),
                      DropdownMenuItem(
                        value: 'sae',
                        child: Text('WPA3-SAE', overflow: TextOverflow.ellipsis),
                      ),
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
                  isExpanded: true,
                  dropdownColor: const Color(0xFF1E293B),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: const InputDecoration(labelText: 'Nivel de Potencia', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(
                      value: 23,
                      child: Text('⚡ 23 dBm (100% - Máxima Cobertura)', overflow: TextOverflow.ellipsis),
                    ),
                    DropdownMenuItem(
                      value: 20,
                      child: Text('🟢 20 dBm (75% - Cobertura Alta)', overflow: TextOverflow.ellipsis),
                    ),
                    DropdownMenuItem(
                      value: 17,
                      child: Text('🟡 17 dBm (50% - Cobertura Media)', overflow: TextOverflow.ellipsis),
                    ),
                    DropdownMenuItem(
                      value: 14,
                      child: Text('🔵 14 dBm (25% - Ahorro Energético)', overflow: TextOverflow.ellipsis),
                    ),
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

                const SizedBox(height: 14),
                // Canales de Transmisión Wi-Fi (Auto / Manual)
                const Text('Canales de Transmisión Wi-Fi', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF38BDF8))),
                const SizedBox(height: 4),
                const Text('Elige "Auto" para que el router seleccione el canal óptimo dinámicamente, o fija un canal manual.', style: TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11].contains(_mainChannel24) ? _mainChannel24 : 0,
                        isExpanded: true,
                        dropdownColor: const Color(0xFF1E293B),
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: const InputDecoration(
                          labelText: 'Canal 2.4 GHz',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('Auto', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: 1, child: Text('Canal 1 (2412 MHz)', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: 2, child: Text('Canal 2 (2417 MHz)', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: 3, child: Text('Canal 3 (2422 MHz)', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: 4, child: Text('Canal 4 (2427 MHz)', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: 5, child: Text('Canal 5 (2432 MHz)', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: 6, child: Text('Canal 6 (2437 MHz)', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: 7, child: Text('Canal 7 (2442 MHz)', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: 8, child: Text('Canal 8 (2447 MHz)', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: 9, child: Text('Canal 9 (2452 MHz)', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: 10, child: Text('Canal 10 (2457 MHz)', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: 11, child: Text('Canal 11 (2462 MHz)', overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _mainChannel24 = val);
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: [0, 36, 40, 44, 48, 149, 153, 157, 161].contains(_mainChannel5) ? _mainChannel5 : 0,
                        isExpanded: true,
                        dropdownColor: const Color(0xFF1E293B),
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: const InputDecoration(
                          labelText: 'Canal 5 GHz',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('Auto', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: 36, child: Text('Canal 36 (5180 MHz)', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: 40, child: Text('Canal 40 (5200 MHz)', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: 44, child: Text('Canal 44 (5220 MHz)', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: 48, child: Text('Canal 48 (5240 MHz)', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: 149, child: Text('Canal 149 (5745 MHz)', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: 153, child: Text('Canal 153 (5765 MHz)', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: 157, child: Text('Canal 157 (5785 MHz)', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: 161, child: Text('Canal 161 (5805 MHz)', overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _mainChannel5 = val);
                        },
                      ),
                    ),
                  ],
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
                          isExpanded: true,
                          dropdownColor: const Color(0xFF1E293B),
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: const InputDecoration(labelText: 'Servidores DNS', border: OutlineInputBorder(), isDense: true),
                          items: const [
                            DropdownMenuItem(
                              value: '1.1.1.1,1.0.0.1',
                              child: Text('Cloudflare Rápido (1.1.1.1, 1.0.0.1)', overflow: TextOverflow.ellipsis),
                            ),
                            DropdownMenuItem(
                              value: '8.8.8.8,8.8.4.4',
                              child: Text('Google DNS (8.8.8.8, 8.8.4.4)', overflow: TextOverflow.ellipsis),
                            ),
                            DropdownMenuItem(
                              value: 'manual',
                              child: Text('DNS Personalizado', overflow: TextOverflow.ellipsis),
                            ),
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
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: _isLoadingLeases ? null : _openDhcpLeasesSheet,
                          icon: const Icon(Icons.devices, color: Color(0xFF38BDF8), size: 18),
                          label: const Text('Ver Concesiones DHCP Activas (Leases)', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFF0284C7)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
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
        // Guía Rápida de Adopción
        Card(
          color: const Color(0xFF0F2B48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF0284C7), width: 1.5),
          ),
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.wifi_tethering, color: Color(0xFF38BDF8), size: 24),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Asistente de Adopción Mesh Directo',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 10),
                Text(
                  'Sigue estos 4 pasos para vincular tu Satélite Motorola:\n\n'
                  '1️⃣ Conecta un cable de red desde el puerto LAN del Router Principal al puerto WAN (azul/globo) del Satélite SOLO durante la adopción y enciéndelo.\n'
                  '2️⃣ Conecta tu teléfono al Wi-Fi de fábrica del satélite (ej: Motorola-XXXX) o a tu Wi-Fi principal.\n'
                  '3️⃣ Ingresa o escanea la clave de etiqueta del satélite y pulsa "Adoptar y Convertir en Satélite Mesh".\n'
                  '4️⃣ Cuando aparezca la barra de progreso de 40 segundos, desconecta el cable de red entre ambos equipos para que el satélite opere de forma inalámbrica.',
                  style: TextStyle(fontSize: 12, color: Colors.white70, height: 1.45),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Card 1: Datos de la Red Mesh a Sincronizar
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
                    Text('1. Datos de tu Malla Mesh', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                ),
                const SizedBox(height: 12),

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
                            const Text('Siguiente IP fija que se le asignará:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                            const SizedBox(height: 2),
                            Text(
                              _calculatedNextIp,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF38BDF8)),
                            ),
                            Text(
                              'Puerta de enlace principal: $_currentIp',
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

                const SizedBox(height: 14),

                // Selector de Banda de Enlace (Backhaul Mesh)
                const Text('Banda de Enlace entre Routers (Backhaul):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: _selectedBackhaulBand,
                  dropdownColor: const Color(0xFF1E293B),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    prefixIcon: Icon(Icons.settings_input_antenna, color: Color(0xFF38BDF8)),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: '2.4 GHz',
                      child: Text('🟢 2.4 GHz (Mayor Cobertura / Muros)', overflow: TextOverflow.ellipsis),
                    ),
                    DropdownMenuItem(
                      value: '5 GHz',
                      child: Text('⚡ 5 GHz (Alta Velocidad / Cercano)', overflow: TextOverflow.ellipsis),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedBackhaulBand = val);
                  },
                ),
                const SizedBox(height: 4),
                Text(
                  _selectedBackhaulBand.contains('5')
                      ? 'Recomendado si están en la misma habitación o sin muros densos.'
                      : 'Recomendado para atravesar paredes de concreto y pisos con estabilidad.',
                  style: const TextStyle(fontSize: 11, color: Colors.white54),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Card 2: Clave de Etiqueta y Ejecución
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('2. Autorizar y Convertir', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 12),

                TextField(
                  controller: _addSatPassController,
                  obscureText: _addSatPassObscure,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Contraseña de etiqueta del Satélite',
                    helperText: 'Impresa en la base del equipo nuevo o leída por QR',
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

                const SizedBox(height: 20),

                ElevatedButton.icon(
                  onPressed: _isProvisioningSat ? null : _runProvisionDirectSatellite,
                  icon: _isProvisioningSat
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                      : const Icon(Icons.bolt, size: 22),
                  label: Text(
                    _isProvisioningSat ? 'Configurando Satélite...' : 'Adoptar y Convertir en Satélite Mesh',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '💡 El proceso ajusta canales, clona tu red, asigna IP fija y unifica los puertos de red.\nAl finalizar, el satélite funcionará tanto de forma inalámbrica como por cable en cualquier puerto.',
                  style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.35),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // =========================================================================
  Widget _buildControlSatellitesTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Header de acción responsivo
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Satélites Mesh Activos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 2),
            const Text('Monitoreo en vivo y control individual de nodos', style: TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isDiscoveringSatellites ? null : () => _autoDiscoverSatellites(),
                    icon: _isDiscoveringSatellites
                        ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.radar, size: 16, color: Colors.white),
                    label: const Text('Detectar Satélites', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isCheckingAllNodes ? null : _checkAllNodes,
                    icon: _isCheckingAllNodes
                        ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.refresh, size: 16, color: Colors.white),
                    label: const Text('Comprobar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
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
                      Row(
                        children: [
                          Text('IP: ${node.ip}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: () => _editNodeIp(node),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              child: Row(
                                children: [
                                  Icon(Icons.edit, size: 12, color: Color(0xFF60A5FA)),
                                  SizedBox(width: 2),
                                  Text('Editar', style: TextStyle(fontSize: 10, color: Color(0xFF60A5FA), fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                          if (node.ip != '192.168.1.2') ...[
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: () => _fixNodeIpToTarget(node, '192.168.1.2'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0284C7).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: const Color(0xFF0284C7), width: 1),
                                ),
                                child: const Text('Fijar a .2', style: TextStyle(fontSize: 9, color: Color(0xFF38BDF8), fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
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
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: () => _switchNodeBackhaulBand(node),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: node.backhaulBand.contains('5') ? const Color(0xFF6366F1).withOpacity(0.2) : const Color(0xFF10B981).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: node.backhaulBand.contains('5') ? const Color(0xFF818CF8) : const Color(0xFF34D399), width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              node.backhaulBand.contains('5') ? '⚡ 5 GHz' : '🟢 2.4 GHz',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: node.backhaulBand.contains('5') ? const Color(0xFFA5B4FC) : const Color(0xFF6EE7B7),
                              ),
                            ),
                            const SizedBox(width: 3),
                            const Icon(Icons.swap_horiz, size: 11, color: Colors.white70),
                          ],
                        ),
                      ),
                    ),
                  ],
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

            // Controles Individuales: Potencia de Transmisión
            DropdownButtonFormField<int>(
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
            const SizedBox(height: 10),
            // Botones con texto y etiquetas legibles
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: node.isChecking ? null : () => _checkNodeQuality(node),
                    icon: node.isChecking
                        ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.network_check, size: 16, color: Colors.white),
                    label: const Text('Comprobar', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _rebootNode(node),
                    icon: const Icon(Icons.restart_alt, size: 16, color: Colors.white),
                    label: const Text('Reiniciar', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Eliminar Satélite',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.red.shade900.withOpacity(0.4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _removeSatellite(node),
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
