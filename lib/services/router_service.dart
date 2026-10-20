import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dartssh2/dartssh2.dart';

class RouterStatus {
  final String ip;
  final String model;
  final int uptimeSeconds;
  final List<ConnectedClient> clients;

  RouterStatus({
    required this.ip,
    required this.model,
    required this.uptimeSeconds,
    required this.clients,
  });
}

class ConnectedClient {
  final String mac;
  final String ip;
  final String name;

  ConnectedClient({required this.mac, required this.ip, required this.name});
}

class RouterService {
  /// Envía la petición a los endpoints OEM de Minim para abrir LuCI y SSH
  static Future<bool> unlockRouter(String ip) async {
    final client = HttpClient()
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;

    try {
      final urls = [
        'https://$ip/cgi-bin/luci/admin/minim/enable_admin',
        'https://$ip/cgi-bin/luci/admin/minim/start_sshd',
      ];

      for (var url in urls) {
        try {
          final request = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 4));
          final response = await request.close();
          await response.drain();
        } catch (_) {}
      }
      return true;
    } finally {
      client.close();
    }
  }

  /// Ejecuta un comando en el router mediante SSH directo
  static Future<String> executeSSH(String ip, String password, String command) async {
    final socket = await SSHSocket.connect(ip, 22, timeout: const Duration(seconds: 7));
    final client = SSHClient(
      socket,
      username: 'root',
      onPasswordRequest: () => password,
    );

    try {
      final session = await client.execute(command);
      final stdout = await utf8.decodeStream(session.stdout);
      return stdout.trim();
    } finally {
      client.close();
    }
  }

  /// Obtiene estado del equipo y clientes conectados
  static Future<RouterStatus> getStatus(String ip, String password) async {
    const script = '''
      echo "===UPTIME===" && cat /proc/uptime
      echo "===LEASES===" && cat /tmp/dhcp.leases 2>/dev/null || cat /var/dhcp.leases 2>/dev/null
      echo "===MODEL===" && cat /tmp/sysinfo/model 2>/dev/null || echo "Motorola MH7601 (OpenWrt)"
    ''';

    final output = await executeSSH(ip, password, script);
    final parts = output.split('===');

    int uptime = 0;
    String model = 'Motorola MH7601';
    List<ConnectedClient> clients = [];

    for (int i = 1; i < parts.length; i += 2) {
      final tag = parts[i].trim();
      final content = i + 1 < parts.length ? parts[i + 1].trim() : '';

      if (tag == 'UPTIME') {
        final secStr = content.split(' ').first;
        uptime = double.tryParse(secStr)?.toInt() ?? 0;
      } else if (tag == 'MODEL') {
        model = content.isNotEmpty ? content : 'Motorola MH7601';
      } else if (tag == 'LEASES') {
        final lines = content.split('\n');
        for (var line in lines) {
          final cols = line.trim().split(RegExp(r'\s+'));
          if (cols.length >= 4) {
            clients.add(ConnectedClient(
              mac: cols[1],
              ip: cols[2],
              name: cols[3] == '*' ? 'Dispositivo' : cols[3],
            ));
          }
        }
      }
    }

    return RouterStatus(ip: ip, model: model, uptimeSeconds: uptime, clients: clients);
  }

  /// Aplica nueva configuración Wi-Fi con 802.11r para Roaming
  static Future<void> setWifiConfig(String ip, String password, {
    required String ssid,
    required String key,
    String encryption = 'psk2',
  }) async {
    final script = '''
      for iface in \$(uci show wireless | grep -E "=wifi-iface" | cut -d'.' -f2 | cut -d'=' -f1); do
        uci set wireless.\${iface}.ssid='$ssid'
        uci set wireless.\${iface}.key='$key'
        uci set wireless.\${iface}.encryption='$encryption'
        uci set wireless.\${iface}.disabled='0'
        uci set wireless.\${iface}.ieee80211r='1'
        uci set wireless.\${iface}.mobility_domain='4f54'
        uci set wireless.\${iface}.ft_over_ds='0'
        uci set wireless.\${iface}.ft_psk_generate_local='1'
      done
      uci commit wireless
      wifi reload 2>/dev/null || wifi 2>/dev/null || true
    ''';
    await executeSSH(ip, password, script);
  }

  /// Configura el nodo Satélite para Mesh Tripack
  static Future<void> configureMeshSatellite({
    required String satIp,
    required String satPassword,
    required String targetIp,
    required String mainGateway,
    required String ssid,
    required String key,
    String encryption = 'psk2',
  }) async {
    final script = '''
      uci set network.lan.ipaddr='$targetIp'
      uci set network.lan.gateway='$mainGateway'
      uci -q delete network.lan.dns
      uci add_list network.lan.dns='$mainGateway'
      uci commit network

      uci set dhcp.lan.ignore='1'
      uci commit dhcp
      /etc/init.d/dnsmasq stop 2>/dev/null
      /etc/init.d/dnsmasq disable 2>/dev/null

      for iface in \$(uci show wireless | grep -E "=wifi-iface" | cut -d'.' -f2 | cut -d'=' -f1); do
        uci set wireless.\${iface}.ssid='$ssid'
        uci set wireless.\${iface}.key='$key'
        uci set wireless.\${iface}.encryption='$encryption'
        uci set wireless.\${iface}.disabled='0'
        uci set wireless.\${iface}.ieee80211r='1'
        uci set wireless.\${iface}.mobility_domain='4f54'
      done
      uci commit wireless

      /etc/init.d/minim stop 2>/dev/null || true
      /etc/init.d/minim disable 2>/dev/null || true

      /etc/init.d/network restart &
    ''';
    await executeSSH(satIp, satPassword, script);
  }
}
