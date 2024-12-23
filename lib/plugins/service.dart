import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/services.dart';

/// for android
/// 创建和销毁ServiceEngine，会立即执行 vpnService 的Dart入口点
/// 在Android的VPNService进程中运行，是否单独进程，前台服务和后台服务？
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
}

final service =
    Platform.isAndroid ? Service() : null;
