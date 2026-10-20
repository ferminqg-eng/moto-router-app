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
      title: 'MotoRouter Mesh Manager',
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
  final TextEditingController _ssid5Controller = TextEditingController();
  final TextEditingController _key5Controller = TextEditingController();

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

  // Mesh Satellites
  final TextEditingController _sat2PassController = TextEditingController();
  final TextEditingController _sat3PassController = TextEditingController();

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
        backgroundColor: isError ? Colors.redAccent : const Color(0xFF2563EB),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // 1. Desbloqueo y Login automático integrado
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
      });

      // Cargar configuraciones actuales
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
        _ssid5Controller.text = wifi.ssid5;
        _key5Controller.text = wifi.key5;
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
        ssid5: _separateBands ? _ssid5Controller.text.trim() : _ssid24Controller.text.trim(),
        key5: _separateBands ? _key5Controller.text.trim() : _key24Controller.text.trim(),
      );

      await RouterService.saveWifiConfig(_currentIp, _currentPassword, cfg);
      _showSnack('Wi-Fi y Roaming 802.11r actualizados correctamente');
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

  Future<void> _setupSatellite(String targetIp, String satPassword) async {
    if (satPassword.isEmpty) {
      return _showSnack('Ingresa la clave del satélite', isError: true);
    }

    setState(() => _isLoading = true);
    try {
      _showSnack('Sincronizando satélite en $targetIp...');
      await RouterService.unlockRouter(targetIp, satPassword);
      await Future.delayed(const Duration(seconds: 2));

      await RouterService.configureMeshSatellite(
        satIp: targetIp,
        satPassword: satPassword,
        targetIp: targetIp,
        mainGateway: _currentIp,
        ssid: _ssid24Controller.text.trim(),
        key: _key24Controller.text.trim(),
      );
      _showSnack('¡Satélite $targetIp emparejado al Mesh!');
    } catch (e) {
      _showSnack('Error al vincular satélite: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isConnected) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('MotoRouter Manager', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
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
                const Text('Modifica el nombre y clave de tus antenas con Roaming 802.11r activo', style: TextStyle(fontSize: 12, color: Colors.grey)),
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

                // Banda 2.4 GHz (o Red Principal si unificado)
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

                if (_separateBands) ...[
                  const SizedBox(height: 16),
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
                ],

                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _isLoading ? null : _saveWifi,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Guardar y Aplicar Wi-Fi', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
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
                const Text('Asistente Mesh Tripack', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 6),
                const Text(
                  'Sincroniza tus nodos satélites 2 y 3. La app apagará su DHCP para evitar colisiones y replicará el Wi-Fi con Roaming 802.11r.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const Divider(height: 24),
                const Text('Nodo Satélite 2 (IP: 192.168.1.2)', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF3B82F6))),
                const SizedBox(height: 6),
                TextField(
                  controller: _sat2PassController,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Clave etiqueta Satélite 2', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: () => _setupSatellite('192.168.1.2', _sat2PassController.text.trim()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Sincronizar Satélite 2', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                ),
                const Divider(height: 24),
                const Text('Nodo Satélite 3 (IP: 192.168.1.3)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigoAccent)),
                const SizedBox(height: 6),
                TextField(
                  controller: _sat3PassController,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Clave etiqueta Satélite 3', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: () => _setupSatellite('192.168.1.3', _sat3PassController.text.trim()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Sincronizar Satélite 3', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
