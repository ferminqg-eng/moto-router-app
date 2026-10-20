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

class WifiConfigData {
  String ssid24;
  String key24;
  String enc24;
  String ssid5;
  String key5;
  String enc5;
  bool separateBands;

  WifiConfigData({
    this.ssid24 = '',
    this.key24 = '',
    this.enc24 = 'psk2',
    this.ssid5 = '',
    this.key5 = '',
    this.enc5 = 'psk2',
    this.separateBands = false,
  });
}

class DhcpConfigData {
  int start;
  int limit;
  String dns;

  DhcpConfigData({this.start = 100, this.limit = 150, this.dns = '1.1.1.1,1.0.0.1'});
}

class RouterService {
  /// Desbloquea y arranca LuCI y SSH directamente desde la app mediante POST con contraseña
  static Future<bool> unlockRouter(String ip, String password) async {
    final client = HttpClient()
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;

    try {
      final postData = 'luci_username=root&luci_password=${Uri.encodeQueryComponent(password)}';
      final endpoints = [
        'https://$ip/cgi-bin/luci/admin/minim/enable_admin',
        'https://$ip/cgi-bin/luci/admin/minim/start_sshd',
      ];

      for (var url in endpoints) {
        try {
          final request = await client.postUrl(Uri.parse(url)).timeout(const Duration(seconds: 4));
          request.headers.contentType = ContentType('application', 'x-www-form-urlencoded');
          request.headers.contentLength = utf8.encode(postData).length;
          request.write(postData);
          final response = await request.close();
          await response.drain();
        } catch (_) {}
      }
      return true;
    } finally {
      client.close();
    }
  }

  /// Ejecuta comando remoto vía SSH
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

