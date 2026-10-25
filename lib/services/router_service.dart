import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dartssh2/dartssh2.dart';

class RouterStatus {
  final String ip;
  final String model;
  final String hostname;
  final bool minimStopped;
  final int uptimeSeconds;
  final List<ConnectedClient> clients;

  RouterStatus({
    required this.ip,
    required this.model,
    this.hostname = 'Router Principal',
    this.minimStopped = true,
    required this.uptimeSeconds,
    required this.clients,
  });
}

class DhcpLeaseEntry {
  final String hostname;
  final String ip;
  final String mac;
  final int expiresTimestamp;
  final bool isStatic;

  DhcpLeaseEntry({
    required this.hostname,
    required this.ip,
    required this.mac,
    required this.expiresTimestamp,
    this.isStatic = false,
  });

  String get expirationFormatted {
    if (expiresTimestamp <= 0) return 'Concesión Estática / Permanente';
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final diff = expiresTimestamp - now;
    if (diff <= 0) return 'Concesión Expirada';
    final hours = diff ~/ 3600;
    final minutes = (diff % 3600) ~/ 60;
    if (hours > 0) {
      return '$hours h $minutes min restantes';
    } else {
      return '$minutes min restantes';
    }
  }
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
  int channel24;
  int channel5;
  String bssid24;
  String bssid5;

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
    this.channel24 = 6,
    this.channel5 = 36,
    this.bssid24 = '',
    this.bssid5 = '',
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

class CableSatelliteCandidate {
  final String ip;
  final String mac;
  final String hostname;
  final String interface;
  final bool isMotorola;

  CableSatelliteCandidate({
    required this.ip,
    required this.mac,
    required this.hostname,
    required this.interface,
    required this.isMotorola,
  });
}

class DiscoveredSatelliteInfo {
  final String ip;
  final String mac;
  final String hostname;
  final String backhaulBand;

  DiscoveredSatelliteInfo({
    required this.ip,
    required this.mac,
    required this.hostname,
    required this.backhaulBand,
  });
}

class RouterService {
  /// Desbloquea y arranca LuCI y SSH directamente desde la app mediante POST con contraseña,
  /// preservando las cookies de sesión (sysauth / sysauth_https) y verificando el puerto 22
  /// Detecta automáticamente si el satélite responde en 10.10.11.1 (cable WAN conectado) o 192.168.1.1 (Wi-Fi de fábrica)
  static Future<String> detectSatelliteGateway() async {
    for (final testIp in ['10.10.11.1', '192.168.1.1']) {
      try {
        final client = HttpClient()
          ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
        final req = await client.getUrl(Uri.parse('https://$testIp/cgi-bin/luci/admin/minim/enable_admin')).timeout(const Duration(milliseconds: 1500));
        final res = await req.close();
        await res.drain();
        return testIp;
      } catch (_) {
        try {
          final sock = await Socket.connect(testIp, 80, timeout: const Duration(milliseconds: 1200));
          sock.destroy();
          return testIp;
        } catch (_) {}
      }
    }
    return '192.168.1.1';
  }

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

      return false; // Error real si el puerto 22 no abrió
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

  /// Ejecuta comando SSH probando múltiples contraseñas candidatas y desbloqueando SSH si es necesario
  static Future<String> executeSSHMultiAuth(String ip, List<String> candidatePasswords, String command) async {
    final passwords = <String>[];
    for (final p in candidatePasswords) {
      final clean = p.trim();
      if (clean.isNotEmpty && !passwords.contains(clean)) {
        passwords.add(clean);
      }
    }

    Object? lastErr;
    for (final pass in passwords) {
      try {
        return await executeSSH(ip, pass, command);
      } catch (e) {
        lastErr = e;
        try {
          await unlockRouter(ip, pass);
          return await executeSSH(ip, pass, command);
        } catch (e2) {
          lastErr = e2;
        }
      }
    }
    throw Exception('No se pudo autenticar por SSH en $ip (${lastErr ?? "sin respuesta"})');
  }

