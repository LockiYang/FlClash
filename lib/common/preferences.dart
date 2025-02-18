import 'dart:async';
import 'dart:convert';

import 'package:fl_clash/models/models.dart';
import 'package:shared_preferences/shared_preferences.dart';


import 'constant.dart';

// 用于存储应用的配置文件和Clash的配置文件
class Preferences {
  static Preferences? _instance;
  Completer<SharedPreferences?> sharedPreferencesCompleter = Completer();

  Future<bool> get isInit async => await sharedPreferencesCompleter.future != null;

  Preferences._internal() {
    SharedPreferences.getInstance().then((value) => sharedPreferencesCompleter.complete(value))
        .onError((_,__)=>sharedPreferencesCompleter.complete(null));
  }

  factory Preferences() {
    _instance ??= Preferences._internal();
    return _instance!;
  }


  Future<ClashConfig?> getClashConfig() async {
    final preferences = await sharedPreferencesCompleter.future;
    final clashConfigString = preferences?.getString(clashConfigKey);
    if (clashConfigString == null) return null;
    final clashConfigMap = json.decode(clashConfigString);
    return ClashConfig.fromJson(clashConfigMap);
  }

  Future<bool> saveClashConfig(ClashConfig clashConfig) async {
    final preferences = await sharedPreferencesCompleter.future;
     preferences?.setString(
      clashConfigKey,
      json.encode(clashConfig),
    );
     return true;
  }

  Future<Config?> getConfig() async {
    final preferences = await sharedPreferencesCompleter.future;
    final configString = preferences?.getString(configKey);
    if (configString == null) return null;
    final configMap = json.decode(configString);
    return Config.fromJson(configMap);
  }

  Future<bool> saveConfig(Config config) async {
    final preferences = await sharedPreferencesCompleter.future;
    return await preferences?.setString(
      configKey,
      json.encode(config),
    ) ?? false;
  }

  clearPreferences() async {
    final sharedPreferencesIns = await sharedPreferencesCompleter.future;
    sharedPreferencesIns?.clear();
  }
}

final preferences = Preferences();
