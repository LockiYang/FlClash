import 'dart:async';
import 'dart:io';

import 'package:launch_at_startup/launch_at_startup.dart';

import 'constant.dart';
import 'system.dart';

/// for desktop
/// 自动启动和管理员自动启动
class AutoLaunch {
  static AutoLaunch? _instance;

  AutoLaunch._internal() {
    launchAtStartup.setup(
      appName: appName,
      appPath: Platform.resolvedExecutable,
    );
  }

  factory AutoLaunch() {
    _instance ??= AutoLaunch._internal();
    return _instance!;
  }

  Future<bool> get isEnable async {
    return await launchAtStartup.isEnabled();
  }

  Future<bool> enable() async {
    return await launchAtStartup.enable();
  }

  Future<bool> disable() async {
    return await launchAtStartup.disable();
  }

  updateStatus(bool isAutoLaunch) async {
    if (await isEnable == isAutoLaunch) return;
    if (isAutoLaunch == true) {
      enable();
    } else {
      disable();
    }
  }
}

final autoLaunch = system.isDesktop ? AutoLaunch() : null;
