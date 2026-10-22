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
  int txPower; // dBm: 14, 17, 20, 23 (Max)
  bool legacyMode; // Compatibilidad con clientes sin Wi-Fi 6 en 2.4 GHz

  WifiConfigData({
    this.ssid24 = '',
    this.key24 = '',
    this.enc24 = 'psk2',
    this.ssid5 = '',
    this.key5 = '',
    this.enc5 = 'psk2',
    this.separateBands = false,
    this.txPower = 23,
    this.legacyMode = false,
  });
}

class DhcpConfigData {
  int start;
  int limit;
  String dns;
  bool dhcpEnabled;
  String lanIp;
  String netmask;
  String gateway;

  DhcpConfigData({
    this.start = 100,
    this.limit = 150,
    this.dns = '1.1.1.1,1.0.0.1',
    this.dhcpEnabled = true,
    this.lanIp = '192.168.1.1',
    this.netmask = '255.255.255.0',
    this.gateway = '',
  });
}

class SatelliteQuality {
  final bool isOnline;
  final double latencyMs;
  final int signalDbm;
  final int qualityPercent;
  final String linkType; // 'Ethernet (Cable)' o 'Wi-Fi Mesh Backhaul'
  final String statusText;

  SatelliteQuality({
    required this.isOnline,
    required this.latencyMs,
    required this.signalDbm,
    required this.qualityPercent,
    required this.linkType,
    required this.statusText,
  });
}

class WirelessScanResult {
  final String mac;
  final String ssid;
  final int signal;
  final int channel;
  final String encryption;
  final bool isMotorola;

  WirelessScanResult({
    required this.mac,
    required this.ssid,
    required this.signal,
    required this.channel,
    required this.encryption,
    required this.isMotorola,
  });
}

class RouterService {
  /// Desbloquea y arranca LuCI y SSH directamente desde la app mediante POST con contraseña,
  /// preservando las cookies de sesión (sysauth / sysauth_https) y verificando el puerto 22
  static Future<bool> unlockRouter(String ip, String password) async {
    final client = HttpClient()
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;

    try {
      final postData = 'luci_username=root&luci_password=${Uri.encodeQueryComponent(password)}';
      String sessionCookie = '';

      // Paso 1: enable_admin para autenticar y obtener cookie de sesión
      for (final proto in ['https', 'http']) {
        try {
          final uri = Uri.parse('$proto://$ip/cgi-bin/luci/admin/minim/enable_admin');
          final request = await client.postUrl(uri).timeout(const Duration(seconds: 4));
          request.headers.contentType = ContentType('application', 'x-www-form-urlencoded');
          request.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36');
          request.headers.set('Origin', '$proto://$ip');
          request.headers.set('Referer', '$proto://$ip/cgi-bin/luci/admin/minim/enable_admin');
          request.headers.contentLength = utf8.encode(postData).length;
          request.write(postData);
          final response = await request.close();
          
          for (var cookie in response.cookies) {
            sessionCookie += '${cookie.name}=${cookie.value}; ';
          }
          await response.drain();
          if (sessionCookie.isNotEmpty) break;
        } catch (_) {}
      }

      // Paso 2: start_sshd enviando la cookie de sesión autenticada
      for (final proto in ['https', 'http']) {
        try {
          final uri = Uri.parse('$proto://$ip/cgi-bin/luci/admin/minim/start_sshd');

          final reqPost = await client.postUrl(uri).timeout(const Duration(seconds: 4));
          reqPost.headers.contentType = ContentType('application', 'x-www-form-urlencoded');
          reqPost.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36');
          reqPost.headers.set('Origin', '$proto://$ip');
          reqPost.headers.set('Referer', '$proto://$ip/cgi-bin/luci/admin/minim/enable_admin');
          if (sessionCookie.isNotEmpty) {
            reqPost.headers.set(HttpHeaders.cookieHeader, sessionCookie);
          }
          reqPost.headers.contentLength = utf8.encode(postData).length;
          reqPost.write(postData);
          final resPost = await reqPost.close();
          await resPost.drain();

          final reqGet = await client.getUrl(uri).timeout(const Duration(seconds: 4));
          reqGet.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36');
          reqGet.headers.set('Referer', '$proto://$ip/cgi-bin/luci/admin/minim/enable_admin');
          if (sessionCookie.isNotEmpty) {
            reqGet.headers.set(HttpHeaders.cookieHeader, sessionCookie);
          }
          final resGet = await reqGet.close();
          await resGet.drain();
        } catch (_) {}
      }

      // Paso 3: Esperar hasta 8 segundos a que SSH (puerto 22) esté abierto
      for (int i = 0; i < 16; i++) {
        try {
          final s = await Socket.connect(ip, 22, timeout: const Duration(milliseconds: 500));
          s.destroy();
          return true; // SSH listo!
        } catch (_) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
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
      echo "===ARP===" && cat /proc/net/arp 2>/dev/null
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
      } else if (tag == 'ARP') {
        final lines = content.split('\n');
        for (var line in lines) {
          final cols = line.trim().split(RegExp(r'\s+'));
          // IP address HW type Flags HW address Mask Device
          if (cols.length >= 4 && cols[0].contains('.') && cols[3].contains(':') && cols[3] != '00:00:00:00:00:00') {
            final arpIp = cols[0];
            final arpMac = cols[3];
            if (!clients.any((c) => c.ip == arpIp || c.mac.toLowerCase() == arpMac.toLowerCase())) {
              clients.add(ConnectedClient(
                mac: arpMac,
                ip: arpIp,
                name: 'Dispositivo Red',
              ));
            }
          }
        }
      }
    }

    return RouterStatus(ip: ip, model: model, uptimeSeconds: uptime, clients: clients);
  }

