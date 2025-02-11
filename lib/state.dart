import 'dart:async';
import 'dart:io';

import 'package:animations/animations.dart';
import 'package:fl_clash/clash/clash.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/widgets/scaffold.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'common/common.dart';
import 'controller.dart';
import 'models/models.dart';

typedef UpdateTasks = List<FutureOr Function()>;

/// 全局单例对象
///
/// timer                 每秒执行一次updateFunctionLists: updateTraffic updateRunTime
/// isVpnService          是否是启动Android VPNService
/// packageInfo           包信息
/// pageController        页面控制器
/// measure               文本缩放比例
/// startTime             ClashCore启动时间
/// navigatorKey          MaterialApp的navigatorKey
/// homeScaffoldKey       主页的Scaffold的key
/// lastTunEnable         上一次Tun是否启用
/// lastProfileModified   上一次修改的Profile的时间戳
class GlobalState {
  bool isService = false;
  Timer? timer;
  Timer? groupsUpdateTimer;
  late PackageInfo packageInfo;
  Function? updateCurrentDelayDebounce;
  PageController? pageController;
  late Measure measure;
  DateTime? startTime;
  UpdateTasks tasks = [];
  final safeMessageOffsetNotifier = ValueNotifier(Offset.zero);
  final navigatorKey = GlobalKey<NavigatorState>();
  late AppController appController;
  GlobalKey<CommonScaffoldState> homeScaffoldKey = GlobalKey();
  bool lastTunEnable = false;
  int? lastProfileModified;

  bool get isStart => startTime != null && startTime!.isBeforeNow;

  startUpdateTasks([UpdateTasks? tasks]) async {
    if (timer != null && timer!.isActive == true) return;
    if (tasks != null) {
      this.tasks = tasks;
    }
    await executorUpdateTask();
    timer = Timer(const Duration(seconds: 1), () async {
      startUpdateTasks();
    });
  }

  executorUpdateTask() async {
    if (timer != null && timer!.isActive == true) return;
    for (final task in tasks) {
      await task();
    }
  }

  stopUpdateTasks() {
    if (timer == null || timer?.isActive == false) return;
    timer?.cancel();
    timer = null;
  }

  Future<void> initCore({
    required AppState appState,
    required ClashConfig clashConfig,
    required Config config,
  }) async {
    await globalState.init(
      appState: appState,
      config: config,
      clashConfig: clashConfig,
    );
    await applyProfile(
      appState: appState,
      config: config,
      clashConfig: clashConfig,
    );
  }

  // 更新配置文件到ClashCore
  // isPatch: true 为增量更新，false 为全量更新
  // 传递currentProfileId，ClashCore会自动寻找对应的profile文件
  Future<void> updateClashConfig({
    required AppState appState,
    required ClashConfig clashConfig,
    required Config config,
    bool isPatch = true,
  }) async {
    await config.currentProfile?.checkAndUpdate();
    final useClashConfig = clashConfig.copyWith();
    if (clashConfig.tun.enable != lastTunEnable &&
        lastTunEnable == false &&
        !Platform.isAndroid) {
      final code = await system.authorizeCore();
      switch (code) {
        case AuthorizeCode.none:
          break;
        case AuthorizeCode.success:
          lastTunEnable = useClashConfig.tun.enable;
          await restartCore(
            appState: appState,
            clashConfig: clashConfig,
            config: config,
          );
          return;
        case AuthorizeCode.error:
          useClashConfig.tun = useClashConfig.tun.copyWith(
            enable: false,
          );
      }
    }
    if (config.appSetting.openLogs) {
      clashCore.startLog();
    } else {
      clashCore.stopLog();
    }
    final res = await clashCore.updateConfig(
      getUpdateConfigParams(config, clashConfig, isPatch),
    );
    if (res.isNotEmpty) throw res;
    lastTunEnable = useClashConfig.tun.enable;
    lastProfileModified = await config.getCurrentProfile()?.profileLastModified;
  }

  // 启动ClashCore
  handleStart([UpdateTasks? tasks]) async {
    await clashCore.startListener();
    await service?.startVpn();
    startUpdateTasks(tasks);
    startTime ??= DateTime.now();
  }

  restartCore({
    required AppState appState,
    required ClashConfig clashConfig,
    required Config config,
    bool isPatch = true,
  }) async {
    await clashService?.reStart();
    await initCore(
      appState: appState,
      clashConfig: clashConfig,
      config: config,
    );

    if (isStart) {
      await handleStart();
    }
  }

  // 读取ClashCore的运行时间
  Future updateStartTime() async {
    startTime = await clashLib?.getRunTime();
  }

  // 停止ClashCore
  Future handleStop() async {
    startTime = null;
    await clashCore.stopListener();
    clashLib?.stopTun();
    await service?.stopVpn();
    stopUpdateTasks();
  }

