import 'dart:io';

/// 为 HttpClient 注入针对浙大校内服务的网络层健壮性防御策略。
///
/// 解决两大核心网络痛点：
/// 1. 非校园网 WiFi / 双栈环境超时：默认将建连超时放宽至 12 秒，确保在 IPv6 路由
///    遇到丢包或路由黑洞时，系统 TCP 栈有充足时间完成 SYN 重传与 IPv4 回退，
///    杜绝激进超时（如 5 秒）导致非校园网 WiFi 频繁报错。
/// 2. 代理劫持与 WAF 拦截：强制 *.zju.edu.cn 走 DIRECT 直连，绕过系统代理 / TUN / Fake-IP，
///    防止请求被代理节点转发至境外导致校内 WAF 拦截与 SSL 握手中断。
/// 3. 公共 WiFi / Portal 证书兼容：忽略自签名网关证书告警。
///
/// 【原则】：绝对不禁用 IPv6、不硬编码静态 IPv4 地址，保障纯 IPv6 流量 APN 与双栈 WiFi 的原生自适应。
void applyZjuNetworkDefense(
  HttpClient client, {
  Duration connectionTimeout = const Duration(seconds: 12),
}) {
  // 1. 放宽底层建连超时，给双栈回退留出充裕窗口
  client.connectionTimeout = connectionTimeout;

  // 2. 空闲超时设为 15 秒，避免陈旧连接被路由器 NAT 悄默掐断后引发复用 RST
  client.idleTimeout = const Duration(seconds: 15);

  // 3. 忽略内网 portal 拦截页、自签名证书等非标 TLS 告警
  client.badCertificateCallback = (cert, host, port) => true;

  // 4. 浙大校内域名强制直连，绕过系统代理 / TUN / Fake-IP
  client.findProxy = (uri) {
    final host = uri.host.toLowerCase();
    if (host.endsWith('.zju.edu.cn') || host == 'zju.edu.cn') {
      return 'DIRECT';
    }
    return HttpClient.findProxyFromEnvironment(uri);
  };
}
