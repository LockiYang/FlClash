import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:fl_clash/clash/clash.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/services.dart';

/// for android
/// 启动普通Service 或者 VPNService
/// 
/// tun工作流程
/// 1. 创建 TUN 接口：VPNService.establish() 创建TUN接口，detachFd()分离出底层的文件描述符fd
/// 2. 将 fd 传递给 Clash 核心（clashcore.startTun(fd)），让它接管流量
/// 3. 调用 VPNService.protect(fd)，保护 Clash 核心流量不被路由到 TUN 接口，避免死循环
/// 4. Clash 核心根据规则（如代理、直连或屏蔽）处理数据包，然后通过真实的网络接口发送
/// 
/// 
/// methodChannel.invokeMethod：调用原生层 VpnPlugin
/// start：启动FlClashService或FlClashVpnService 取决于：VpnOptions.enable，通过started回调获取fd
/// stop：停止Service，停止前台通知，没调用过；在service.destroy中替代
/// setProtect：
/// startForeground：
/// resolverProcess：
/// 
/// methodChannel.setMethodCallHandler：监听原生层回调
/// started：clashCore.startTun 和 通过ReceivePort监听来自 clashCore 的消息
/// gc：
/// dnsChanged：
/// 
class Vpn {
  static Vpn? _instance;
  late MethodChannel methodChannel;
  ReceivePort? receiver;
  ServiceMessageListener? _serviceMessageHandler;

  Vpn._internal() {
    methodChannel = const MethodChannel("vpn");
    methodChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case "started":
          final fd = call.arguments as int;
          onStarted(fd);
          break;
        case "gc":
          clashCore.requestGc();
        case "dnsChanged":
          final dns = call.arguments as String;
          clashLib?.updateDns(dns);
        default:
          throw MissingPluginException();
      }
    });
  }

  factory Vpn() {
    _instance ??= Vpn._internal();
    return _instance!;
  }

  Future<bool?> startVpn() async {
    final options = clashLib?.getAndroidVpnOptions();
    return await methodChannel.invokeMethod<bool>("start", {
      'data': json.encode(options),
    });
  }

  Future<bool?> stopVpn() async {
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

  Future<bool?> startForeground({
    required String title,
    required String content,
  }) async {
    return await methodChannel.invokeMethod<bool?>("startForeground", {
      'title': title,
      'content': content,
    });
  }

  onStarted(int fd) {
    if (receiver != null) {
      receiver!.close();
      receiver == null;
    }
    receiver = ReceivePort();
    receiver!.listen((message) {
      _handleServiceMessage(message);
    });
    clashLib?.startTun(fd, receiver!.sendPort.nativePort);
  }

  setServiceMessageHandler(ServiceMessageListener serviceMessageListener) {
    _serviceMessageHandler = serviceMessageListener;
  }

  _handleServiceMessage(String message) {
    final m = ServiceMessage.fromJson(json.decode(message));
    switch (m.type) {
      case ServiceMessageType.protect:
        _serviceMessageHandler?.onProtect(Fd.fromJson(m.data));
      case ServiceMessageType.process:
        _serviceMessageHandler?.onProcess(ProcessData.fromJson(m.data));
      case ServiceMessageType.started:
        _serviceMessageHandler?.onStarted(m.data);
      case ServiceMessageType.loaded:
        _serviceMessageHandler?.onLoaded(m.data);
    }
  }
}

final vpn = Platform.isAndroid ? Vpn() : null;
