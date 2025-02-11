import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:fl_clash/state.dart';
import 'package:flutter/services.dart';

import '../clash/lib.dart';

/// for android
/// 
/// 调用原生
/// init：初始化ServiceEngine，ClashLib 构造函数中调用，申请通知权限、加载App\VPN\Tile、立即执行Dart入口点
/// destroy：销毁，ClashLib destroy 方法中调用
/// startVpn：启动 VPN，会调用VPNPlugin
/// stopVpn：停止 VPN，会调用VPNPlugin
/// 
/// 与UI线程在同一个进程
class Service {
  static Service? _instance;
  late MethodChannel methodChannel;
  ReceivePort? receiver;

  Service._internal() {
    methodChannel = const MethodChannel("service");
  }

  factory Service() {
    _instance ??= Service._internal();
    return _instance!;
  }

  Future<bool?> init() async {
    return await methodChannel.invokeMethod<bool>("init");
  }

  Future<bool?> destroy() async {
    return await methodChannel.invokeMethod<bool>("destroy");
  }

  Future<bool?> startVpn() async {
    final options = await clashLib?.getAndroidVpnOptions();
    return await methodChannel.invokeMethod<bool>("startVpn", {
      'data': json.encode(options),
    });
  }

  Future<bool?> stopVpn() async {
    return await methodChannel.invokeMethod<bool>("stopVpn");
  }
}

Service? get service => Platform.isAndroid && !globalState.isService ? Service() : null;
