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

  final TextEditingController _ipController = TextEditingController(text: '192.168.1.1');
  final TextEditingController _passController = TextEditingController();
  final TextEditingController _ssidController = TextEditingController();
  final TextEditingController _keyController = TextEditingController();
  final TextEditingController _sat2PassController = TextEditingController();
  final TextEditingController _sat3PassController = TextEditingController();

  bool _isLoading = false;

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.redAccent : Colors.blueAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _unlockRouter() async {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) return _showSnack('Ingresa la IP primero', isError: true);

    setState(() => _isLoading = true);
    await RouterService.unlockRouter(ip);
    setState(() => _isLoading = false);
    _showSnack('Señal de desbloqueo enviada (LuCI y SSH activos)');
  }

  Future<void> _login() async {
    final ip = _ipController.text.trim();
    final pass = _passController.text.trim();
    if (ip.isEmpty || pass.isEmpty) {
      return _showSnack('Ingresa IP y Contraseña', isError: true);
    }

    setState(() => _isLoading = true);
    try {
      final status = await RouterService.getStatus(ip, pass);
      setState(() {
        _isConnected = true;
        _currentIp = ip;
        _currentPassword = pass;
        _status = status;
      });
      _showSnack('Conectado al router Motorola');
    } catch (e) {
      _showSnack('Error de conexión: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveWifi() async {
    final ssid = _ssidController.text.trim();
    final key = _keyController.text.trim();
    if (ssid.isEmpty || key.isEmpty) {
      return _showSnack('Completa SSID y contraseña', isError: true);
    }

    setState(() => _isLoading = true);
    try {
      await RouterService.setWifiConfig(
        _currentIp,
        _currentPassword,
        ssid: ssid,
        key: key,
      );
      _showSnack('Wi-Fi y Roaming 802.11r actualizados');
    } catch (e) {
      _showSnack('Error al guardar Wi-Fi: $e', isError: true);
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
      await RouterService.unlockRouter(targetIp);
      await RouterService.configureMeshSatellite(
        satIp: targetIp,
        satPassword: satPassword,
        targetIp: targetIp,
        mainGateway: _currentIp,
        ssid: _ssidController.text.trim(),
        key: _keyController.text.trim(),
      );
      _showSnack('Nodo satélite $targetIp emparejado a la malla');
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
          title: const Text('MotoRouter Manager', style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF1E293B),
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.wifi_tethering, size: 52, color: Color(0xFF2563EB)),
                    const SizedBox(height: 12),
                    const Text(
                      'Gestión Local Motorola MH7601',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Control autónomo sin dependencia de MotoSync / Minim Cloud',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.lock_open, size: 18),
                      label: const Text('1. Desbloquear Router (1 clic)'),
                      onPressed: _isLoading ? null : _unlockRouter,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.indigoAccent,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _ipController,
                      decoration: const InputDecoration(
                        labelText: 'IP del Router',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.dns),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Contraseña de fábrica (Etiqueta)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.key),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('Conectar al Router', style: TextStyle(fontSize: 16)),
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
        title: Text(_status?.model ?? 'Motorola Router'),
        backgroundColor: const Color(0xFF1E293B),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
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
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Router Principal', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                Text(_status?.model ?? 'MH7601', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text('IP: $_currentIp', style: const TextStyle(color: Colors.grey)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Dispositivos Conectados', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (_status?.clients.isEmpty ?? true)
                  const Text('No hay clientes DHCP registrados', style: TextStyle(color: Colors.grey))
                else
                  ..._status!.clients.map((c) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.devices, color: Colors.blueAccent),
                    title: Text(c.name),
                    subtitle: Text(c.mac, style: const TextStyle(fontSize: 11)),
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
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Configurar Red Wi-Fi (2.4 & 5 GHz)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                TextField(
                  controller: _ssidController,
                  decoration: const InputDecoration(labelText: 'Nombre de red (SSID)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _keyController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Contraseña Wi-Fi', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _isLoading ? null : _saveWifi,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB)),
                  child: const Text('Guardar y Aplicar Wi-Fi'),
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
      children: const [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Ajustes de Enrutamiento y DHCP activos bajo OpenWrt UCI.'),
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
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Asistente Mesh Tripack', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('Sincroniza los otros 2 routers MH7601 como satélites sin DHCP y con el mismo Wi-Fi.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const Divider(height: 24),
                const Text('Nodo Satélite 2 (IP: 192.168.1.2)', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(
                  controller: _sat2PassController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Clave etiqueta Satélite 2', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () => _setupSatellite('192.168.1.2', _sat2PassController.text.trim()),
                  child: const Text('Sincronizar Satélite 2'),
                ),
                const Divider(height: 24),
                const Text('Nodo Satélite 3 (IP: 192.168.1.3)', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(
                  controller: _sat3PassController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Clave etiqueta Satélite 3', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () => _setupSatellite('192.168.1.3', _sat3PassController.text.trim()),
                  child: const Text('Sincronizar Satélite 3'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
