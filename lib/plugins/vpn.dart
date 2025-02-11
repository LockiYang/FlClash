import 'dart:async';
import 'dart:convert';

import 'package:fl_clash/clash/clash.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract mixin class VpnListener {
  void onStarted(int fd) {}

  void onDnsChanged(String dns) {}
}

/// for android
///
/// 准备工作
/// 1. App内启动时（非qucikstart），会初始化AppController（initGeo、init(homeDirPath)、clashLib?.setState）
/// 2. App启动时ClashLib构造函数调用 service.init
/// 3. 初始化ServiceEngine，执行_service入口点，建立和ClashCore的通信
///
/// startVPN按钮点击时，调用service.startVpn
/// 1. requestVpnPermission 
/// 2. 调用 VpnService.start，VPNService.establish() 创建TUN接口，detachFd()分离出底层的文件描述符fd
/// 2. 回调 Dart层 started，将 fd 传递给 Clash 核心（clashcore.startTun(fd)），让它接管流量
/// 3. 调用 VPNService.protect(fd)，保护 Clash 核心流量不被路由到 TUN 接口，避免死循环
/// 4. Clash 核心根据规则（如代理、直连或屏蔽）处理数据包，然后通过真实的网络接口发送
///
///
/// 处理原生调用
/// gc：触发ClashLib.requestGc
/// getStartForegroundParams：获取流量和当前配置文件名作为前台通知参数
/// started：clashCore.startTun 和 通过ReceivePort监听来自 ClashCore 的消息
/// dnsChanged：
///
/// 调用原生
/// start：启动VPNService，通过started回调获取fd
/// stop：停止VPNService，停止前台通知，没调用过；在service.destroy中替代
/// setProtect：VPNService.protect(fd)，保护 Clash 核心流量不被路由到 TUN 接口
/// resolverProcess：解析网络连接的进程信息，并返回 发起该连接的应用包名。
///
/// receiver：监听来自 Clash 核心的消息
/// onProtect：保护 Clash 核心流量不被路由到 TUN 接口
/// onProcess：用于解析 TUN 流量的进程信息（如来源 IP、端口、协议等）
/// onStarted：在 TUN 接口启动成功后触发，表示 Clash 的 TUN 模式正式运行
/// onLoaded：在 Clash 核心加载成功后触发，表示 Clash 核心已经加载完成
class Vpn {
  static Vpn? _instance;
  late MethodChannel methodChannel;
  FutureOr<String> Function()? handleGetStartForegroundParams;

  Vpn._internal() {
    methodChannel = const MethodChannel("vpn");
    methodChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case "gc":
          clashCore.requestGc();
        case "getStartForegroundParams":
          if (handleGetStartForegroundParams != null) {
            return await handleGetStartForegroundParams!();
          }
          return "";
        default:
          for (final VpnListener listener in _listeners) {
            switch (call.method) {
              case "started":
                final fd = call.arguments as int;
                listener.onStarted(fd);
                break;
              case "dnsChanged":
                final dns = call.arguments as String;
                listener.onDnsChanged(dns);
            }
          }
      }
    });
  }

  factory Vpn() {
    _instance ??= Vpn._internal();
    return _instance!;
  }

  final ObserverList<VpnListener> _listeners = ObserverList<VpnListener>();

  Future<bool?> start(AndroidVpnOptions options) async {
    return await methodChannel.invokeMethod<bool>("start", {
      'data': json.encode(options),
    });
  }

  Future<bool?> stop() async {
    return await methodChannel.invokeMethod<bool>("stop");
  }

  Future<bool?> setProtect(int fd) async {
    return await methodChannel.invokeMethod<bool?>("setProtect", {'fd': fd});
  }

  Future<String?> resolverProcess(ProcessData process) async {
    return await methodChannel.invokeMethod<String>("resolverProcess", {
      "data": json.encode(process),
    });
  }

  void addListener(VpnListener listener) {
    _listeners.add(listener);
  }

  void removeListener(VpnListener listener) {
    _listeners.remove(listener);
  }
}

Vpn? get vpn => globalState.isService ? Vpn() : null;