  /// Lee estado general, modelo y dispositivos conectados
  static Future<RouterStatus> getStatus(String ip, String password) async {
    const script = '''
      echo "===UPTIME===" && cat /proc/uptime
      echo "===LEASES===" && cat /tmp/dhcp.leases 2>/dev/null || cat /var/dhcp.leases 2>/dev/null
      echo "===MODEL===" && cat /tmp/sysinfo/model 2>/dev/null || cat /proc/cpuinfo | grep -m1 'model name'
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
        final clean = content.replaceAll(RegExp(r'model name\s*:\s*'), '').trim();
        model = clean.isNotEmpty ? clean : 'Motorola MH7601 (AX1800)';
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

  /// Lee la configuración Wi-Fi actual del router
  static Future<WifiConfigData> getWifiConfig(String ip, String password) async {
    const script = 'uci show wireless';
    final output = await executeSSH(ip, password, script);

    final config = WifiConfigData();
    final lines = output.split('\n');

    String? currentIface;
    Map<String, Map<String, String>> ifaces = {};

    for (var line in lines) {
      final trimmed = line.trim();
      if (trimmed.contains('=wifi-iface')) {
        final parts = trimmed.split('=');
        currentIface = parts[0].replaceAll('wireless.', '');
        ifaces[currentIface] = {};
      } else if (currentIface != null && trimmed.startsWith('wireless.$currentIface.')) {
        final eqIdx = trimmed.indexOf('=');
        if (eqIdx != -1) {
          final key = trimmed.substring('wireless.$currentIface.'.length, eqIdx);
          final val = trimmed.substring(eqIdx + 1).replaceAll("'", '');
          ifaces[currentIface]![key] = val;
        }
      }
    }

    // Identificar 2.4GHz y 5GHz
    for (var entry in ifaces.values) {
      final dev = entry['device'] ?? '';
      final ssid = entry['ssid'] ?? '';
      final key = entry['key'] ?? '';
      final enc = entry['encryption'] ?? 'psk2';

      if (dev.contains('5') || dev.contains('1') || dev.toLowerCase().contains('wlan1')) {
        config.ssid5 = ssid;
        config.key5 = key;
        config.enc5 = enc;
      } else {
        config.ssid24 = ssid;
        config.key24 = key;
        config.enc24 = enc;
      }
    }

    // Si solo hay una configurada, replicarla
    if (config.ssid5.isEmpty && config.ssid24.isNotEmpty) {
      config.ssid5 = config.ssid24;
      config.key5 = config.key24;
      config.enc5 = config.enc24;
    }
    if (config.ssid24.isEmpty && config.ssid5.isNotEmpty) {
      config.ssid24 = config.ssid5;
      config.key24 = config.key5;
      config.enc24 = config.enc5;
    }

    config.separateBands = (config.ssid24 != config.ssid5 && config.ssid5.isNotEmpty);
    return config;
  }

  /// Aplica cambios Wi-Fi (bandas separadas o unificadas) con 802.11r Roaming
  static Future<void> saveWifiConfig(String ip, String password, WifiConfigData cfg) async {
    final commands = <String>[];

    if (cfg.separateBands) {
      // 2.4 GHz y 5 GHz independientes
      commands.add('''
        for iface in \$(uci show wireless | grep -E "=wifi-iface" | cut -d'.' -f2 | cut -d'=' -f1); do
          dev=\$(uci -q get wireless.\${iface}.device)
          if echo "\$dev" | grep -qE "5|wlan1|radio1"; then
            uci set wireless.\${iface}.ssid='${cfg.ssid5}'
            uci set wireless.\${iface}.key='${cfg.key5}'
            uci set wireless.\${iface}.encryption='${cfg.enc5}'
          else
            uci set wireless.\${iface}.ssid='${cfg.ssid24}'
            uci set wireless.\${iface}.key='${cfg.key24}'
            uci set wireless.\${iface}.encryption='${cfg.enc24}'
          fi
          uci set wireless.\${iface}.disabled='0'
          uci set wireless.\${iface}.ieee80211r='1'
          uci set wireless.\${iface}.mobility_domain='4f54'
        done
      ''');
    } else {
      // Banda Unificada (Mesh Roaming)
      commands.add('''
        for iface in \$(uci show wireless | grep -E "=wifi-iface" | cut -d'.' -f2 | cut -d'=' -f1); do
          uci set wireless.\${iface}.ssid='${cfg.ssid24}'
          uci set wireless.\${iface}.key='${cfg.key24}'
          uci set wireless.\${iface}.encryption='${cfg.enc24}'
          uci set wireless.\${iface}.disabled='0'
          uci set wireless.\${iface}.ieee80211r='1'
          uci set wireless.\${iface}.mobility_domain='4f54'
        done
      ''');
    }

    commands.add('uci commit wireless');
    commands.add('wifi reload 2>/dev/null || wifi 2>/dev/null || true');

    await executeSSH(ip, password, commands.join('\n'));
  }

  /// Lee configuración actual de DHCP y DNS
  static Future<DhcpConfigData> getDhcpConfig(String ip, String password) async {
    const script = '''
      echo "===START===" && uci -q get dhcp.lan.start || echo "100"
      echo "===LIMIT===" && uci -q get dhcp.lan.limit || echo "150"
      echo "===DNS===" && uci -q get network.lan.dns || echo "1.1.1.1 1.0.0.1"
    ''';

    final output = await executeSSH(ip, password, script);
    final parts = output.split('===');
    final data = DhcpConfigData();

    for (int i = 1; i < parts.length; i += 2) {
      final tag = parts[i].trim();
      final val = i + 1 < parts.length ? parts[i + 1].trim() : '';

      if (tag == 'START') data.start = int.tryParse(val) ?? 100;
      if (tag == 'LIMIT') data.limit = int.tryParse(val) ?? 150;
      if (tag == 'DNS') data.dns = val.replaceAll(' ', ',');
    }

    return data;
  }

  /// Guarda DHCP y DNS
  static Future<void> saveDhcpConfig(String ip, String password, DhcpConfigData cfg) async {
    final commands = <String>[
      "uci set dhcp.lan.start='${cfg.start}'",
      "uci set dhcp.lan.limit='${cfg.limit}'",
      "uci commit dhcp",
    ];

    if (cfg.dns.isNotEmpty) {
      commands.add("uci -q delete network.lan.dns");
      for (var d in cfg.dns.split(',')) {
        final clean = d.trim();
        if (clean.isNotEmpty) {
          commands.add("uci add_list network.lan.dns='$clean'");
        }
      }
      commands.add("uci commit network");
    }

    commands.add("/etc/init.d/dnsmasq restart");
    await executeSSH(ip, password, commands.join('\n'));
  }

  /// Agrega regla de Port Forwarding
  static Future<void> addPortForward(String ip, String password, {
    required String name,
    required String proto,
    required String extPort,
    required String intIp,
    required String intPort,
  }) async {
    final script = '''
      uci add firewall redirect
      uci set firewall.@redirect[-1].name='$name'
      uci set firewall.@redirect[-1].src='wan'
      uci set firewall.@redirect[-1].proto='$proto'
      uci set firewall.@redirect[-1].src_dport='$extPort'
      uci set firewall.@redirect[-1].dest_ip='$intIp'
      uci set firewall.@redirect[-1].dest_port='$intPort'
      uci set firewall.@redirect[-1].target='DNAT'
      uci commit firewall
      /etc/init.d/firewall restart
    ''';
    await executeSSH(ip, password, script);
  }

  /// Configura satélite Mesh
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
