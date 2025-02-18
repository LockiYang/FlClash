import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract mixin class TileListener {
  void onStart() {}

  void onStop() {}

  void onDetached(){

  }
}

/// for android
/// 磁贴，通知栏快捷菜单插件
/// 
/// 处理原生调用
/// start：触发监听器 onStart 回调
/// stop：触发监听器 onStop 回调
/// detached：触发监听器 onDetached 回调
class Tile {

  final MethodChannel _channel = const MethodChannel('tile');

  Tile._() {
    _channel.setMethodCallHandler(_methodCallHandler);
  }

  static final Tile instance = Tile._();

  final ObserverList<TileListener> _listeners = ObserverList<TileListener>();

  Future<void> _methodCallHandler(MethodCall call) async {
    for (final TileListener listener in _listeners) {
      switch (call.method) {
        case "start":
          listener.onStart();
          break;
        case "stop":
          listener.onStop();
          break;
        case "detached":
          listener.onDetached();
          break;
      }
    }
  }

  bool get hasListeners {
    return _listeners.isNotEmpty;
  }

  void addListener(TileListener listener) {
    _listeners.add(listener);
  }

  void removeListener(TileListener listener) {
    _listeners.remove(listener);
  }
}

final tile =  Platform.isAndroid ? Tile.instance : null;