  /// Lee estado general, modelo, hostname, estado de Minim/Unum y clientes conectados
  static Future<RouterStatus> getStatus(String ip, String password) async {
    const script = '''
      echo "===UPTIME===" && cat /proc/uptime
      echo "===HOSTNAME===" && (cat /proc/sys/kernel/hostname 2>/dev/null || uci -q get system.@system[0].hostname || echo "Router Principal")
      echo "===MINIM===" && (ps | grep -v grep | grep -E "unum|minim" || echo "STOPPED")
      echo "===LEASES===" && cat /tmp/dhcp.leases 2>/dev/null || cat /var/dhcp.leases 2>/dev/null
      echo "===ARP===" && cat /proc/net/arp 2>/dev/null
      echo "===MODEL===" && cat /tmp/sysinfo/model 2>/dev/null || cat /proc/cpuinfo | grep -m1 'model name'
    ''';

    final output = await executeSSH(ip, password, script);
    final parts = output.split('===');

    int uptime = 0;
    String model = 'Motorola MH7601';
    String hostname = 'Router Principal';
    bool minimStopped = true;
    List<ConnectedClient> clients = [];

    for (int i = 1; i < parts.length; i += 2) {
      final tag = parts[i].trim();
      final content = i + 1 < parts.length ? parts[i + 1].trim() : '';

      if (tag == 'UPTIME') {
        final secStr = content.split(' ').first;
        uptime = double.tryParse(secStr)?.toInt() ?? 0;
      } else if (tag == 'HOSTNAME') {
        if (content.isNotEmpty) hostname = content.split('\n').first.trim();
      } else if (tag == 'MINIM') {
        minimStopped = content.contains('STOPPED') || content.isEmpty;
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

    return RouterStatus(
      ip: ip,
      model: model,
      hostname: hostname,
      minimStopped: minimStopped,
      uptimeSeconds: uptime,
      clients: clients,
    );
  }

  /// Cambia el nombre del equipo (Hostname)
  static Future<void> setHostname(String ip, String password, String hostname, {List<String> fallbackPasswords = const []}) async {
    final clean = hostname.replaceAll(RegExp(r'[^a-zA-Z0-9_\-\s]'), '').trim();
    final cleanHost = clean.replaceAll(RegExp(r'\s+'), '-');
    final script = '''
      uci set system.@system[0].hostname='$cleanHost'
      uci commit system
      echo '$cleanHost' > /proc/sys/kernel/hostname
      nvram set router_name='$cleanHost' 2>/dev/null || true
      nvram commit 2>/dev/null || true
      /etc/init.d/system reload 2>/dev/null || true
    ''';
    await executeSSHMultiAuth(ip, [password, ...fallbackPasswords], script);
  }

  /// Detiene y deshabilita permanentemente el agente de la nube unum (Minim/MotoSync)
  static Future<void> disableMinim(String ip, String password) async {
    const script = '''
      /etc/init.d/unum stop 2>/dev/null || true
      /etc/init.d/unum disable 2>/dev/null || true
      /etc/init.d/minim stop 2>/dev/null || true
      /etc/init.d/minim disable 2>/dev/null || true
      /etc/init.d/onboard stop 2>/dev/null || true
      /etc/init.d/onboard disable 2>/dev/null || true
      echo '#!/bin/sh' > /sbin/start_on_board_sta.sh 2>/dev/null || true
      echo 'exit 0' >> /sbin/start_on_board_sta.sh 2>/dev/null || true
      chmod 755 /sbin/start_on_board_sta.sh 2>/dev/null || true
      for p in \$(ps | grep "start_on_board" | grep -v grep | awk '{print \$1}'); do
        kill -9 "\$p" 2>/dev/null || true
      done
      killall -9 unum 2>/dev/null || true
      killall -9 minim 2>/dev/null || true
      killall -9 minimd 2>/dev/null || true
      echo '#!/bin/sh' > /usr/bin/unum 2>/dev/null || true
      echo 'exit 0' >> /usr/bin/unum 2>/dev/null || true
      chmod 755 /usr/bin/unum 2>/dev/null || true
      rm -f /tmp/provision_info.json 2>/dev/null || true

      # Habilitar SSH persistente en arranque
      /usr/sbin/fw_setenv sshd_enable 1 2>/dev/null || true
      /etc/init.d/dropbear restart_admin_enable 2>/dev/null || true

      # Garantizar entrega de DHCP y puente STP rápido (2s) libre de bucles en Router Principal
      uci -q set dhcp.lan.ignore='0'
      uci -q set dhcp.lan.authoritative='1'
      uci -q set dhcp.@dnsmasq[0].authoritative='1'
      uci commit dhcp 2>/dev/null || true
      uci -q set network.lan.stp='1'
      uci -q set network.lan.forward_delay='2'
      uci commit network 2>/dev/null || true
      brctl setbridgeprio br-lan 16384 2>/dev/null || true
      brctl setfd br-lan 2 2>/dev/null || true
      brctl stp br-lan on 2>/dev/null || true
      /etc/init.d/dnsmasq restart 2>/dev/null || true
    ''';
    await executeSSH(ip, password, script);
  }

  /// Obtiene diagnóstico a bajo nivel del router (unum, NVRAM, driver wl, bridge)
  static Future<Map<String, String>> getDiagnosticInfo(String ip, String password) async {
    const script = '''
      echo "===UNUM===" && (ps | grep -v grep | grep -E "unum|minim" || echo "DETENIDO_OK")
      echo "===NVRAM_SSID===" && (nvram get wl0_ssid 2>/dev/null || echo "N/A")
      echo "===NVRAM_SSID5===" && (nvram get wl1_ssid 2>/dev/null || echo "N/A")
      echo "===WL0_SSID===" && (wl -i wl0 ssid 2>/dev/null || echo "N/A")
      echo "===WL1_SSID===" && (wl -i wl1 ssid 2>/dev/null || echo "N/A")
      echo "===UCI_SSID===" && (uci -q get wireless.@wifi-iface[0].ssid || echo "N/A")
      echo "===HOSTNAME===" && (cat /proc/sys/kernel/hostname 2>/dev/null || echo "N/A")
      echo "===INTERFACES===" && (ifconfig -s 2>/dev/null || echo "N/A")
    ''';
    final output = await executeSSH(ip, password, script);
    final parts = output.split('===');
    final map = <String, String>{};
    for (int i = 1; i < parts.length; i += 2) {
      final tag = parts[i].trim();
      final val = i + 1 < parts.length ? parts[i + 1].trim() : '';
      map[tag] = val;
    }
    return map;
  }

  /// Reinicia el router de forma remota
  static Future<void> rebootRouter(String ip, String password, {String? fallbackPassword, List<String> extraPasswords = const []}) async {
    const script = '''
      (sleep 1 && reboot -f) >/dev/null 2>&1 &
      echo "REBOOT_INITIATED"
    ''';

    await executeSSHMultiAuth(ip, [
      password,
      if (fallbackPassword != null) fallbackPassword,
      ...extraPasswords,
    ], script);
  }

  /// Lee la configuración Wi-Fi actual del router, incluyendo potencia, cifrado, canales y BSSID
  static Future<WifiConfigData> getWifiConfig(String ip, String password) async {
    const script = '''
      echo "===SSID0===" && (nvram get wl0_ssid 2>/dev/null || uci -q get wireless.default_wl0.ssid || wl -i wl0 ssid 2>/dev/null | sed 's/Current SSID: //g' | tr -d '"' || echo "")
      echo "===SSID1===" && (nvram get wl1_ssid 2>/dev/null || uci -q get wireless.default_wl1.ssid || wl -i wl1 ssid 2>/dev/null | sed 's/Current SSID: //g' | tr -d '"' || echo "")
      echo "===KEY0===" && (nvram get wl0_wpa_psk || uci -q get wireless.default_wl0.key || echo "")
      echo "===KEY1===" && (nvram get wl1_wpa_psk || uci -q get wireless.default_wl1.key || echo "")
      echo "===TXPOWER===" && uci -q get wireless.radio0.txpower || echo "23"
      echo "===LEGACY===" && uci -q get wireless.radio0.legacy_mode || echo "0"
      echo "===CHAN0===" && (nvram get wl0_channel 2>/dev/null || uci -q get wireless.radio0.channel || echo "0")
      echo "===CHAN1===" && (nvram get wl1_channel 2>/dev/null || uci -q get wireless.radio1.channel || echo "0")
      echo "===BSSID0===" && (wl -i wl0 cur_etheraddr 2>/dev/null || cat /sys/class/net/eth1/address 2>/dev/null || echo "")
      echo "===BSSID1===" && (wl -i wl1 cur_etheraddr 2>/dev/null || cat /sys/class/net/eth2/address 2>/dev/null || echo "")
      echo "===WIRELESS===" && uci show wireless
    ''';
    final output = await executeSSH(ip, password, script);

    final config = WifiConfigData();
    final parts = output.split('===');

    String wirelessOutput = '';
    for (int i = 1; i < parts.length; i += 2) {
      final tag = parts[i].trim();
      final val = i + 1 < parts.length ? parts[i + 1].trim() : '';
      if (tag == 'SSID0' && val.isNotEmpty && !val.toLowerCase().contains('guest')) config.ssid24 = val.replaceAll('Current SSID:', '').replaceAll('"', '').trim();
      if (tag == 'SSID1' && val.isNotEmpty && !val.toLowerCase().contains('guest')) config.ssid5 = val.replaceAll('Current SSID:', '').replaceAll('"', '').trim();
      if (tag == 'KEY0' && val.isNotEmpty) config.key24 = val;
      if (tag == 'KEY1' && val.isNotEmpty) config.key5 = val;
      if (tag == 'WIRELESS') wirelessOutput = val;
      if (tag == 'TXPOWER') config.txPower = int.tryParse(val) ?? 23;
      if (tag == 'LEGACY') config.legacyMode = (val == '1');
      if (tag == 'CHAN0') {
        final match = RegExp(r'(\d+)').firstMatch(val);
        if (match != null) config.channel24 = int.tryParse(match.group(1)!) ?? 6;
      }
      if (tag == 'CHAN1') {
        final match = RegExp(r'(\d+)').firstMatch(val);
        if (match != null) config.channel5 = int.tryParse(match.group(1)!) ?? 36;
      }
      if (tag == 'BSSID0') config.bssid24 = val.trim().toUpperCase();
      if (tag == 'BSSID1') config.bssid5 = val.trim().toUpperCase();
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

    // Identificar 2.4GHz y 5GHz ignorando COMPLETAMENTE interfaces de invitados (guest)
    for (var entry in ifaces.entries) {
      if (entry.key.toLowerCase().contains('guest')) continue;
      final dev = entry.value['device'] ?? '';
      final ssid = entry.value['ssid'] ?? '';
      final key = entry.value['key'] ?? '';
      final enc = entry.value['encryption'] ?? 'psk2';
      if (ssid.toLowerCase().contains('guest')) continue;

      if (dev.contains('5') || dev.contains('1') || dev.toLowerCase().contains('wlan1') || dev.contains('radio1')) {
        final cleanS = ssid.replaceAll('Current SSID:', '').replaceAll('"', '').trim();
        if (config.ssid5.isEmpty) config.ssid5 = cleanS;
        if (config.key5.isEmpty) config.key5 = key;
        config.enc5 = enc;
      } else {
        final cleanS = ssid.replaceAll('Current SSID:', '').replaceAll('"', '').trim();
        if (config.ssid24.isEmpty) config.ssid24 = cleanS;
        if (config.key24.isEmpty) config.key24 = key;
        config.enc24 = enc;
      }
    }

    // Replicar si una banda viene vacía
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
  /// Neutraliza unum/onboard, activa DWDS nativo Broadcom en router principal, persiste en NVRAM y en UCI
  static Future<void> saveWifiConfig(String ip, String password, WifiConfigData cfg) async {
    final commands = <String>[];

    // 1. Apagar y neutralizar permanentemente unum/minim/onboard y habilitar SSH persistente
    commands.add('''
      /etc/init.d/unum stop 2>/dev/null || true
      /etc/init.d/unum disable 2>/dev/null || true
      /etc/init.d/minim stop 2>/dev/null || true
      /etc/init.d/minim disable 2>/dev/null || true
      /etc/init.d/onboard stop 2>/dev/null || true
      /etc/init.d/onboard disable 2>/dev/null || true
      echo '#!/bin/sh' > /sbin/start_on_board_sta.sh 2>/dev/null || true
      echo 'exit 0' >> /sbin/start_on_board_sta.sh 2>/dev/null || true
      chmod 755 /sbin/start_on_board_sta.sh 2>/dev/null || true
      for p in \$(ps | grep "start_on_board" | grep -v grep | awk '{print \$1}'); do
        kill -9 "\$p" 2>/dev/null || true
      done
      killall -9 unum 2>/dev/null || true
      killall -9 minim 2>/dev/null || true
      killall -9 minimd 2>/dev/null || true
      echo '#!/bin/sh' > /usr/bin/unum 2>/dev/null || true
      echo 'exit 0' >> /usr/bin/unum 2>/dev/null || true
      chmod 755 /usr/bin/unum 2>/dev/null || true
      rm -f /tmp/provision_info.json 2>/dev/null || true
      /usr/sbin/fw_setenv sshd_enable 1 2>/dev/null || true
      /etc/init.d/dropbear restart_admin_enable 2>/dev/null || true

      mkdir -p /etc/hotplug.d/net
      cat << 'EOF' > /etc/hotplug.d/net/99-wds-bridge
if echo "\$INTERFACE" | grep -q "^wds"; then
  ifconfig "\$INTERFACE" up 2>/dev/null || true
  brctl addif br-lan "\$INTERFACE" 2>/dev/null || true
  brctl setbridgeprio br-lan 16384 2>/dev/null || true
  brctl setfd br-lan 2 2>/dev/null || true
  brctl stp br-lan on 2>/dev/null || true
fi
EOF
      chmod +x /etc/hotplug.d/net/99-wds-bridge 2>/dev/null || true
      uci -q set network.lan.stp='1'
      uci -q set network.lan.forward_delay='2'
      uci commit network 2>/dev/null || true
    ''');

    final ssid24 = cfg.ssid24.replaceAll('Current SSID:', '').replaceAll('"', '').trim();
    final key24 = cfg.key24.trim();
    final enc24 = cfg.enc24;
    final ssid5 = (cfg.separateBands ? cfg.ssid5 : cfg.ssid24).replaceAll('Current SSID:', '').replaceAll('"', '').trim();
    final key5 = (cfg.separateBands ? cfg.key5 : cfg.key24).trim();
    final enc5 = cfg.separateBands ? cfg.enc5 : cfg.enc24;

    // 2. Persistir en NVRAM (Broadcom wlssk carga de aquí en boot) con DWDS nativo activo
    commands.add('''
      if which nvram >/dev/null 2>&1; then
        ${ssid24.isNotEmpty ? "nvram set wl0_ssid='$ssid24'" : ""}
        ${ssid5.isNotEmpty ? "nvram set wl1_ssid='$ssid5'" : ""}
        ${ssid24.isNotEmpty ? "nvram set wl_ssid='$ssid24'" : ""}
        ${key24.isNotEmpty ? "nvram set wl0_wpa_psk='$key24'" : ""}
        ${key5.isNotEmpty ? "nvram set wl1_wpa_psk='$key5'" : ""}
        ${key24.isNotEmpty ? "nvram set wl_wpa_psk='$key24'" : ""}
        nvram set wl0_akm='psk2'
        nvram set wl1_akm='psk2'
        nvram set wl0_crypto='aes'
        nvram set wl1_crypto='aes'
        nvram set wl0_txpwr='${cfg.txPower}'
        nvram set wl1_txpwr='${cfg.txPower}'
        nvram set wl0_dwds='1'
        nvram set wl1_dwds='1'
        nvram set wl0_lazywds='1'
        nvram set wl1_lazywds='1'
        nvram unset wl0_wds 2>/dev/null || true
        nvram unset wl1_wds 2>/dev/null || true
        nvram commit 2>/dev/null || true
      fi
    ''');

    // 3. Inyección inmediata en caliente a los radios Broadcom wl
    commands.add('''
      ${ssid24.isNotEmpty ? "wl -i wl0 ssid '$ssid24' 2>/dev/null || true" : ""}
      ${ssid5.isNotEmpty ? "wl -i wl1 ssid '$ssid5' 2>/dev/null || true" : ""}
      ${key24.isNotEmpty ? "wl -i wl0 wpa_psk '$key24' 2>/dev/null || true" : ""}
      ${key5.isNotEmpty ? "wl -i wl1 wpa_psk '$key5' 2>/dev/null || true" : ""}
      wl -i wl0 txpwr1 -d ${cfg.txPower} 2>/dev/null || true
      wl -i wl1 txpwr1 -d ${cfg.txPower} 2>/dev/null || true
      wl -i wl0 lazywds 1 2>/dev/null || true
      wl -i wl1 lazywds 1 2>/dev/null || true
    ''');

    // 3.5 Guardar Canales Wi-Fi en UCI y NVRAM (chanspec Broadcom)
    if (cfg.channel24 == 0) {
      commands.add("uci -q set wireless.radio0.channel='auto'");
      commands.add("if which nvram >/dev/null 2>&1; then nvram set wl0_channel='0' 2>/dev/null || true; nvram set wl0_chanspec='0' 2>/dev/null || true; nvram commit 2>/dev/null || true; fi");
    } else {
      commands.add("uci -q set wireless.radio0.channel='${cfg.channel24}'");
      commands.add("if which nvram >/dev/null 2>&1; then nvram set wl0_channel='${cfg.channel24}' 2>/dev/null || true; nvram set wl0_chanspec='${cfg.channel24}' 2>/dev/null || true; nvram commit 2>/dev/null || true; fi");
      commands.add("wl -i wl0 channel ${cfg.channel24} 2>/dev/null || true");
    }

    if (cfg.channel5 == 0) {
      commands.add("uci -q set wireless.radio1.channel='auto'");
      commands.add("if which nvram >/dev/null 2>&1; then nvram set wl1_channel='0' 2>/dev/null || true; nvram set wl1_chanspec='0' 2>/dev/null || true; nvram commit 2>/dev/null || true; fi");
    } else {
      commands.add("uci -q set wireless.radio1.channel='${cfg.channel5}'");
      commands.add("if which nvram >/dev/null 2>&1; then nvram set wl1_channel='${cfg.channel5}' 2>/dev/null || true; nvram set wl1_chanspec='${cfg.channel5}/80' 2>/dev/null || true; nvram commit 2>/dev/null || true; fi");
      commands.add("wl -i wl1 channel ${cfg.channel5} 2>/dev/null || true");
    }

    // 4. Ajustar potencia y modo legacy en OpenWrt UCI
    commands.add("uci -q set wireless.radio0.txpower='${cfg.txPower}'");
    commands.add("uci -q set wireless.radio1.txpower='${cfg.txPower}'");
    commands.add("uci -q delete wireless.radio0.wds");
    commands.add("uci -q delete wireless.radio1.wds");

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

    // 5. Configurar interfaces inalámbricas UCI
    if (cfg.separateBands) {
      commands.add('''
        for iface in \$(uci show wireless | grep -E "=wifi-iface" | cut -d'.' -f2 | cut -d'=' -f1); do
          dev=\$(uci -q get wireless.\${iface}.device)
          if echo "\$dev" | grep -qE "5|wlan1|radio1"; then
            ${ssid5.isNotEmpty ? "uci set wireless.\${iface}.ssid='$ssid5'" : ""}
            ${key5.isNotEmpty ? "uci set wireless.\${iface}.key='$key5'" : ""}
            uci set wireless.\${iface}.encryption='$enc5'
          else
            ${ssid24.isNotEmpty ? "uci set wireless.\${iface}.ssid='$ssid24'" : ""}
            ${key24.isNotEmpty ? "uci set wireless.\${iface}.key='$key24'" : ""}
            uci set wireless.\${iface}.encryption='$enc24'
          fi
          uci set wireless.\${iface}.disabled='0'
          uci -q delete wireless.\${iface}.wds
        done
      ''');
    } else {
      commands.add('''
        for iface in \$(uci show wireless | grep -E "=wifi-iface" | cut -d'.' -f2 | cut -d'=' -f1); do
          ${ssid24.isNotEmpty ? "uci set wireless.\${iface}.ssid='$ssid24'" : ""}
          ${key24.isNotEmpty ? "uci set wireless.\${iface}.key='$key24'" : ""}
          uci set wireless.\${iface}.encryption='$enc24'
          uci set wireless.\${iface}.disabled='0'
          uci -q delete wireless.\${iface}.wds
        done
      ''');
    }

    // 6. Commit, flush de memoria y reinicio limpio automático
    commands.add('uci commit wireless');
    commands.add('sync');
    commands.add('sync');
    commands.add('(sleep 2 && reboot) >/dev/null 2>&1 &');

    try {
      await executeSSH(ip, password, commands.join('\n'));
    } catch (_) {
      // El reinicio cierra la sesión SSH normalmente
    }
  }

  /// Mide la calidad de conexión real entre el router principal y un satélite (Cable vs DWDS 2.4G / 5G + RSSI Broadcom)
  static Future<SatelliteQuality> checkSatelliteQuality(String mainIp, String mainPassword, String satIp) async {
    final script = '''
      ping -c 3 -W 1 $satIp 2>/dev/null || echo "PING_FAIL"
      SAT_MAC=\$(awk '\$1=="$satIp" {print tolower(\$4)}' /proc/net/arp | head -n 1)
      echo "===SAT_MAC===\$SAT_MAC"
      if [ -n "\$SAT_MAC" ]; then
        PORT_NO=\$(brctl showmacs br-lan 2>/dev/null | awk -v m="\$SAT_MAC" 'tolower(\$2)==m {print \$1}' | head -n 1)
        for p in /sys/class/net/br-lan/brif/*; do
          PNUM=\$(printf "%d" \$(cat "\$p/port_no" 2>/dev/null) 2>/dev/null)
          if [ "\$PNUM" = "\$PORT_NO" ]; then
            echo "===BR_PORT===\$(basename \$p)"
          fi
        done
      fi
      echo "===DWDS0==="
      for m in \$(wl -i wl0 dwdslist 2>/dev/null | awk '{print \$2}'); do
        echo "WDS0_MAC:\$m RSSI:\$(wl -i wl0 rssi \$m 2>/dev/null)"
      done
      echo "===DWDS1==="
      for m in \$(wl -i wl1 dwdslist 2>/dev/null | awk '{print \$2}'); do
        echo "WDS1_MAC:\$m RSSI:\$(wl -i wl1 rssi \$m 2>/dev/null)"
      done
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

    double latency = 1.5;
    final rttMatch = RegExp(r'avg = ([0-9.]+)|min/avg/max = [0-9.]+/([0-9.]+)/').firstMatch(output);
    if (rttMatch != null) {
      latency = double.tryParse(rttMatch.group(1) ?? rttMatch.group(2) ?? '1.5') ?? 1.5;
    }

    String brPort = '';
    final portMatch = RegExp(r'===BR_PORT===([^\s\r\n]+)').firstMatch(output);
    if (portMatch != null) {
      brPort = portMatch.group(1)!.trim();
    }

    String satMacPrefix = '';
    final macMatch = RegExp(r'===SAT_MAC===([0-9a-f:]+)').firstMatch(output);
    if (macMatch != null && macMatch.group(1)!.length >= 14) {
      satMacPrefix = macMatch.group(1)!.substring(0, 14).toUpperCase();
    }

    int signal = -55;
    bool isWireless = brPort.startsWith('wds') || brPort.startsWith('wl');
    String wirelessBand = brPort.startsWith('wds1') || brPort.startsWith('wl1') ? '5 GHz' : '2.4 GHz';

    // Extraer RSSI exacto de la lista DWDS de Broadcom
    final wds0Matches = RegExp(r'WDS0_MAC:([0-9A-Fa-f:]+)\s+RSSI:(-?[0-9]+)').allMatches(output);
    for (final m in wds0Matches) {
      final wmac = m.group(1)!.toUpperCase();
      final rssi = int.tryParse(m.group(2) ?? '') ?? -55;
      if (brPort.startsWith('wds0') || (satMacPrefix.isNotEmpty && wmac.startsWith(satMacPrefix))) {
        signal = rssi;
        isWireless = true;
        wirelessBand = '2.4 GHz';
        break;
      }
    }

    final wds1Matches = RegExp(r'WDS1_MAC:([0-9A-Fa-f:]+)\s+RSSI:(-?[0-9]+)').allMatches(output);
    for (final m in wds1Matches) {
      final wmac = m.group(1)!.toUpperCase();
      final rssi = int.tryParse(m.group(2) ?? '') ?? -55;
      if (brPort.startsWith('wds1') || (satMacPrefix.isNotEmpty && wmac.startsWith(satMacPrefix))) {
        signal = rssi;
        isWireless = true;
        wirelessBand = '5 GHz';
        break;
      }
    }

    int quality;
    String status;
    String linkType;

    if (!isWireless) {
      linkType = 'Ethernet por Cable (1 Gbps)';
      quality = 100;
      status = 'Excelente (Enlace gigabit por cable)';
    } else {
      linkType = 'Wi-Fi Mesh DWDS ($wirelessBand)';
      if (signal >= -55) {
        quality = 95;
        status = 'Excelente ($signal dBm • $wirelessBand)';
      } else if (signal >= -68) {
        quality = 80;
        status = 'Buena ($signal dBm • $wirelessBand)';
      } else if (signal >= -78) {
        quality = 55;
        status = 'Regular ($signal dBm • Recomendado acercar)';
      } else {
        quality = 30;
        status = 'Débil ($signal dBm • Muy lejos)';
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

  /// Descubre automáticamente satélites activos en la malla (tanto inalámbricos DWDS como cableados en 192.168.1.2-.5)
  static Future<List<DiscoveredSatelliteInfo>> discoverActiveMeshSatellites(
    String mainIp,
    String mainPassword, {
    List<String> candidatePasswords = const [],
  }) async {
    final prefixParts = mainIp.split('.');
    final subnetPrefix = prefixParts.length == 4 ? '${prefixParts[0]}.${prefixParts[1]}.${prefixParts[2]}' : '192.168.1';
    final scanIps = ['$subnetPrefix.2', '$subnetPrefix.3', '$subnetPrefix.4', '$subnetPrefix.5'];
    final pingCmd = scanIps.where((ip) => ip != mainIp).map((ip) => 'ping -c 1 -W 1 $ip >/dev/null 2>&1 &').join(' ');

    final script = '''
      $pingCmd
      wait
      echo "===ARP==="
      cat /proc/net/arp 2>/dev/null
      echo "===BRMACS==="
      for p in /sys/class/net/br-lan/brif/*; do
        PNUM=\$(printf "%d" \$(cat "\$p/port_no" 2>/dev/null) 2>/dev/null)
        echo "PORTMAP:\$PNUM:\$(basename \$p)"
      done
      brctl showmacs br-lan 2>/dev/null
    ''';

    final out = await executeSSH(mainIp, mainPassword, script);
    final portMap = <String, String>{};
    for (final m in RegExp(r'PORTMAP:(\d+):([^\s\r\n]+)').allMatches(out)) {
      portMap[m.group(1)!] = m.group(2)!;
    }

    final macToPort = <String, String>{};
    for (final line in out.split('\n')) {
      final cols = line.trim().split(RegExp(r'\s+'));
      if (cols.length >= 4 && cols[1].contains(':') && portMap.containsKey(cols[0])) {
        macToPort[cols[1].toUpperCase()] = portMap[cols[0]]!;
      }
    }

    final found = <DiscoveredSatelliteInfo>[];
    final arpSection = out.contains('===ARP===') ? out.split('===ARP===')[1].split('===BRMACS===')[0] : '';
    for (final line in arpSection.split('\n')) {
      final cols = line.trim().split(RegExp(r'\s+'));
      if (cols.length >= 6) {
        final ip = cols[0];
        final flags = cols[2];
        final mac = cols[3].toUpperCase();
        if (ip == mainIp || flags == '0x0' || mac == '00:00:00:00:00:00') continue;

        final isMoto = mac.startsWith('C8:C7:50') || mac.startsWith('00:0C:E7') || mac.startsWith('14:59:C0');
        final isSatPool = scanIps.contains(ip);
        final port = macToPort[mac] ?? '';
        final isWds = port.startsWith('wds');

        if (isMoto || isWds || isSatPool) {
          // Confirmar que la IP responde realmente a ping para descartar entradas ARP antiguas
          final aliveCheck = await executeSSH(mainIp, mainPassword, 'ping -c 1 -W 1 $ip >/dev/null 2>&1 && echo "ALIVE" || echo "DEAD"');
          if (!aliveCheck.contains('ALIVE')) continue;

          String band = port.startsWith('wds1') ? '5 GHz' : '2.4 GHz';
          String host = '';
          try {
            final h = await executeSSHMultiAuth(ip, [mainPassword, ...candidatePasswords], 'cat /proc/sys/kernel/hostname 2>/dev/null');
            if (h.trim().isNotEmpty) host = h.trim().split('\n').first.trim();
          } catch (_) {}

          if (!isMoto && !isWds && host.isEmpty) continue;
          if (host.isEmpty) host = 'Satélite (${ip.split('.').last})';

          if (!found.any((f) => f.ip == ip || (f.mac.isNotEmpty && f.mac == mac))) {
            found.add(DiscoveredSatelliteInfo(
              ip: ip,
              mac: mac,
              hostname: host,
              backhaulBand: band,
            ));
          }
        }
      }
    }
    return found;
  }

  /// Ajusta la potencia de transmisión (Tx Power) en un satélite específico sin derribar el enlace DWDS
  static Future<void> setSatelliteTxPower(String satIp, String satPassword, int txPower, {List<String> fallbackPasswords = const []}) async {
    final script = '''
      if which nvram >/dev/null 2>&1; then
        nvram set wl0_txpwr='$txPower'
        nvram set wl1_txpwr='$txPower'
        nvram commit 2>/dev/null || true
      fi
      wl -i wl0 txpwr1 -d $txPower 2>/dev/null || true
      wl -i wl1 txpwr1 -d $txPower 2>/dev/null || true
      uci -q set wireless.radio0.txpower='$txPower'
      uci -q set wireless.radio1.txpower='$txPower'
      uci commit wireless 2>/dev/null || true
    ''';
    await executeSSHMultiAuth(satIp, [satPassword, ...fallbackPasswords], script);
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
      commands.add("uci -q set dhcp.lan.authoritative='1'");
      commands.add("uci -q set dhcp.@dnsmasq[0].authoritative='1'");
      commands.add("uci set dhcp.lan.start='${cfg.start}'");
      commands.add("uci set dhcp.lan.limit='${cfg.limit}'");
      commands.add("uci commit dhcp");
      commands.add("uci -q set network.lan.stp='1'");
      commands.add("uci -q set network.lan.forward_delay='2'");
      commands.add("uci commit network 2>/dev/null || true");
      commands.add("brctl setbridgeprio br-lan 16384 2>/dev/null || true");
      commands.add("brctl setfd br-lan 2 2>/dev/null || true");
      commands.add("brctl stp br-lan on 2>/dev/null || true");
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

  /// Obtiene la lista completa de concesiones DHCP activas (leases) y tabla ARP
  static Future<List<DhcpLeaseEntry>> getDhcpLeases(String ip, String password) async {
    const script = '''
      echo "===LEASES===" && cat /tmp/dhcp.leases 2>/dev/null || cat /var/dhcp.leases 2>/dev/null
      echo "===ARP===" && cat /proc/net/arp 2>/dev/null
    ''';

    final output = await executeSSH(ip, password, script);
    final parts = output.split('===');
    String leasesRaw = '';
    String arpRaw = '';

    for (int i = 1; i < parts.length; i += 2) {
      final tag = parts[i].trim();
      final body = i + 1 < parts.length ? parts[i + 1] : '';
      if (tag == 'LEASES') leasesRaw = body;
      if (tag == 'ARP') arpRaw = body;
    }

    final Map<String, DhcpLeaseEntry> map = {};

    for (final line in leasesRaw.split('\n')) {
      final tokens = line.trim().split(RegExp(r'\s+'));
      if (tokens.length >= 4) {
        final exp = int.tryParse(tokens[0]) ?? 0;
        final mac = tokens[1].toUpperCase();
        final clientIp = tokens[2];
        final host = (tokens[3] == '*' || tokens[3].isEmpty) ? 'Dispositivo' : tokens[3];
        map[clientIp] = DhcpLeaseEntry(
          hostname: host,
          ip: clientIp,
          mac: mac,
          expiresTimestamp: exp,
        );
      }
    }

    // Complementar con ARP
    for (final line in arpRaw.split('\n')) {
      final tokens = line.trim().split(RegExp(r'\s+'));
      if (tokens.length >= 4 && tokens[0].contains('.') && tokens[3].contains(':') && tokens[3] != '00:00:00:00:00:00') {
        final arpIp = tokens[0];
        final arpMac = tokens[3].toUpperCase();
        if (!map.containsKey(arpIp)) {
          map[arpIp] = DhcpLeaseEntry(
            hostname: 'Dispositivo Red (ARP)',
            ip: arpIp,
            mac: arpMac,
            expiresTimestamp: 0,
            isStatic: true,
          );
        }
      }
    }

    final list = map.values.toList();
    list.sort((a, b) {
      final lastA = int.tryParse(a.ip.split('.').last) ?? 0;
      final lastB = int.tryParse(b.ip.split('.').last) ?? 0;
      return lastA.compareTo(lastB);
    });
    return list;
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
          if (ssid == 'Red Oculta' && isMoto) ssid = 'Red Oculta (Motorola)';
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
          if (ssid == 'Red Oculta' && isMoto) ssid = 'Red Oculta (Motorola)';
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

  /// Detecta satélites conectados por cable al Router Principal (inspeccionando Leases DHCP y ARP)
  static Future<List<CableSatelliteCandidate>> findCableSatellites(String mainIp, String mainPassword) async {
    const script = '''
      echo "===LEASES===" && cat /tmp/dhcp.leases 2>/dev/null || cat /var/dhcp.leases 2>/dev/null
      echo "===ARP===" && cat /proc/net/arp 2>/dev/null
    ''';

    final output = await executeSSH(mainIp, mainPassword, script);
    final results = <CableSatelliteCandidate>[];
    final parts = output.split('===');
    String leasesRaw = '';
    String arpRaw = '';

    for (int i = 1; i < parts.length; i += 2) {
      final tag = parts[i].trim();
      final body = i + 1 < parts.length ? parts[i + 1] : '';
      if (tag == 'LEASES') leasesRaw = body;
      if (tag == 'ARP') arpRaw = body;
    }

    final leaseMap = <String, String>{};
    for (final line in leasesRaw.split('\n')) {
      final tokens = line.trim().split(RegExp(r'\s+'));
      if (tokens.length >= 4) {
        final mac = tokens[1].toUpperCase();
        final ip = tokens[2];
        final host = tokens[3] == '*' ? 'Dispositivo' : tokens[3];
        leaseMap[mac] = host;

        final isMoto = mac.startsWith('C8:C7:50') ||
                       mac.startsWith('00:0C:E7') ||
                       mac.startsWith('14:59:C0') ||
                       host.toLowerCase().contains('moto') ||
                       host.toLowerCase().contains('openwrt');

        if (!results.any((r) => r.mac == mac) && ip != mainIp) {
          results.add(CableSatelliteCandidate(
            ip: ip,
            mac: mac,
            hostname: host,
            interface: 'eth',
            isMotorola: isMoto,
          ));
        }
      }
    }

    for (final line in arpRaw.split('\n')) {
      final tokens = line.trim().split(RegExp(r'\s+'));
      if (tokens.length >= 6) {
        final ip = tokens[0];
        final mac = tokens[3].toUpperCase();
        final iface = tokens[5];

        if (mac.length == 17 && mac != '00:00:00:00:00:00' && ip != mainIp) {
          final isMoto = mac.startsWith('C8:C7:50') ||
                         mac.startsWith('00:0C:E7') ||
                         mac.startsWith('14:59:C0');
          if (!results.any((r) => r.mac == mac)) {
            final host = leaseMap[mac] ?? (isMoto ? 'Satélite Motorola' : 'Equipo LAN');
            results.add(CableSatelliteCandidate(
              ip: ip,
              mac: mac,
              hostname: host,
              interface: iface,
              isMotorola: isMoto,
            ));
          }
        }
      }
    }

    results.sort((a, b) => (b.isMotorola ? 1 : 0).compareTo(a.isMotorola ? 1 : 0));
    return results;
  }

  /// Calcula dinámicamente la siguiente IP disponible en el pool (192.168.1.2, .3, .4, .5)
  static Future<String> getNextAvailableSatelliteIp(String mainIp, String mainPassword, List<String> existingIps) async {
    const candidateIps = ['192.168.1.2', '192.168.1.3', '192.168.1.4', '192.168.1.5'];
    final script = candidateIps.map((ip) => 'ping -c 1 -W 1 $ip >/dev/null 2>&1 && echo "$ip:ALIVE" || echo "$ip:FREE"').join('; ');

    try {
      final output = await executeSSH(mainIp, mainPassword, script);
      for (final candidate in candidateIps) {
        if (existingIps.contains(candidate)) continue;
        if (output.contains('$candidate:FREE')) {
          return candidate;
        }
      }
    } catch (_) {}

    for (final candidate in candidateIps) {
      if (!existingIps.contains(candidate)) return candidate;
    }
    return '192.168.1.2';
  }

  /// Construye el script nativo Broadcom HND DWDS + STP rápido (2s) verificado en hardware real MH7601
  static String _buildNativeBroadcomDwdsSatelliteScript({
    required String cleanHost,
    required String targetIp,
    required String mainGateway,
    required String mainSsid,
    required String mainKey,
    required bool is24G,
    String syncRootPassword = '',
  }) {
    final cleanMainSsid = mainSsid.replaceAll('Current SSID:', '').replaceAll('"', '').trim();
    final cleanMainKey = mainKey.replaceAll('"', '').trim();
    final bhPrimary = is24G ? 'wl0' : 'wl1';
    final bhVif = is24G ? 'wl0.1' : 'wl1.1';
    final otherPrimary = is24G ? 'wl1' : 'wl0';
    final otherVif = is24G ? 'wl1.1' : 'wl0.1';

    return '''
      # 1. Neutralizar permanentemente servicios Minim/OpenWrt que interfieren con DWDS, ebtables o cambian la IP
      for svc in unum minim minim_inits onboard fix_lan_addr dnsmasq dnsmasq-watchdog firewall rep_dhcpc_mon_launcher mesh_watchdog; do
        /etc/init.d/\$svc stop 2>/dev/null || true
        /etc/init.d/\$svc disable 2>/dev/null || true
      done
      rm -f /etc/init.d/mesh_watchdog /etc/rc.d/*mesh_watchdog /usr/bin/start_mesh_backhaul.sh 2>/dev/null || true
      echo '#!/bin/sh' > /usr/bin/unum 2>/dev/null || true
      echo 'exit 0' >> /usr/bin/unum 2>/dev/null || true
      chmod 755 /usr/bin/unum 2>/dev/null || true
      echo '#!/bin/sh' > /sbin/start_on_board_sta.sh 2>/dev/null || true
      echo 'exit 0' >> /sbin/start_on_board_sta.sh 2>/dev/null || true
      chmod 755 /sbin/start_on_board_sta.sh 2>/dev/null || true
      for p in \$(ps | grep -E "start_on_board|mesh_guardian|fix_lan_addr|isolate_guest" | grep -v grep | awk '{print \$1}'); do
        kill -9 "\$p" 2>/dev/null || true
      done
      killall -9 unum minim minimd isolate_guest.sh udhcpc 2>/dev/null || true
      ebtables -F 2>/dev/null || true
      rm -f /tmp/provision_info.json 2>/dev/null || true

      # 2. Sincronizar contraseña root si se indicó
      ${syncRootPassword.isNotEmpty ? "echo -e '$syncRootPassword\\n$syncRootPassword' | passwd root 2>/dev/null || true" : ""}

      # 3. Habilitar Dropbear SSH (con sshd_enable en U-Boot env) y uhttpd permanentemente
      /usr/sbin/fw_setenv sshd_enable 1 2>/dev/null || true
      touch /tmp/sshd_enable
      uci -q set dropbear.@dropbear[0].enable='1'
      uci -q delete dropbear.@dropbear[0].Interface
      uci commit dropbear 2>/dev/null || true
      /etc/init.d/dropbear enable 2>/dev/null || true
      /etc/init.d/dropbear restart_admin_enable 2>/dev/null || true
      /etc/init.d/uhttpd enable 2>/dev/null || true
      /etc/init.d/uhttpd start 2>/dev/null || true

      # 4. Hostname del Satélite
      ${cleanHost.isNotEmpty ? "uci set system.@system[0].hostname='$cleanHost'\necho '$cleanHost' > /proc/sys/kernel/hostname\nuci commit system" : ""}

      # 5. Hotplug para interfaces dinámicas WDS
      mkdir -p /etc/hotplug.d/net
      cat << 'EOFHP' > /etc/hotplug.d/net/99-wds-bridge
if echo "\$INTERFACE" | grep -q "^wds"; then
  ifconfig "\$INTERFACE" up 2>/dev/null || true
  brctl addif br-lan "\$INTERFACE" 2>/dev/null || true
fi
EOFHP
      chmod +x /etc/hotplug.d/net/99-wds-bridge 2>/dev/null || true

      # 6. Configurar DWDS Nativo Broadcom HND (wlssk + wlconf + libnv2hapdcfg) en NVRAM
      if which nvram >/dev/null 2>&1; then
        ${cleanHost.isNotEmpty ? "nvram set router_name='$cleanHost'" : ""}
        nvram set lan_ifname='br-lan'
        nvram set lan_ifnames='eth0 eth1 eth2 eth3 eth4 wl0 wl0.1 wl1 wl1.1'
        nvram set ure_disable='0'
        nvram set router_disable='1'
        nvram set multiap_mode='0'
        nvram unset wl0_wds 2>/dev/null || true
        nvram unset wl1_wds 2>/dev/null || true

        # Radio primario de retorno ($bhPrimary) = Estación DWDS Nativa Broadcom 4-address
        nvram set ${bhPrimary}_bss_enabled='1'
        nvram set ${bhPrimary}_mode='sta'
        nvram set ${bhPrimary}_dwds='1'
        nvram set ${bhPrimary}_lazywds='1'
        nvram set ${bhPrimary}_keep_ap_up='1'
        nvram set ${bhPrimary}_sta_retry_time='5'
        nvram set ${bhPrimary}_ssid='$cleanMainSsid'
        nvram set ${bhPrimary}_akm='psk2'
        nvram set ${bhPrimary}_crypto='aes'
        ${cleanMainKey.isNotEmpty ? "nvram set ${bhPrimary}_wpa_psk='$cleanMainKey'" : ""}
        nvram set ${bhPrimary}_wps_mode='disabled'
        nvram set ${bhPrimary}_vifs='$bhVif'

        # Interfaz virtual local ($bhVif) = Punto de Acceso Wi-Fi para clientes en la misma banda
        nvram set ${bhVif}_bss_enabled='1'
        nvram set ${bhVif}_mode='ap'
        nvram set ${bhVif}_dwds='1'
        nvram set ${bhVif}_ssid='$cleanMainSsid'
        nvram set ${bhVif}_akm='psk2'
        nvram set ${bhVif}_crypto='aes'
        ${cleanMainKey.isNotEmpty ? "nvram set ${bhVif}_wpa_psk='$cleanMainKey'" : ""}
        nvram set ${bhVif}_closed='0'
        nvram set ${bhVif}_ap_isolate='0'
        nvram set ${bhVif}_wps_mode='disabled'

        # Otra banda ($otherPrimary) = Punto de Acceso Wi-Fi completo para clientes
        nvram set ${otherPrimary}_bss_enabled='1'
        nvram set ${otherPrimary}_mode='ap'
        nvram set ${otherPrimary}_dwds='1'
        nvram set ${otherPrimary}_lazywds='1'
        nvram set ${otherPrimary}_vifs=''
        nvram set ${otherVif}_bss_enabled='0'
        nvram set ${otherPrimary}_ssid='$cleanMainSsid'
        nvram set ${otherPrimary}_akm='psk2'
        nvram set ${otherPrimary}_crypto='aes'
        ${cleanMainKey.isNotEmpty ? "nvram set ${otherPrimary}_wpa_psk='$cleanMainKey'" : ""}
        nvram set ${otherPrimary}_closed='0'
        nvram set ${otherPrimary}_ap_isolate='0'

        nvram commit 2>/dev/null || true
      fi

      # 7. Sincronizar UCI wireless para consistencia con diagnósticos
      uci -q delete wireless.mesh_sta
      for iface in \$(uci show wireless | grep -E "=wifi-iface" | cut -d'.' -f2 | cut -d'=' -f1); do
        ${cleanMainSsid.isNotEmpty ? "uci set wireless.\${iface}.ssid='$cleanMainSsid'" : ""}
        ${cleanMainKey.isNotEmpty ? "uci set wireless.\${iface}.key='$cleanMainKey'" : ""}
        uci set wireless.\${iface}.encryption='psk2'
        uci set wireless.\${iface}.mode='ap'
        uci set wireless.\${iface}.network='lan'
        uci set wireless.\${iface}.disabled='0'
        uci -q delete wireless.\${iface}.wds
      done
      uci commit wireless 2>/dev/null || true

      # 8. Modo Puente Universal Capa 2 (eth0 WAN + eth1 LAN en br-lan) con STP rápido (2s) anti-bucles
      uci -q delete network.wan
      uci -q delete network.wan6
      uci -q set network.lan.ifname='eth0 eth1'
      uci -q set network.lan.type='bridge'
      uci -q set network.lan.proto='static'
      ${targetIp.isNotEmpty ? "uci -q set network.lan.ipaddr='$targetIp'" : ""}
      uci -q set network.lan.netmask='255.255.255.0'
      uci -q set network.lan.gateway='$mainGateway'
      uci -q delete network.lan.dns
      uci add_list network.lan.dns='$mainGateway'
      uci -q set network.lan.stp='1'
      uci -q set network.lan.forward_delay='2'
      uci commit network

      uci set dhcp.lan.ignore='1'
      uci commit dhcp 2>/dev/null || true

      # 9. Respaldo wpa_supplicant para recuperación automática del guardián
      cat << 'EOFSUPP' > /etc/mesh_supp.conf
update_config=1
ctrl_interface=/var/run/${bhPrimary}_wpa_supplicant
ctrl_interface_group=0
network={
    ssid="$cleanMainSsid"
    scan_ssid=1
    proto=RSN
    key_mgmt=WPA-PSK
    pairwise=CCMP
    group=CCMP
    psk="$cleanMainKey"
    ieee80211w=0
}
EOFSUPP
      chmod 600 /etc/mesh_supp.conf

      # 10. Guardián Mesh no destructivo (une eth0 WAN + eth1 LAN en br-lan sin alterar SYSPORT, limpia ebtables y reconecta si cae el AP)
      cat << 'EOFGUARD' > /usr/bin/mesh_guardian.sh
#!/bin/sh
touch /tmp/sshd_enable
killall isolate_guest.sh 2>/dev/null || true
ebtables -F 2>/dev/null || true
sleep 20

ebtables -F 2>/dev/null || true
sysctl -w net.ipv4.ip_forward=1 2>/dev/null || true
sysctl -w net.bridge.bridge-nf-call-iptables=0 2>/dev/null || true

brctl setbridgeprio br-lan 32768 2>/dev/null || true
brctl setfd br-lan 2 2>/dev/null || true
brctl stp br-lan on 2>/dev/null || true

FAIL_COUNT=0
while true; do
  ebtables -F 2>/dev/null || true
  for dev in eth0 eth1 $bhPrimary $bhVif $otherPrimary \$(ifconfig -a | grep "^wds" | awk '{print \$1}'); do
    if ifconfig "\$dev" >/dev/null 2>&1; then
      ifconfig "\$dev" up 2>/dev/null || true
      brctl addif br-lan "\$dev" 2>/dev/null || true
    fi
  done
  brctl setpathcost br-lan eth0 4 2>/dev/null || true
  brctl setpathcost br-lan eth1 4 2>/dev/null || true
  brctl setpathcost br-lan $bhPrimary 100 2>/dev/null || true
  brctl setfd br-lan 2 2>/dev/null || true
  brctl stp br-lan on 2>/dev/null || true

  if ping -c 2 -W 2 $mainGateway >/dev/null 2>&1; then
    FAIL_COUNT=0
  else
    FAIL_COUNT=\$((FAIL_COUNT + 1))
    if [ "\$FAIL_COUNT" -ge 2 ]; then
      if ! ps | grep -v grep | grep -q "wpa_supplicant.*$bhPrimary"; then
        wl -i $bhPrimary dwds 1 2>/dev/null || true
        wpa_supplicant -i $bhPrimary -Dnl80211 -c /etc/mesh_supp.conf -b br-lan -B >/dev/null 2>&1
      else
        wpa_cli -p /var/run/${bhPrimary}_wpa_supplicant -i $bhPrimary scan >/dev/null 2>&1 || true
        wpa_cli -p /var/run/${bhPrimary}_wpa_supplicant -i $bhPrimary reconnect >/dev/null 2>&1 || true
      fi
      FAIL_COUNT=0
    fi
  fi
  sleep 15
done
EOFGUARD
      chmod +x /usr/bin/mesh_guardian.sh

      # 11. Servicio de Inicio Mesh Backhaul (con boot() y start())
      cat << 'EOFINIT' > /etc/init.d/mesh_backhaul
#!/bin/sh /etc/rc.common
START=99
boot() {
  start
}
start() {
  touch /tmp/sshd_enable
  killall mesh_guardian.sh 2>/dev/null || true
  /usr/bin/mesh_guardian.sh >/dev/null 2>&1 &
}
stop() {
  killall mesh_guardian.sh 2>/dev/null || true
}
EOFINIT
      chmod +x /etc/init.d/mesh_backhaul 2>/dev/null || true
      /etc/init.d/mesh_backhaul enable 2>/dev/null || true

      sync
      sync
      (sleep 2 && reboot -f) >/dev/null 2>&1 &
    ''';
  }

  /// Sincroniza y aprovisiona un satélite conectado por cable (Plug & Mesh -> Wireless DWDS listo al desconectar)
  static Future<void> provisionSatelliteOverCable({
    required String tempSatIp,
    required String satPassword,
    required String targetIp,
    required String mainGateway,
    required String mainSsid,
    required String mainKey,
    String satName = 'Equipo Satélite',
    int channel5 = 36,
    int channel24 = 6,
    String backhaulBand = '2.4 GHz',
  }) async {
    final unlocked = await unlockRouter(tempSatIp, satPassword);
    if (!unlocked) {
      throw Exception('No se pudo desbloquear el satélite en $tempSatIp. Verifica que la contraseña de etiqueta sea correcta.');
    }
    await Future.delayed(const Duration(seconds: 2));

    final cleanName = satName.replaceAll(RegExp(r'[^a-zA-Z0-9_\-\s]'), '').trim();
    final cleanHost = cleanName.replaceAll(RegExp(r'\s+'), '-');
    final is24G = !backhaulBand.contains('5');

    final script = _buildNativeBroadcomDwdsSatelliteScript(
      cleanHost: cleanHost,
      targetIp: targetIp,
      mainGateway: mainGateway,
      mainSsid: mainSsid,
      mainKey: mainKey,
      is24G: is24G,
      syncRootPassword: mainKey.trim(),
    );

    try {
      await executeSSH(tempSatIp, satPassword, script);
    } catch (_) {}
  }

  /// Prepara el Router Principal para aceptar enlaces inalámbricos DWDS nativos Broadcom de satélites
  static Future<void> prepareMainRouterForWds(String mainIp, String mainPassword) async {
    const script = '''
      # 1. Neutralizar demonio de onboarding que interfiere con interfaces inalámbricas
      /etc/init.d/onboard stop 2>/dev/null || true
      /etc/init.d/onboard disable 2>/dev/null || true
      echo '#!/bin/sh' > /sbin/start_on_board_sta.sh 2>/dev/null || true
      echo 'exit 0' >> /sbin/start_on_board_sta.sh 2>/dev/null || true
      chmod 755 /sbin/start_on_board_sta.sh 2>/dev/null || true
      for p in \$(ps | grep "start_on_board" | grep -v grep | awk '{print \$1}'); do
        kill -9 "\$p" 2>/dev/null || true
      done
      ifconfig wl1.5 down 2>/dev/null || true
      iw dev wl1.5 del 2>/dev/null || true

      # 2. Habilitar SSH persistente en arranque
      /usr/sbin/fw_setenv sshd_enable 1 2>/dev/null || true
      /etc/init.d/dropbear restart_admin_enable 2>/dev/null || true

      # 3. Hotplug para auto-anexar interfaces dinámicas wds0.* / wds1.* al puente br-lan
      mkdir -p /etc/hotplug.d/net
      cat << 'EOF' > /etc/hotplug.d/net/99-wds-bridge
if echo "\$INTERFACE" | grep -q "^wds"; then
  ifconfig "\$INTERFACE" up 2>/dev/null || true
  brctl addif br-lan "\$INTERFACE" 2>/dev/null || true
  brctl setbridgeprio br-lan 16384 2>/dev/null || true
  brctl setfd br-lan 2 2>/dev/null || true
  brctl stp br-lan on 2>/dev/null || true
fi
EOF
      chmod +x /etc/hotplug.d/net/99-wds-bridge 2>/dev/null || true

      # 4. Asegurar DHCP activo y puente raíz STP rápido (prioridad 16384, forward_delay 2s)
      uci -q set dhcp.lan.ignore='0'
      uci -q set dhcp.lan.authoritative='1'
      uci -q set dhcp.@dnsmasq[0].authoritative='1'
      uci commit dhcp 2>/dev/null || true
      uci -q set network.lan.stp='1'
      uci -q set network.lan.forward_delay='2'
      uci commit network 2>/dev/null || true
      brctl setbridgeprio br-lan 16384 2>/dev/null || true
      brctl setfd br-lan 2 2>/dev/null || true
      brctl stp br-lan on 2>/dev/null || true

      for dev in \$(ifconfig -a | grep "^wds" | awk '{print \$1}'); do
        ifconfig "\$dev" up 2>/dev/null || true
        brctl addif br-lan "\$dev" 2>/dev/null || true
      done

      # 5. Activar DWDS nativo Broadcom en ambas bandas (reinicia wlssk solo una vez si estaba apagado)
      DWDS0=\$(wl -i wl0 dwds 2>/dev/null || echo "0")
      DWDS1=\$(wl -i wl1 dwds 2>/dev/null || echo "0")
      nvram set wl0_dwds='1'
      nvram set wl1_dwds='1'
      nvram set wl0_lazywds='1'
      nvram set wl1_lazywds='1'
      nvram commit 2>/dev/null || true
      if [ "\$DWDS0" != "1" ] || [ "\$DWDS1" != "1" ]; then
        (sleep 1 && /bin/nvram restart) >/dev/null 2>&1 &
      fi
    ''';
    try {
      await executeSSH(mainIp, mainPassword, script);
    } catch (_) {}
  }

  /// Aprovisiona el Satélite (conectado en 10.10.11.1 con cable WAN o en 192.168.1.1 por Wi-Fi de fábrica)
  /// utilizando DWDS Nativo Broadcom HND para operación 100% inalámbrica o híbrida por cable
  static Future<String> provisionSatelliteDirect({
    required String satIp,
    required String satPassword,
    required String targetIp,
    required String mainGateway,
    required String mainSsid,
    required String mainKey,
    String satName = 'Equipo Satélite',
    int channel5 = 149,
    int channel24 = 6,
    String mainBssid = '',
    String backhaulBand = '2.4 GHz',
    void Function(String step, double progress)? onProgress,
  }) async {
    String effectiveSatIp = satIp;
    onProgress?.call('Localizando satélite en la red...', 0.15);
    try {
      final detectedIp = await detectSatelliteGateway();
      if (detectedIp.isNotEmpty) {
        effectiveSatIp = detectedIp;
      }
    } catch (_) {}

    onProgress?.call('Conectando a LuCI en $effectiveSatIp y arrancando SSH...', 0.25);
    final unlocked = await unlockRouter(effectiveSatIp, satPassword);
    if (!unlocked) {
      throw Exception('No se pudo desbloquear el satélite en $effectiveSatIp. Verifica que tu teléfono esté conectado al Wi-Fi de ese satélite y que la contraseña de etiqueta sea correcta.');
    }

    onProgress?.call('Verificando acceso SSH en puerto 22...', 0.40);
    await Future.delayed(const Duration(seconds: 2));

    String satMac = '';
    try {
      final macOut = await executeSSH(effectiveSatIp, satPassword, "cat /sys/class/net/eth0/address 2>/dev/null || cat /sys/class/net/br-lan/address 2>/dev/null || wl -i wl0 cur_etheraddr 2>/dev/null || echo ''");
      final match = RegExp(r'([0-9a-fA-F]{2}[:-]){5}([0-9a-fA-F]{2})').firstMatch(macOut);
      if (match != null) satMac = match.group(0)!.toUpperCase();
    } catch (_) {}

    final cleanName = satName.replaceAll(RegExp(r'[^a-zA-Z0-9_\-\s]'), '').trim();
    final cleanHost = cleanName.replaceAll(RegExp(r'\s+'), '-');
    final is24G = !backhaulBand.contains('5');
    final bhDesc = is24G ? '2.4 GHz DWDS (Mayor Alcance)' : '5 GHz DWDS (Alta Velocidad)';

    onProgress?.call('Configurando Broadcom DWDS Nativo ($bhDesc), puente Capa 2 e IP $targetIp...', 0.65);

    final script = _buildNativeBroadcomDwdsSatelliteScript(
      cleanHost: cleanHost,
      targetIp: targetIp,
      mainGateway: mainGateway,
      mainSsid: mainSsid,
      mainKey: mainKey,
      is24G: is24G,
      syncRootPassword: mainKey.trim(),
    );

    try {
      await executeSSH(effectiveSatIp, satPassword, script);
    } catch (e) {
      final err = e.toString().toLowerCase();
      if (!err.contains('closed') && !err.contains('reset') && !err.contains('broken pipe') && !err.contains('socketexception')) {
        throw Exception('Fallo al aplicar la configuración en el satélite: $e');
      }
    }

    onProgress?.call('¡Configuración aplicada! El satélite se está reiniciando...', 1.0);
    return satMac;
  }

  /// Restablece un satélite a sus valores de fábrica de forma remota (incluyendo restauración de modos AP en NVRAM)
  static Future<void> factoryResetSatellite(String ip, String password, {List<String> fallbackPasswords = const []}) async {
    const script = '''
      if which nvram >/dev/null 2>&1; then
        nvram set ure_disable='1'
        nvram set router_disable='0'
        nvram set multiap_mode='0'
        nvram set lan_ifnames='eth1 eth2 eth3 eth4 wl0 wl0.1 wl1 wl1.1'
        nvram set wl0_mode='ap'
        nvram set wl1_mode='ap'
        nvram set wl0_dwds='0'
        nvram set wl1_dwds='0'
        nvram set wl0_vifs=''
        nvram set wl1_vifs=''
        nvram set wl0.1_bss_enabled='0'
        nvram set wl1.1_bss_enabled='0'
        nvram commit 2>/dev/null || true
      fi
      (sleep 1; firstboot -y 2>/dev/null || jffs2reset -y 2>/dev/null; reboot -f) >/dev/null 2>&1 &
      echo "RESET_INITIATED"
    ''';
    try {
      await executeSSHMultiAuth(ip, [password, ...fallbackPasswords], script);
    } catch (_) {}
  }

  /// Restablece el equipo a los valores de fábrica predeterminados (Reset Default)
  static Future<void> factoryReset(String ip, String password) async {
    const script = '''
      if which nvram >/dev/null 2>&1; then
        nvram set ure_disable='1'
        nvram set router_disable='0'
        nvram set multiap_mode='0'
        nvram set wl0_mode='ap'
        nvram set wl1_mode='ap'
        nvram set wl0_dwds='0'
        nvram set wl1_dwds='0'
        nvram set wl0_vifs=''
        nvram set wl1_vifs=''
        nvram set wl0.1_bss_enabled='0'
        nvram set wl1.1_bss_enabled='0'
        nvram commit 2>/dev/null || true
      fi
      (sleep 1; firstboot -y 2>/dev/null || jffs2reset -y 2>/dev/null; reboot -f) >/dev/null 2>&1 &
      echo "FACTORY_RESET_INITIATED"
    ''';
    await executeSSH(ip, password, script);
  }

  /// Agrega una reserva estática DHCP en el Router Principal para un satélite o dispositivo
  static Future<void> addDhcpStaticReservation({
    required String mainIp,
    required String mainPassword,
    required String mac,
    required String targetIp,
    required String hostname,
  }) async {
    final cleanHost = hostname.replaceAll(RegExp(r'\s+'), '-');
    final cleanMac = mac.trim().toLowerCase();
    final script = '''
      for sec in \$(uci show dhcp | grep -E "=host" | cut -d'.' -f2 | cut -d'=' -f1); do
        m=\$(uci -q get dhcp.\${sec}.mac)
        ip=\$(uci -q get dhcp.\${sec}.ip)
        if [ "\$m" = "$cleanMac" ] || [ "\$ip" = "$targetIp" ]; then
          uci -q delete dhcp.\${sec}
        fi
      done
      sec=\$(uci add dhcp host)
      uci set dhcp.\${sec}.name='$cleanHost'
      uci set dhcp.\${sec}.mac='$cleanMac'
      uci set dhcp.\${sec}.ip='$targetIp'
      uci commit dhcp
      sed -i "/$cleanMac/Id" /tmp/dhcp.leases 2>/dev/null || true
      sed -i "/$cleanMac/Id" /var/dhcp.leases 2>/dev/null || true
      /etc/init.d/dnsmasq restart
    ''';
    await executeSSH(mainIp, mainPassword, script);
  }

  /// Asigna una IP estática directamente al satélite y configura la reserva en el router principal
  static Future<void> fixSatelliteIp({
    required String currentSatIp,
    required String satPassword,
    required String mainIp,
    required String mainPassword,
    required String targetIp,
    required String satName,
    String? satMac,
    List<String> extraPasswords = const [],
  }) async {
    String finalMac = satMac?.trim().toUpperCase() ?? '';
    final candidatePasswords = [satPassword, mainPassword, ...extraPasswords];

    if (finalMac.isEmpty) {
      try {
        final macOut = await executeSSHMultiAuth(
          currentSatIp,
          candidatePasswords,
          "cat /sys/class/net/eth0/address 2>/dev/null || cat /sys/class/net/br-lan/address 2>/dev/null || wl -i wl0 cur_etheraddr 2>/dev/null || echo ''",
        );
        final match = RegExp(r'([0-9a-fA-F]{2}[:-]){5}([0-9a-fA-F]{2})').firstMatch(macOut);
        if (match != null) finalMac = match.group(0)!.toUpperCase();
      } catch (_) {}
    }

    if (finalMac.isNotEmpty) {
      try {
        await addDhcpStaticReservation(
          mainIp: mainIp,
          mainPassword: mainPassword,
          mac: finalMac,
          targetIp: targetIp,
          hostname: satName,
        );
      } catch (_) {}
    }

    final script = '''
      uci set network.lan.proto='static'
      uci set network.lan.ipaddr='$targetIp'
      uci set network.lan.netmask='255.255.255.0'
      uci set network.lan.gateway='$mainIp'
      uci -q delete network.lan.dns
      uci add_list network.lan.dns='$mainIp'
      uci commit network
      killall -9 udhcpc 2>/dev/null || true
      sync
      (sleep 1 && reboot -f) >/dev/null 2>&1 &
    ''';

    await executeSSHMultiAuth(currentSatIp, candidatePasswords, script);
  }

  /// Cambia la banda de enlace DWDS Nativo (Backhaul 2.4 GHz vs 5 GHz) en un satélite activo
  static Future<void> switchSatelliteBackhaulBand({
    required String satIp,
    required String satPassword,
    required String mainGateway,
    required String mainSsid,
    required String mainKey,
    required String targetBand, // '2.4 GHz' o '5 GHz'
    List<String> fallbackPasswords = const [],
  }) async {
    final is24 = !targetBand.contains('5');
    final script = _buildNativeBroadcomDwdsSatelliteScript(
      cleanHost: '',
      targetIp: '',
      mainGateway: mainGateway,
      mainSsid: mainSsid,
      mainKey: mainKey,
      is24G: is24,
    );

    await executeSSHMultiAuth(satIp, [satPassword, ...fallbackPasswords, mainKey], script);
  }
}