  /// Lee la configuración Wi-Fi actual del router, incluyendo potencia y cifrado
  static Future<WifiConfigData> getWifiConfig(String ip, String password) async {
    const script = '''
      echo "===WIRELESS===" && uci show wireless
      echo "===TXPOWER===" && uci -q get wireless.radio0.txpower || echo "23"
      echo "===LEGACY===" && uci -q get wireless.radio0.legacy_mode || echo "0"
    ''';
    final output = await executeSSH(ip, password, script);

    final config = WifiConfigData();
    final parts = output.split('===');

    String wirelessOutput = '';
    for (int i = 1; i < parts.length; i += 2) {
      final tag = parts[i].trim();
      final val = i + 1 < parts.length ? parts[i + 1].trim() : '';
      if (tag == 'WIRELESS') wirelessOutput = val;
      if (tag == 'TXPOWER') config.txPower = int.tryParse(val) ?? 23;
      if (tag == 'LEGACY') config.legacyMode = (val == '1');
    }

    final lines = wirelessOutput.split('\n');
    String? currentIface;
    Map<String, Map<String, String>> ifaces = {};

    for (var line in lines) {
      final trimmed = line.trim();
      if (trimmed.contains('=wifi-iface')) {
        final eqParts = trimmed.split('=');
        currentIface = eqParts[0].replaceAll('wireless.', '');
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

      if (dev.contains('5') || dev.contains('1') || dev.toLowerCase().contains('wlan1') || dev.contains('radio1')) {
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

  /// Aplica cambios Wi-Fi (bandas, cifrado, potencia de transmisión y modo legacy Wi-Fi 6)
  static Future<void> saveWifiConfig(String ip, String password, WifiConfigData cfg) async {
    final commands = <String>[];

    // 1. Ajustar potencia de transmisión (Tx Power) en ambos radios (2.4 y 5 GHz)
    commands.add("uci -q set wireless.radio0.txpower='${cfg.txPower}'");
    commands.add("uci -q set wireless.radio1.txpower='${cfg.txPower}'");

    // 2. Modo de compatibilidad para clientes sin Wi-Fi 6 (Desactivar 802.11ax en 2.4 GHz)
    if (cfg.legacyMode) {
      commands.add("uci -q set wireless.radio0.legacy_mode='1'");
      commands.add("uci -q set wireless.radio0.hwmode='11g'");
      commands.add("uci -q set wireless.radio0.htmode='HT40'");
      commands.add("uci -q set wireless.radio0.ieee80211ax='0'");
    } else {
      commands.add("uci -q set wireless.radio0.legacy_mode='0'");
      commands.add("uci -q delete wireless.radio0.ieee80211ax");
      commands.add("uci -q set wireless.radio0.htmode='HE40'");
    }

    // 3. Configurar interfaces inalámbricas (SSID, Clave, Cifrado, Roaming 802.11r)
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

  /// Mide la calidad de conexión entre el router principal y un satélite
  static Future<SatelliteQuality> checkSatelliteQuality(String mainIp, String mainPassword, String satIp) async {
    final script = '''
      # Ping para latencia
      ping -c 3 -W 1 $satIp 2>/dev/null || echo "PING_FAIL"
      echo "===ARP===" && cat /proc/net/arp | grep -w '$satIp' || true
      echo "===IW===" && (iw dev wlan0 station dump 2>/dev/null; iw dev wlan1 station dump 2>/dev/null) || true
    ''';

    final output = await executeSSH(mainIp, mainPassword, script);
    if (output.contains('100% packet loss') || output.contains('PING_FAIL')) {
      return SatelliteQuality(
        isOnline: false,
        latencyMs: 0,
        signalDbm: -100,
        qualityPercent: 0,
        linkType: 'Desconectado',
        statusText: 'El satélite no responde o está apagado',
      );
    }

    // Extraer latencia de ping
    double latency = 1.5;
    final rttMatch = RegExp(r'avg = ([0-9.]+)|min/avg/max = [0-9.]+/([0-9.]+)/').firstMatch(output);
    if (rttMatch != null) {
      latency = double.tryParse(rttMatch.group(1) ?? rttMatch.group(2) ?? '1.5') ?? 1.5;
    }

    // Buscar señal Wi-Fi
    int signal = -60;
    bool isWireless = false;
    final sigMatch = RegExp(r'signal:\s*(-[0-9]+)\s*dBm').firstMatch(output);
    if (sigMatch != null) {
      signal = int.tryParse(sigMatch.group(1) ?? '-60') ?? -60;
      isWireless = true;
    }

    // Calcular calidad porcentual
    int quality;
    String status;
    String linkType;

    if (!isWireless && latency < 2.5) {
      linkType = 'Ethernet por Cable (1 Gbps)';
      quality = 100;
      status = 'Excelente (Enlace gigabit por cable)';
    } else {
      linkType = 'Wi-Fi Mesh Backhaul';
      if (signal >= -55) {
        quality = 95;
        status = 'Excelente (-${signal.abs()} dBm)';
      } else if (signal >= -68) {
        quality = 80;
        status = 'Buena (-${signal.abs()} dBm)';
      } else if (signal >= -78) {
        quality = 55;
        status = 'Regular (-${signal.abs()} dBm - Recomendado acercar)';
      } else {
        quality = 30;
        status = 'Débil (-${signal.abs()} dBm - Muy lejos)';
      }
    }

    return SatelliteQuality(
      isOnline: true,
      latencyMs: latency,
      signalDbm: signal,
      qualityPercent: quality,
      linkType: linkType,
      statusText: status,
    );
  }

  /// Ajusta la potencia de transmisión (Tx Power) en un satélite específico
  static Future<void> setSatelliteTxPower(String satIp, String satPassword, int txPower) async {
    final script = '''
      uci -q set wireless.radio0.txpower='$txPower'
      uci -q set wireless.radio1.txpower='$txPower'
      uci commit wireless
      wifi reload 2>/dev/null || wifi 2>/dev/null || true
    ''';
    await executeSSH(satIp, satPassword, script);
  }

  /// Lee configuración actual de DHCP, DNS e IP de LAN
  static Future<DhcpConfigData> getDhcpConfig(String ip, String password) async {
    const script = '''
      echo "===START===" && uci -q get dhcp.lan.start || echo "100"
      echo "===LIMIT===" && uci -q get dhcp.lan.limit || echo "150"
      echo "===DNS===" && uci -q get network.lan.dns || echo "1.1.1.1 1.0.0.1"
      echo "===IGNORE===" && uci -q get dhcp.lan.ignore || echo "0"
      echo "===LAN_IP===" && uci -q get network.lan.ipaddr || echo ""
      echo "===NETMASK===" && uci -q get network.lan.netmask || echo "255.255.255.0"
      echo "===GATEWAY===" && uci -q get network.lan.gateway || echo ""
    ''';

    final output = await executeSSH(ip, password, script);
    final parts = output.split('===');
    final data = DhcpConfigData(lanIp: ip);

    for (int i = 1; i < parts.length; i += 2) {
      final tag = parts[i].trim();
      final val = i + 1 < parts.length ? parts[i + 1].trim() : '';

      if (tag == 'START') data.start = int.tryParse(val) ?? 100;
      if (tag == 'LIMIT') data.limit = int.tryParse(val) ?? 150;
      if (tag == 'DNS') data.dns = val.replaceAll(' ', ',');
      if (tag == 'IGNORE') data.dhcpEnabled = (val != '1');
      if (tag == 'LAN_IP' && val.isNotEmpty) data.lanIp = val.split('\n').first.trim();
      if (tag == 'NETMASK' && val.isNotEmpty) data.netmask = val.split('\n').first.trim();
      if (tag == 'GATEWAY' && val.isNotEmpty) data.gateway = val.split('\n').first.trim();
    }

    return data;
  }

  /// Guarda DHCP (activar/apagar, rango) y DNS
  static Future<void> saveDhcpConfig(String ip, String password, DhcpConfigData cfg) async {
    final commands = <String>[];

    if (cfg.dhcpEnabled) {
      commands.add("uci set dhcp.lan.ignore='0'");
      commands.add("uci set dhcp.lan.start='${cfg.start}'");
      commands.add("uci set dhcp.lan.limit='${cfg.limit}'");
      commands.add("uci commit dhcp");
      commands.add("/etc/init.d/dnsmasq enable 2>/dev/null || true");
      commands.add("/etc/init.d/dnsmasq restart");
    } else {
      commands.add("uci set dhcp.lan.ignore='1'");
      commands.add("uci commit dhcp");
      commands.add("/etc/init.d/dnsmasq stop 2>/dev/null || true");
      commands.add("/etc/init.d/dnsmasq disable 2>/dev/null || true");
    }

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

    await executeSSH(ip, password, commands.join('\n'));
  }

  /// Guarda la dirección IP de LAN, máscara de subred y Gateway
  static Future<void> saveLanIpConfig(String ip, String password, {
    required String newIp,
    required String netmask,
    String gateway = '',
    String dns = '',
  }) async {
    final commands = <String>[
      "uci set network.lan.ipaddr='$newIp'",
      "uci set network.lan.netmask='$netmask'",
    ];

    if (gateway.isNotEmpty) {
      commands.add("uci set network.lan.gateway='$gateway'");
    } else {
      commands.add("uci -q delete network.lan.gateway");
    }

    if (dns.isNotEmpty) {
      commands.add("uci -q delete network.lan.dns");
      for (var d in dns.split(',')) {
        final clean = d.trim();
        if (clean.isNotEmpty) {
          commands.add("uci add_list network.lan.dns='$clean'");
        }
      }
    }

    commands.add("uci commit network");
    commands.add("/etc/init.d/network restart &");

    try {
      await executeSSH(ip, password, commands.join('\n'));
    } catch (_) {
      // Al reiniciar la interfaz de red, el SSH corta la conexión, lo cual es esperado
    }
  }

  /// Modo Satélite / Punto de Acceso asistido:
  /// Apaga DHCP y fija IP estática (ej: 192.168.1.2) con Gateway apuntando al Router Principal
  static Future<void> convertToAccessPoint(String ip, String password, {
    required String satIp,
    required String mainGateway,
  }) async {
    final script = '''
      uci set network.lan.ipaddr='$satIp'
      uci set network.lan.netmask='255.255.255.0'
      uci set network.lan.gateway='$mainGateway'
      uci -q delete network.lan.dns
      uci add_list network.lan.dns='$mainGateway'
      uci commit network

      uci set dhcp.lan.ignore='1'
      uci commit dhcp
      /etc/init.d/dnsmasq stop 2>/dev/null || true
      /etc/init.d/dnsmasq disable 2>/dev/null || true

      /etc/init.d/minim stop 2>/dev/null || true
      /etc/init.d/minim disable 2>/dev/null || true

      /etc/init.d/network restart &
    ''';
    try {
      await executeSSH(ip, password, script);
    } catch (_) {}
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
    int txPower = 23,
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

      uci -q set wireless.radio0.txpower='$txPower'
      uci -q set wireless.radio1.txpower='$txPower'

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

      /etc/init.d/minim stop 2>/dev/null || true
      /etc/init.d/minim disable 2>/dev/null || true

      /etc/init.d/network restart &
    ''';
    await executeSSH(satIp, satPassword, script);
  }

  /// Activa Roaming 802.11r (Fast Transition) en el router principal
  static Future<void> enableMeshRoamingOnMain(String ip, String password) async {
    const script = '''
      for iface in \$(uci show wireless | grep -E "=wifi-iface" | cut -d'.' -f2 | cut -d'=' -f1); do
        uci set wireless.\${iface}.ieee80211r='1'
        uci set wireless.\${iface}.mobility_domain='4f54'
        uci set wireless.\${iface}.ft_over_ds='0'
        uci set wireless.\${iface}.ft_psk_generate_local='1'
      done
      uci commit wireless
    ''';
    try {
      await executeSSH(ip, password, script);
    } catch (_) {}
  }

  /// Dispara el emparejamiento WPS Push-Button (PBC) en el router principal
  static Future<bool> triggerWps(String ip, String password) async {
    const script = '''
      (hostapd_cli -i wlan0 wps_pbc 2>/dev/null || true)
      (hostapd_cli -i wlan1 wps_pbc 2>/dev/null || true)
      (hostapd_cli wps_pbc 2>/dev/null || true)
      (ubus call hostapd.wlan0 wps_start 2>/dev/null || true)
      (ubus call hostapd.wlan1 wps_start 2>/dev/null || true)
      (wps_pbc 2>/dev/null || true)
      (wl -i wl0 wps_pbc 2>/dev/null || true)
      (wl -i wl1 wps_pbc 2>/dev/null || true)
      echo "WPS_TRIGGERED"
    ''';
    try {
      await executeSSH(ip, password, script);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Escaneo real del aire (RF Site Survey) para detectar nodos satélites cercanos y su señal
  static Future<List<WirelessScanResult>> scanWirelessAir(String ip, String password) async {
    const script = '''
      (wl -i wl0 scan 2>/dev/null && sleep 2 && wl -i wl0 scanresults 2>/dev/null) || \\
      (wl -i wl1 scan 2>/dev/null && sleep 2 && wl -i wl1 scanresults 2>/dev/null) || \\
      (iwinfo wlan0 scan 2>/dev/null) || \\
      (iwinfo wlan1 scan 2>/dev/null) || \\
      (iw dev wlan0 scan 2>/dev/null) || true
    ''';
    final output = await executeSSH(ip, password, script);
    final results = <WirelessScanResult>[];

    // Intentar formato Broadcom 'wl scanresults'
    if (output.contains('BSSID:') || output.contains('SSID:')) {
      final bssBlocks = output.split(RegExp(r'(?:BSSID:\s*|BSS\s+)', caseSensitive: false));
      for (final block in bssBlocks) {
        if (block.trim().isEmpty) continue;
        final macMatch = RegExp(r'([0-9a-fA-F:]{17})').firstMatch(block);
        final ssidMatch = RegExp(r'(?:SSID|ESSID):\s*["' + "'" + r']?([^"' + "'" + r'\n\r]+)["' + "'" + r']?', caseSensitive: false).firstMatch(block);
        final signalMatch = RegExp(r'(?:RSSI|Signal|signal):\s*(-?\d+)\s*dBm', caseSensitive: false).firstMatch(block);
        final chanMatch = RegExp(r'(?:Channel|channel):\s*(\d+)', caseSensitive: false).firstMatch(block);
        final encMatch = RegExp(r'(?:RSN|WPA|Encryption):\s*([^\n\r]+)', caseSensitive: false).firstMatch(block);

        final mac = macMatch?.group(1)?.toUpperCase() ?? '';
        String ssid = ssidMatch?.group(1)?.trim() ?? 'Red Oculta';
        final signal = int.tryParse(signalMatch?.group(1) ?? '-75') ?? -75;
        final channel = int.tryParse(chanMatch?.group(1) ?? '0') ?? 0;
        final encryption = encMatch?.group(1)?.trim() ?? 'WPA2';

        if (mac.isNotEmpty && mac != '00:00:00:00:00:00') {
          final isMoto = ssid.toLowerCase().contains('moto') ||
                         mac.startsWith('C8:C7:50') ||
                         mac.startsWith('00:0C:E7') ||
                         mac.startsWith('14:59:C0');
          if (ssid == 'Red Oculta' && isMoto) ssid = 'Nodo Motorola Mesh';
          if (!results.any((r) => r.mac == mac)) {
            results.add(WirelessScanResult(
              mac: mac,
              ssid: ssid,
              signal: signal,
              channel: channel,
              encryption: encryption,
              isMotorola: isMoto,
            ));
          }
        }
      }
    }

    if (results.isEmpty) {
      final blocks = output.split(RegExp(r'(?:Cell \d+|BSS [0-9a-fA-F:]{17})'));
      for (final block in blocks) {
        if (block.trim().isEmpty) continue;

        final macMatch = RegExp(r'(?:Address:|BSS)\s*([0-9a-fA-F:]{17})', caseSensitive: false).firstMatch(block);
        final ssidMatch = RegExp(r'(?:ESSID:|SSID:)\s*["' + "'" + r']?([^"' + "'" + r'\n\r]+)["' + "'" + r']?', caseSensitive: false).firstMatch(block);
        final signalMatch = RegExp(r'(?:Signal:|signal:)\s*(-?\d+)\s*dBm', caseSensitive: false).firstMatch(block);
        final chanMatch = RegExp(r'(?:Channel:|channel)\s*(\d+)', caseSensitive: false).firstMatch(block);
        final encMatch = RegExp(r'(?:Encryption:|encryption:)\s*([^\n\r]+)', caseSensitive: false).firstMatch(block);

        final mac = macMatch?.group(1)?.toUpperCase() ?? '';
        String ssid = ssidMatch?.group(1)?.trim() ?? 'Red Oculta';
        final signal = int.tryParse(signalMatch?.group(1) ?? '-80') ?? -80;
        final channel = int.tryParse(chanMatch?.group(1) ?? '0') ?? 0;
        final encryption = encMatch?.group(1)?.trim() ?? 'WPA2';

        if (mac.isNotEmpty) {
          final isMoto = ssid.toLowerCase().contains('moto') ||
                         mac.startsWith('C8:C7:50') ||
                         mac.startsWith('00:0C:E7') ||
                         mac.startsWith('14:59:C0');
          if (ssid == 'Red Oculta' && isMoto) ssid = 'Nodo Motorola Mesh';
          if (!results.any((r) => r.mac == mac)) {
            results.add(WirelessScanResult(
              mac: mac,
              ssid: ssid,
              signal: signal,
              channel: channel,
              encryption: encryption,
              isMotorola: isMoto,
            ));
          }
        }
      }
    }

    results.sort((a, b) => b.signal.compareTo(a.signal));
    return results;
  }

  /// Aprovisionamiento Guiado Directo del Satélite (Universal Bridge y Roaming 802.11r)
  static Future<void> provisionSatelliteDirect({
    required String satIp,
    required String satPassword,
    required String targetIp,
    required String mainGateway,
    required String mainSsid,
    required String mainKey,
    String connectionMode = 'cable',
  }) async {
    // PASO 1: Desbloquear LuCI y arrancar Dropbear SSH en el satélite
    final unlocked = await unlockRouter(satIp, satPassword);
    if (!unlocked) {
      throw Exception('No se pudo desbloquear el satélite en $satIp. Verifica que estés conectado a su red Wi-Fi o cable y que la clave de etiqueta sea correcta.');
    }
    await Future.delayed(const Duration(seconds: 3));

    String script = '';

    if (connectionMode == 'cable') {
      script = '''
        uci -q delete network.wan
        uci -q delete network.wan6
        uci -q set network.lan.ifname='eth0 eth1'
        uci -q set network.lan.type='bridge'

        uci set network.lan.ipaddr='$targetIp'
        uci set network.lan.netmask='255.255.255.0'
        uci set network.lan.gateway='$mainGateway'
        uci -q delete network.lan.dns
        uci add_list network.lan.dns='$mainGateway'
        uci commit network

        uci set dhcp.lan.ignore='1'
        uci commit dhcp
        /etc/init.d/dnsmasq stop 2>/dev/null || true
        /etc/init.d/dnsmasq disable 2>/dev/null || true

        for iface in \$(uci show wireless | grep -E "=wifi-iface" | cut -d'.' -f2 | cut -d'=' -f1); do
          ${mainSsid.isNotEmpty ? "uci set wireless.\${iface}.ssid='$mainSsid'" : ""}
          ${mainKey.isNotEmpty ? "uci set wireless.\${iface}.key='$mainKey'" : ""}
          uci set wireless.\${iface}.encryption='psk2'
          uci set wireless.\${iface}.disabled='0'
          uci set wireless.\${iface}.ieee80211r='1'
          uci set wireless.\${iface}.mobility_domain='4f54'
          uci set wireless.\${iface}.ft_over_ds='0'
          uci set wireless.\${iface}.ft_psk_generate_local='1'
        done
        uci commit wireless

        /etc/init.d/minim stop 2>/dev/null || true
        /etc/init.d/minim disable 2>/dev/null || true
        /etc/init.d/network restart &
        wifi reload 2>/dev/null || wifi 2>/dev/null || true
      ''';
    } else {
      script = '''
        uci set network.lan.ipaddr='$targetIp'
        uci set network.lan.netmask='255.255.255.0'
        uci set network.lan.gateway='$mainGateway'
        uci -q delete network.lan.dns
        uci add_list network.lan.dns='$mainGateway'
        uci commit network

        uci set dhcp.lan.ignore='1'
        uci commit dhcp
        /etc/init.d/dnsmasq stop 2>/dev/null || true
        /etc/init.d/dnsmasq disable 2>/dev/null || true

        for iface in \$(uci show wireless | grep -E "=wifi-iface" | cut -d'.' -f2 | cut -d'=' -f1); do
          ${mainSsid.isNotEmpty ? "uci set wireless.\${iface}.ssid='$mainSsid'" : ""}
          ${mainKey.isNotEmpty ? "uci set wireless.\${iface}.key='$mainKey'" : ""}
          uci set wireless.\${iface}.encryption='psk2'
          uci set wireless.\${iface}.disabled='0'
          uci set wireless.\${iface}.ieee80211r='1'
          uci set wireless.\${iface}.mobility_domain='4f54'
        done

        uci -q delete wireless.mesh_sta
        uci set wireless.mesh_sta=wifi-iface
        uci set wireless.mesh_sta.device='radio1'
        uci set wireless.mesh_sta.mode='sta'
        uci set wireless.mesh_sta.network='lan'
        uci set wireless.mesh_sta.ssid='$mainSsid'
        uci set wireless.mesh_sta.key='$mainKey'
        uci set wireless.mesh_sta.encryption='psk2'
        uci commit wireless

        /etc/init.d/minim stop 2>/dev/null || true
        /etc/init.d/minim disable 2>/dev/null || true
        /etc/init.d/network restart &
        wifi reload 2>/dev/null || wifi 2>/dev/null || true
      ''';
    }

    try {
      await executeSSH(satIp, satPassword, script);
    } catch (_) {
      // Al reiniciar la interfaz de red con la nueva IP, la sesión SSH se cierra normalmente
    }
  }
  }

  /// Restablece el equipo a los valores de fábrica predeterminados (Reset Default)
  static Future<void> factoryReset(String ip, String password) async {
    const script = '''
      (sleep 1; firstboot -y 2>/dev/null || jffs2reset -y 2>/dev/null; reboot -f) &
      echo "FACTORY_RESET_INITIATED"
    ''';
    await executeSSH(ip, password, script);
  }
}