  // 更新配置文件并更新策略组
  Future applyProfile({
    required AppState appState,
    required Config config,
    required ClashConfig clashConfig,
  }) async {
    clashCore.requestGc();
    await updateClashConfig(
      appState: appState,
      clashConfig: clashConfig,
      config: config,
      isPatch: false,
    );
    await updateGroups(appState);
    await updateProviders(appState);
  }

  // 读取ClashCore的ExternalProviders
  updateProviders(AppState appState) async {
    appState.providers = await clashCore.getExternalProviders();
  }

  CoreState getCoreState(Config config, ClashConfig clashConfig) {
    return CoreState(
      enable: config.vpnProps.enable,
      accessControl: config.isAccessControl ? config.accessControl : null,
      ipv6: config.vpnProps.ipv6,
      allowBypass: config.vpnProps.allowBypass,
      bypassDomain: config.networkProps.bypassDomain,
      systemProxy: config.vpnProps.systemProxy,
      currentProfileName:
          config.currentProfile?.label ?? config.currentProfileId ?? "",
      routeAddress: clashConfig.routeAddress,
    );
  }

  getUpdateConfigParams(Config config, ClashConfig clashConfig, bool isPatch) {
    return UpdateConfigParams(
      profileId: config.currentProfileId ?? "",
      config: clashConfig,
      params: ConfigExtendedParams(
        isPatch: isPatch,
        isCompatible: true,
        selectedMap: config.currentSelectedMap,
        overrideDns: config.overrideDns,
        testUrl: config.appSetting.testUrl,
        onlyStatisticsProxy: config.appSetting.onlyStatisticsProxy,
      ),
    );
  }

  // 初始化ClashCore
  init({
    required AppState appState,
    required Config config,
    required ClashConfig clashConfig,
  }) async {
    appState.isInit = await clashCore.isInit;
    if (!appState.isInit) {
      appState.isInit = await clashCore.init(
        config: config,
        clashConfig: clashConfig,
      );
      // android 非service才会执行
      clashLib?.setState(
        getCoreState(config, clashConfig),
      );
    }
  }

  // 读取ClashCore的ProxyGroups
  Future<void> updateGroups(AppState appState) async {
    appState.groups = await clashCore.getProxiesGroups();
  }

  // 显示消息提示
  Future<bool?> showMessage<bool>({
    required String title,
    required InlineSpan message,
    String? confirmText,
  }) async {
    return await showCommonDialog<bool>(
      child: Builder(
        builder: (context) {
          return AlertDialog(
            title: Text(title),
            content: Container(
              width: 300,
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                child: SelectableText.rich(
                  TextSpan(
                    style: Theme.of(context).textTheme.labelLarge,
                    children: [message],
                  ),
                  style: const TextStyle(
                    overflow: TextOverflow.visible,
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(false);
                },
                child: Text(appLocalizations.cancel),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(true);
                },
                child: Text(confirmText ?? appLocalizations.confirm),
              )
            ],
          );
        },
      ),
    );
  }

  // 切换ClashCore中的Proxy
  changeProxy({
    required Config config,
    required String groupName,
    required String proxyName,
  }) async {
    await clashCore.changeProxy(
      ChangeProxyParams(
        groupName: groupName,
        proxyName: proxyName,
      ),
    );
    if (config.appSetting.closeConnections) {
      clashCore.closeConnections();
    }
  }

  // 显示通用对话框
  Future<T?> showCommonDialog<T>({
    required Widget child,
    bool dismissible = true,
  }) async {
    return await showModal<T>(
      context: navigatorKey.currentState!.context,
      configuration: FadeScaleTransitionConfiguration(
        barrierColor: Colors.black38,
        barrierDismissible: dismissible,
      ),
      builder: (_) => child,
      filter: filter,
    );
  }

  // 读取ClashCore的流量信息
  updateTraffic({
    required Config config,
    AppFlowingState? appFlowingState,
  }) async {
    final traffic = await clashCore.getTraffic();
    if (appFlowingState != null) {
      appFlowingState.addTraffic(traffic);
      appFlowingState.totalTraffic = await clashCore.getTotalTraffic();
    }
  }

  // 执行异步方法并捕获异常，显示错误提示
  Future<T?> safeRun<T>(
    FutureOr<T> Function() futureFunction, {
    String? title,
    bool silence = true,
  }) async {
    try {
      final res = await futureFunction();
      return res;
    } catch (e) {
      if (silence) {
        showNotifier(e.toString());
      } else {
        showMessage(
          title: title ?? appLocalizations.tip,
          message: TextSpan(
            text: e.toString(),
          ),
        );
      }
      return null;
    }
  }

  showNotifier(String text) {
    if (text.isEmpty) {
      return;
    }
    navigatorKey.currentContext?.showNotifier(text);
  }

  // 打开外部链接
  openUrl(String url) async {
    final res = await showMessage(
      message: TextSpan(text: url),
      title: appLocalizations.externalLink,
      confirmText: appLocalizations.go,
    );
    if (res != true) {
      return;
    }
    launchUrl(Uri.parse(url));
  }
}

final globalState = GlobalState();
