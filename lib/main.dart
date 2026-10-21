import 'package:flutter/material.dart';
import 'services/router_service.dart';

void main() {
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
      ),
      home: const MainNavigationScreen(),
    );
  }
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

  // Controllers Login
  final TextEditingController _ipController = TextEditingController(text: '192.168.1.1');
  final TextEditingController _passController = TextEditingController();

  // Wi-Fi State
  bool _separateBands = false;
  final TextEditingController _ssid24Controller = TextEditingController();
  final TextEditingController _key24Controller = TextEditingController();
  String _enc24 = 'psk2';

  final TextEditingController _ssid5Controller = TextEditingController();
  final TextEditingController _key5Controller = TextEditingController();
  String _enc5 = 'psk2';

  int _txPower = 23; // 23 = Max (100%), 20 = Alta (75%), 17 = Media (50%), 14 = Baja (25%)
  bool _legacyMode = false; // Compatibilidad con dispositivos sin Wi-Fi 6

  // DHCP State
  final TextEditingController _dhcpStartController = TextEditingController(text: '100');
  final TextEditingController _dhcpLimitController = TextEditingController(text: '150');
  String _selectedDns = '1.1.1.1,1.0.0.1';

  // Port Forward State
  final TextEditingController _pfNameController = TextEditingController();
  final TextEditingController _pfExtPortController = TextEditingController();
  final TextEditingController _pfIntIpController = TextEditingController();
  final TextEditingController _pfIntPortController = TextEditingController();
  String _pfProto = 'tcp udp';

  // Mesh Satellites State
  final TextEditingController _sat2CurrentIpController = TextEditingController(text: '192.168.1.147');
  final TextEditingController _sat2TargetIpController = TextEditingController(text: '192.168.1.2');
  final TextEditingController _sat2PassController = TextEditingController();
  int _sat2TxPower = 23;
  SatelliteQuality? _sat2Quality;
  bool _checkingSat2 = false;
  bool _sat2PassObscure = true;

  final TextEditingController _sat3CurrentIpController = TextEditingController(text: '192.168.1.3');
  final TextEditingController _sat3TargetIpController = TextEditingController(text: '192.168.1.3');
  final TextEditingController _sat3PassController = TextEditingController();
  int _sat3TxPower = 23;
  SatelliteQuality? _sat3Quality;
  bool _checkingSat3 = false;
  bool _sat3PassObscure = true;

  // Site Survey State
  bool _isScanningMesh = false;
  bool _showAllSurveyClients = false;

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
        backgroundColor: isError ? Colors.redAccent : const Color(0xFF2563EB),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _autoDetectSatellites(List<ConnectedClient> clients) {
    final satCandidates = clients.where((c) {
      final name = c.name.toUpperCase();
      final mac = c.mac.toLowerCase();
      final isMoto = name.contains('MH') || name.contains('MOTO') || 
                     mac.startsWith('c8:c7:50') || mac.startsWith('00:0c:e7') || mac.startsWith('14:59:c0');
      return isMoto && c.ip != _currentIp;
    }).toList();

    if (satCandidates.isNotEmpty) {
      _sat2CurrentIpController.text = satCandidates[0].ip;
      if (satCandidates.length > 1) {
        _sat3CurrentIpController.text = satCandidates[1].ip;
      }
    }
  }

  // Login y desbloqueo automático
  Future<void> _login() async {
    final ip = _ipController.text.trim();
    final pass = _passController.text.trim();
    if (ip.isEmpty || pass.isEmpty) {
      return _showSnack('Ingresa IP y Contraseña', isError: true);
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
        _autoDetectSatellites(status.clients);
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
        _ssid24Controller.text = wifi.ssid24;
        _key24Controller.text = wifi.key24;
        _enc24 = wifi.enc24;

        _ssid5Controller.text = wifi.ssid5;
        _key5Controller.text = wifi.key5;
        _enc5 = wifi.enc5;

        _txPower = wifi.txPower;
        _legacyMode = wifi.legacyMode;
      });
    } catch (_) {}
  }

  Future<void> _loadDhcpConfig() async {
    try {
      final dhcp = await RouterService.getDhcpConfig(_currentIp, _currentPassword);
      setState(() {
        _dhcpStartController.text = dhcp.start.toString();
        _dhcpLimitController.text = dhcp.limit.toString();
        _selectedDns = dhcp.dns;
      });
    } catch (_) {}
  }

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
      _showSnack('Wi-Fi, Cifrado y Potencia actualizados correctamente');
    } catch (e) {
      _showSnack('Error al guardar Wi-Fi: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveDhcp() async {
    setState(() => _isLoading = true);
    try {
      final cfg = DhcpConfigData(
        start: int.tryParse(_dhcpStartController.text.trim()) ?? 100,
        limit: int.tryParse(_dhcpLimitController.text.trim()) ?? 150,
        dns: _selectedDns,
      );
      await RouterService.saveDhcpConfig(_currentIp, _currentPassword, cfg);
      _showSnack('Servidor DHCP y DNS actualizados');
    } catch (e) {
      _showSnack('Error al guardar DHCP: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _addPortForward() async {
    final name = _pfNameController.text.trim();
    final extPort = _pfExtPortController.text.trim();
    final intIp = _pfIntIpController.text.trim();
    final intPort = _pfIntPortController.text.trim().isEmpty ? extPort : _pfIntPortController.text.trim();

    if (name.isEmpty || extPort.isEmpty || intIp.isEmpty) {
      return _showSnack('Completa los campos del puerto', isError: true);
    }

    setState(() => _isLoading = true);
    try {
      await RouterService.addPortForward(
        _currentIp,
        _currentPassword,
        name: name,
        proto: _pfProto,
        extPort: extPort,
        intIp: intIp,
        intPort: intPort,
      );
      _showSnack('Regla de puerto $extPort agregada al firewall');
      _pfNameController.clear();
      _pfExtPortController.clear();
    } catch (e) {
      _showSnack('Error agregando regla: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Escaneo interactivo de Satélites Mesh (Site Survey)
  Future<void> _scanMeshNodes() async {
    setState(() => _isScanningMesh = true);
    try {
      final status = await RouterService.getStatus(_currentIp, _currentPassword);
      setState(() {
        _status = status;
        _autoDetectSatellites(status.clients);
      });
      _showSnack('Radar Mesh: ${status.clients.length} dispositivos detectados');
    } catch (e) {
      _showSnack('Error al escanear dispositivos: $e', isError: true);
    } finally {
      setState(() => _isScanningMesh = false);
    }
  }

  // Comprobar calidad de satélite
  Future<void> _checkQuality(String satIp, bool isSat2) async {
    if (satIp.isEmpty) {
      return _showSnack('Ingresa la IP del satélite a comprobar', isError: true);
    }
    setState(() {
      if (isSat2) _checkingSat2 = true;
      else _checkingSat3 = true;
    });

    try {
      final q = await RouterService.checkSatelliteQuality(_currentIp, _currentPassword, satIp);
      setState(() {
        if (isSat2) _sat2Quality = q;
        else _sat3Quality = q;
      });
      _showSnack('Diagnóstico completado para $satIp: ${q.statusText}');
    } catch (e) {
      _showSnack('Error midiendo calidad en $satIp: $e', isError: true);
    } finally {
      setState(() {
        if (isSat2) _checkingSat2 = false;
        else _checkingSat3 = false;
      });
    }
  }

  // Ajustar potencia satélite
  Future<void> _applySatellitePower(String satIp, String satPassword, int txPower) async {
    if (satPassword.isEmpty) {
      return _showSnack('Ingresa la contraseña del satélite primero', isError: true);
    }

    setState(() => _isLoading = true);
    try {
      await RouterService.setSatelliteTxPower(satIp, satPassword, txPower);
      _showSnack('Potencia de transmisión ($txPower dBm) aplicada en $satIp');
    } catch (e) {
      _showSnack('Error aplicando potencia: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _setupSatellite({
    required String currentIp,
    required String targetIp,
    required String satPassword,
    required int txPower,
    required bool isSat2,
  }) async {
    if (satPassword.isEmpty) {
      return _showSnack('Ingresa la contraseña de la etiqueta del satélite', isError: true);
    }
    if (currentIp.isEmpty || targetIp.isEmpty) {
      return _showSnack('Debes especificar la IP actual y la IP estática final', isError: true);
    }

    setState(() => _isLoading = true);
    try {
      _showSnack('Paso 1/3: Desbloqueando satélite en $currentIp...');
      await RouterService.unlockRouter(currentIp, satPassword);
      await Future.delayed(const Duration(seconds: 2));

      _showSnack('Paso 2/3: Sincronizando Wi-Fi y configurando red mesh...');
      final ssid = _ssid24Controller.text.trim().isNotEmpty
          ? _ssid24Controller.text.trim()
          : (_wifiConfig?.ssid24 ?? 'MotoWiFi');
      final key = _key24Controller.text.trim().isNotEmpty
          ? _key24Controller.text.trim()
          : (_wifiConfig?.key24 ?? '');

      await RouterService.configureMeshSatellite(
        satIp: currentIp,
        satPassword: satPassword,
        targetIp: targetIp,
        mainGateway: _currentIp,
        ssid: ssid,
        key: key,
        encryption: _enc24,
        txPower: txPower,
      );

      _showSnack('Paso 3/3: Activando Roaming 802.11r en router principal...');
      await RouterService.enableMeshRoamingOnMain(_currentIp, _currentPassword);

      setState(() {
        if (isSat2) {
          _sat2CurrentIpController.text = targetIp;
        } else {
          _sat3CurrentIpController.text = targetIp;
        }
      });

      _showSnack('¡Satélite sincronizado! Ahora opera en $targetIp');

      // Medir calidad a la nueva IP
      await Future.delayed(const Duration(seconds: 4));
      _checkQuality(targetIp, isSat2);
    } catch (e) {
      _showSnack('Error al vincular satélite en $currentIp: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isConnected) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Lan Router Management', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          backgroundColor: const Color(0xFF1E293B),
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
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
                      'Gestión Local Motorola MH7601',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Desbloqueo y gestión directa sin MotoSync Cloud',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _ipController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'IP del Router',
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
                              'Conectar y Desbloquear Router',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final pages = [
      _buildDashboardTab(),
      _buildWifiTab(),
      _buildNetworkTab(),
      _buildMeshTab(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_status?.model ?? 'Motorola Router', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: const Color(0xFF1E293B),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () => setState(() => _isConnected = false),
          ),
        ],
      ),
      body: pages[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Estado'),
          NavigationDestination(icon: Icon(Icons.wifi_outlined), selectedIcon: Icon(Icons.wifi), label: 'Wi-Fi'),
          NavigationDestination(icon: Icon(Icons.lan_outlined), selectedIcon: Icon(Icons.lan), label: 'Red/DHCP'),
          NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view), label: 'Mesh'),
        ],
      ),
    );
  }

  Widget _buildDashboardTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Router Principal', style: TextStyle(color: Color(0xFF3B82F6), fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(_status?.model ?? 'MH7601', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                Text('IP Local: $_currentIp', style: const TextStyle(color: Colors.grey)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          color: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Dispositivos Conectados', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 10),
                if (_status?.clients.isEmpty ?? true)
                  const Text('No hay clientes DHCP registrados', style: TextStyle(color: Colors.grey))
                else
                  ..._status!.clients.map((c) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFF2563EB),
                      radius: 16,
                      child: Icon(Icons.devices, size: 16, color: Colors.white),
                    ),
                    title: Text(c.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    subtitle: Text(c.mac, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    trailing: Text(c.ip, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.greenAccent)),
                  )),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          color: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(Icons.tune, color: Color(0xFF818CF8), size: 18),
                    SizedBox(width: 8),
                    Text('Mantenimiento del Sistema', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: const Color(0xFF1E293B),
                        title: const Text('Reiniciar Router', style: TextStyle(color: Colors.white)),
                        content: const Text('¿Estás seguro de que deseas reiniciar el equipo?', style: TextStyle(color: Colors.white70)),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB)),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Reiniciar', style: TextStyle(color: Colors.white)),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      try {
                        await RouterService.executeSSH(_currentIp, _currentPass, 'reboot');
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reinicio enviado... Espera 90 segundos')));
                        }
                      } catch (_) {}
                    }
                  },
                  icon: const Icon(Icons.restart_alt, color: Colors.amber),
                  label: const Text('Reiniciar Router', style: TextStyle(color: Colors.white)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: const Color(0xFF1E293B),
                        title: const Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
                            SizedBox(width: 8),
                            Text('Reset Default', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        content: const Text(
                          '⚠️ ADVERTENCIA: Esta acción borrará todas las configuraciones personalizadas y restablecerá el router a los valores de fábrica de la etiqueta.\n\n¿Deseas continuar con el restablecimiento completo?',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Sí, Restablecer Todo', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      try {
                        await RouterService.factoryReset(_currentIp, _currentPass);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              backgroundColor: Colors.redAccent,
                              content: Text('Restablecimiento de fábrica iniciado. El router se reiniciará con su clave de fábrica.'),
                              duration: Duration(seconds: 6),
                            ),
                          );
                          setState(() => _isConnected = false);
                        }
                      } catch (err) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $err')));
                        }
                      }
                    }
                  },
                  icon: const Icon(Icons.restore, color: Colors.white),
                  label: const Text('Reset Default (Valores de Fábrica)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF991B1B),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWifiTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Configurar Red Wi-Fi', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 4),
                const Text('Nombre, clave, cifrado y potencia de señal con Roaming 802.11r activo', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 14),

                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Separar bandas (2.4 GHz y 5 GHz)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
                  subtitle: Text(
                    _separateBands ? 'Dos nombres de red independientes' : 'Un solo nombre unificado inteligente',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  value: _separateBands,
                  onChanged: (val) => setState(() => _separateBands = val),
                ),
                const Divider(height: 20),

                // Banda 2.4 GHz (o Principal)
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
                  obscureText: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Contraseña Wi-Fi', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _enc24,
                  dropdownColor: const Color(0xFF1E293B),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: const InputDecoration(labelText: 'Tipo de Cifrado (Seguridad)', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'psk2', child: Text('WPA2-PSK (Recomendado para máxima compatibilidad)')),
                    DropdownMenuItem(value: 'sae-mixed', child: Text('WPA2 / WPA3 Personal (Mixto)')),
                    DropdownMenuItem(value: 'sae', child: Text('WPA3-SAE (Estricto)')),
                    DropdownMenuItem(value: 'psk-mixed', child: Text('WPA / WPA2 (Dispositivos muy antiguos)')),
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
                    obscureText: true,
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

                // Control de Potencia de Transmisión (Tx Power)
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
                    DropdownMenuItem(value: 20, child: Text('🟢 20 dBm (75% - Alta)')),
                    DropdownMenuItem(value: 17, child: Text('🟡 17 dBm (50% - Media / Espacios pequeños)')),
                    DropdownMenuItem(value: 14, child: Text('🔵 14 dBm (25% - Baja / Ahorro energético)')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _txPower = v);
                  },
                ),

                const SizedBox(height: 16),

                // Switch Modo Compatibilidad Wi-Fi 6
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Modo Compatibilidad IoT / Dispositivos Antiguos', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
                  subtitle: const Text(
                    'Desactiva 802.11ax en 2.4 GHz para que bombillos inteligentes, enchufes y celulares viejos se conecten sin fallos',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  value: _legacyMode,
                  onChanged: (val) => setState(() => _legacyMode = val),
                ),

                const SizedBox(height: 22),
                ElevatedButton(
                  onPressed: _isLoading ? null : _saveWifi,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Guardar y Aplicar Configuración Wi-Fi', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNetworkTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Card DHCP y DNS
        Card(
          color: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Servidor DHCP y DNS', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _dhcpStartController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(labelText: 'IP Inicio', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _dhcpLimitController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(labelText: 'Límite IPs', border: OutlineInputBorder()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _selectedDns.contains('1.1.1.1') ? '1.1.1.1,1.0.0.1' : (_selectedDns.contains('8.8.8.8') ? '8.8.8.8,8.8.4.4' : '1.1.1.1,1.0.0.1'),
                  decoration: const InputDecoration(labelText: 'Servidores DNS', border: OutlineInputBorder()),
                  dropdownColor: const Color(0xFF1E293B),
                  items: const [
                    DropdownMenuItem(value: '1.1.1.1,1.0.0.1', child: Text('Cloudflare (1.1.1.1) - Rápido')),
                    DropdownMenuItem(value: '8.8.8.8,8.8.4.4', child: Text('Google DNS (8.8.8.8) - Estable')),
                    DropdownMenuItem(value: '9.9.9.9,149.112.112.112', child: Text('Quad9 (9.9.9.9) - Seguridad')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedDns = val);
                  },
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _isLoading ? null : _saveDhcp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Actualizar DHCP y DNS', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Card Port Forwarding
        Card(
          color: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Reenvío de Puertos (Port Forward)', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 12),
                TextField(
                  controller: _pfNameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Nombre regla (ej: Camara / Servidor)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _pfExtPortController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(labelText: 'Puerto Externo', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _pfProto,
                        decoration: const InputDecoration(labelText: 'Protocolo', border: OutlineInputBorder()),
                        dropdownColor: const Color(0xFF1E293B),
                        items: const [
                          DropdownMenuItem(value: 'tcp udp', child: Text('TCP/UDP')),
                          DropdownMenuItem(value: 'tcp', child: Text('TCP')),
                          DropdownMenuItem(value: 'udp', child: Text('UDP')),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _pfProto = val);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _pfIntIpController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(labelText: 'IP Destino (192.168.1.X)', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: TextField(
                        controller: _pfIntPortController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(labelText: 'Puerto Int.', border: OutlineInputBorder()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _isLoading ? null : _addPortForward,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Abrir Puerto', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMeshTab() {
    final clients = _status?.clients ?? [];
    final satCandidates = clients.where((c) {
      final name = c.name.toUpperCase();
      final mac = c.mac.toLowerCase();
      final isMoto = name.contains('MH') || name.contains('MOTO') || 
                     mac.startsWith('c8:c7:50') || mac.startsWith('00:0c:e7') || mac.startsWith('14:59:c0');
      return isMoto && c.ip != _currentIp;
    }).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // TARJETA DE SITE SURVEY / DETECCIÓN AUTOMÁTICA
        Card(
          color: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF38BDF8), width: 1.2),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.radar, color: Color(0xFF38BDF8), size: 24),
                        const SizedBox(width: 8),
                        const Text('Site Survey / Radar Mesh', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                      ],
                    ),
                    ElevatedButton.icon(
                      onPressed: _isScanningMesh ? null : _scanMeshNodes,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0284C7),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: _isScanningMesh
                          ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.refresh, size: 16),
                      label: Text(_isScanningMesh ? 'Buscando...' : 'Escanear', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Detecta nodos Motorola MH7601 conectados con IP asignada por DHCP y vincúlalos automáticamente.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),

                if (satCandidates.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF064E3B).withOpacity(0.4),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.greenAccent.withOpacity(0.4)),
                    ),
                    child: Text(
                      '📡 ¡Se encontraron ${satCandidates.length} satélite(s) Motorola en la red!',
                      style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...satCandidates.map((c) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.5)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const CircleAvatar(
                              radius: 16,
                              backgroundColor: Color(0xFF1E3A8A),
                              child: Icon(Icons.router, color: Colors.cyanAccent, size: 18),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${c.name} (Satélite Detectado)',
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14),
                                  ),
                                  Text('IP Actual: ${c.ip} • MAC: ${c.mac}', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _sat2CurrentIpController.text = c.ip;
                                  });
                                  _showSnack('IP ${c.ip} asignada a Satélite 2. Ingresa su clave y pulsa Sincronizar.');
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF2563EB),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                icon: const Icon(Icons.check_circle_outline, size: 14),
                                label: const Text('Usar como Satélite 2', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _sat3CurrentIpController.text = c.ip;
                                  });
                                  _showSnack('IP ${c.ip} asignada a Satélite 3. Ingresa su clave y pulsa Sincronizar.');
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF4F46E5),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                icon: const Icon(Icons.check_circle_outline, size: 14),
                                label: const Text('Usar como Satélite 3', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'No se han detectado automáticamente satélites Motorola nuevos.\nEnciende el nodo satélite y conéctalo al router (por cable o cerca) y presiona "Escanear".',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ),
                ],

                // Opción para ver todos los clientes conectados
                const SizedBox(height: 6),
                InkWell(
                  onTap: () => setState(() => _showAllSurveyClients = !_showAllSurveyClients),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Ver todos los dispositivos DHCP / ARP (${clients.length})',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF38BDF8), fontWeight: FontWeight.w600),
                        ),
                        Icon(_showAllSurveyClients ? Icons.expand_less : Icons.expand_more, color: const Color(0xFF38BDF8), size: 18),
                      ],
                    ),
                  ),
                ),
                if (_showAllSurveyClients) ...[
                  const Divider(color: Colors.white24),
                  if (clients.isEmpty)
                    const Text('No hay clientes en la tabla de asignaciones', style: TextStyle(color: Colors.grey, fontSize: 11))
                  else
                    ...clients.map((cl) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.devices, color: Colors.grey, size: 18),
                      title: Text('${cl.name} (${cl.ip})', style: const TextStyle(color: Colors.white, fontSize: 12)),
                      subtitle: Text(cl.mac, style: const TextStyle(color: Colors.grey, fontSize: 10)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6)),
                            onPressed: () {
                              setState(() => _sat2CurrentIpController.text = cl.ip);
                              _showSnack('IP ${cl.ip} asignada a Satélite 2');
                            },
                            child: const Text('Sat 2', style: TextStyle(fontSize: 11, color: Color(0xFF60A5FA))),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6)),
                            onPressed: () {
                              setState(() => _sat3CurrentIpController.text = cl.ip);
                              _showSnack('IP ${cl.ip} asignada a Satélite 3');
                            },
                            child: const Text('Sat 3', style: TextStyle(fontSize: 11, color: Color(0xFFA5B4FC))),
                          ),
                        ],
                      ),
                    )),
                ],
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // TARJETA DE GESTIÓN MESH TRIPACK (NODOS)
        Card(
          color: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Configuración de Nodos Mesh', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 6),
                const Text(
                  'El satélite se desbloqueará en su IP Actual y se configurará con su IP Estática fija, apagando su propio DHCP y clonando el Wi-Fi con Fast Roaming 802.11r.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const Divider(height: 24),

                // NODO SATELITE 2
                _buildSatelliteCard(
                  name: 'Nodo Satélite 2',
                  currentIpController: _sat2CurrentIpController,
                  targetIpController: _sat2TargetIpController,
                  passController: _sat2PassController,
                  quality: _sat2Quality,
                  checking: _checkingSat2,
                  txPower: _sat2TxPower,
                  obscurePass: _sat2PassObscure,
                  onToggleObscure: () => setState(() => _sat2PassObscure = !_sat2PassObscure),
                  onCheckQuality: () => _checkQuality(_sat2CurrentIpController.text.trim(), true),
                  onPowerChanged: (p) => setState(() => _sat2TxPower = p),
                  onApplyPower: () => _applySatellitePower(_sat2CurrentIpController.text.trim(), _sat2PassController.text.trim(), _sat2TxPower),
                  onSync: () => _setupSatellite(
                    currentIp: _sat2CurrentIpController.text.trim(),
                    targetIp: _sat2TargetIpController.text.trim(),
                    satPassword: _sat2PassController.text.trim(),
                    txPower: _sat2TxPower,
                    isSat2: true,
                  ),
                  accentColor: const Color(0xFF3B82F6),
                ),

                const Divider(height: 32),

                // NODO SATELITE 3
                _buildSatelliteCard(
                  name: 'Nodo Satélite 3',
                  currentIpController: _sat3CurrentIpController,
                  targetIpController: _sat3TargetIpController,
                  passController: _sat3PassController,
                  quality: _sat3Quality,
                  checking: _checkingSat3,
                  txPower: _sat3TxPower,
                  obscurePass: _sat3PassObscure,
                  onToggleObscure: () => setState(() => _sat3PassObscure = !_sat3PassObscure),
                  onCheckQuality: () => _checkQuality(_sat3CurrentIpController.text.trim(), false),
                  onPowerChanged: (p) => setState(() => _sat3TxPower = p),
                  onApplyPower: () => _applySatellitePower(_sat3CurrentIpController.text.trim(), _sat3PassController.text.trim(), _sat3TxPower),
                  onSync: () => _setupSatellite(
                    currentIp: _sat3CurrentIpController.text.trim(),
                    targetIp: _sat3TargetIpController.text.trim(),
                    satPassword: _sat3PassController.text.trim(),
                    txPower: _sat3TxPower,
                    isSat2: false,
                  ),
                  accentColor: const Color(0xFF6366F1),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSatelliteCard({
    required String name,
    required TextEditingController currentIpController,
    required TextEditingController targetIpController,
    required TextEditingController passController,
    required SatelliteQuality? quality,
    required bool checking,
    required int txPower,
    required bool obscurePass,
    required VoidCallback onToggleObscure,
    required VoidCallback onCheckQuality,
    required ValueChanged<int> onPowerChanged,
    required VoidCallback onApplyPower,
    required VoidCallback onSync,
    required Color accentColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(Icons.hub, color: accentColor, size: 20),
                const SizedBox(width: 8),
                Text(name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: accentColor)),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: accentColor.withOpacity(0.5)),
              ),
              child: Text(
                'Mesh: ${targetIpController.text}',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: accentColor),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Campos de IP: IP Actual (DHCP) e IP Estática Mesh
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: currentIpController,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'IP Actual (donde responde)',
                  hintText: 'ej. 192.168.1.147',
                  border: OutlineInputBorder(),
                  isDense: true,
                  helperText: 'IP temporal DHCP',
                  helperStyle: TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: targetIpController,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Nueva IP Estática Mesh',
                  hintText: 'ej. 192.168.1.2',
                  border: OutlineInputBorder(),
                  isDense: true,
                  helperText: 'IP fija final en el Mesh',
                  helperStyle: TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Tarjeta de calidad de enlace si está disponible
        if (quality != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: quality.isOnline ? Colors.green.withOpacity(0.4) : Colors.red.withOpacity(0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(quality.isOnline ? Icons.wifi : Icons.wifi_off, color: quality.isOnline ? Colors.greenAccent : Colors.redAccent, size: 18),
                        const SizedBox(width: 6),
                        Text(quality.statusText, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
                      ],
                    ),
                    Text('${quality.qualityPercent}%', style: TextStyle(fontWeight: FontWeight.bold, color: quality.isOnline ? Colors.greenAccent : Colors.redAccent)),
                  ],
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: quality.qualityPercent / 100,
                  backgroundColor: Colors.grey[800],
                  valueColor: AlwaysStoppedAnimation<Color>(
                    quality.qualityPercent > 70 ? Colors.greenAccent : (quality.qualityPercent > 40 ? Colors.amberAccent : Colors.redAccent),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Tipo: ${quality.linkType}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    Text('Latencia: ${quality.latencyMs} ms', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],

        // Botón Diagnosticar Calidad
        OutlinedButton.icon(
          onPressed: checking ? null : onCheckQuality,
          icon: checking
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.speed, size: 16),
          label: Text(checking ? 'Midiendo enlace...' : 'Ver Calidad de Conexión (${currentIpController.text})', style: const TextStyle(fontSize: 13, color: Colors.white)),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: accentColor),
            padding: const EdgeInsets.symmetric(vertical: 10),
          ),
        ),

        const SizedBox(height: 12),

        // Potencia individual para este satélite
        Row(
          children: [
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<int>(
                value: txPower,
                dropdownColor: const Color(0xFF1E293B),
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: const InputDecoration(labelText: 'Potencia Satélite', border: OutlineInputBorder(), isDense: true),
                items: const [
                  DropdownMenuItem(value: 23, child: Text('⚡ 23 dBm (Máx / 100%)')),
                  DropdownMenuItem(value: 20, child: Text('🟢 20 dBm (Alta / 75%)')),
                  DropdownMenuItem(value: 17, child: Text('🟡 17 dBm (Media / 50%)')),
                  DropdownMenuItem(value: 14, child: Text('🔵 14 dBm (Baja / 25%)')),
                ],
                onChanged: (v) {
                  if (v != null) onPowerChanged(v);
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 1,
              child: ElevatedButton(
                onPressed: onApplyPower,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF334155),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Aplicar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // Clave etiqueta y Sincronizar
        TextField(
          controller: passController,
          obscureText: obscurePass,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Clave etiqueta de este Satélite',
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: IconButton(
              icon: Icon(obscurePass ? Icons.visibility : Icons.visibility_off, color: Colors.grey, size: 20),
              onPressed: onToggleObscure,
            ),
          ),
        ),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          onPressed: onSync,
          style: ElevatedButton.styleFrom(
            backgroundColor: accentColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          icon: const Icon(Icons.sync, color: Colors.white),
          label: const Text('Sincronizar a la Malla Mesh', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
        ),
      ],
    );
  }
}
