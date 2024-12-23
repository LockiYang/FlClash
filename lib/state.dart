import 'dart:async';
import 'dart:io';

import 'package:animations/animations.dart';
import 'package:fl_clash/clash/clash.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/plugins/vpn.dart';
import 'package:fl_clash/widgets/scaffold.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'common/common.dart';
import 'controller.dart';
import 'models/models.dart';

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
  Timer? timer;
  Timer? groupsUpdateTimer;
  var isVpnService = false;
  late PackageInfo packageInfo;
  Function? updateCurrentDelayDebounce;
  PageController? pageController;
  late Measure measure;
  DateTime? startTime;
  final navigatorKey = GlobalKey<NavigatorState>();
  late AppController appController;
  GlobalKey<CommonScaffoldState> homeScaffoldKey = GlobalKey();
  List<Function> updateFunctionLists = [];
  bool lastTunEnable = false;
  int? lastProfileModified;

  bool get isStart => startTime != null && startTime!.isBeforeNow;

  startListenUpdate() {
    if (timer != null && timer!.isActive == true) return;
    timer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      for (final function in updateFunctionLists) {
        function();
      }
    });
  }

  stopListenUpdate() {
    if (timer == null || timer?.isActive == false) return;
    timer?.cancel();
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

  // 更新Clash配置到ClashCore
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
      UpdateConfigParams(
        profileId: config.currentProfileId ?? "",
        config: useClashConfig,
        params: ConfigExtendedParams(
          isPatch: isPatch,
          isCompatible: true,
          selectedMap: config.currentSelectedMap,
          overrideDns: config.overrideDns,
          testUrl: config.appSetting.testUrl,
        ),
      ),
    );
    if (res.isNotEmpty) throw res;
    lastTunEnable = useClashConfig.tun.enable;
    lastProfileModified = await config.getCurrentProfile()?.profileLastModified;
  }

  // 启动ClashCore
  handleStart() async {
    await clashCore.startListener();
    if (globalState.isVpnService) {
      await vpn?.startVpn();
      startListenUpdate();
      return;
    }
    startTime ??= DateTime.now();
    await service?.init();
    startListenUpdate();
  }

  restartCore({
    required AppState appState,
    required ClashConfig clashConfig,
    required Config config,
    bool isPatch = true,
  }) async {
    await clashService?.startCore();
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
  updateStartTime() {
    startTime = clashLib?.getRunTime();
  }

  // 停止ClashCore
  Future handleStop() async {
    startTime = null;
    await clashCore.stopListener();
    clashLib?.stopTun();
    await service?.destroy();
    stopListenUpdate();
  }

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
      clashLib?.setState(
        CoreState(
          enable: config.vpnProps.enable,
          accessControl: config.isAccessControl ? config.accessControl : null,
          ipv6: config.vpnProps.ipv6,
          allowBypass: config.vpnProps.allowBypass,
          systemProxy: config.vpnProps.systemProxy,
          onlyProxy: config.appSetting.onlyProxy,
          bypassDomain: config.networkProps.bypassDomain,
          routeAddress: clashConfig.routeAddress,
          currentProfileName:
              config.currentProfile?.label ?? config.currentProfileId ?? "",
        ),
      );
    }
  }

  // 读取ClashCore的ProxyGroups
  Future<void> updateGroups(AppState appState) async {
    appState.groups = await clashCore.getProxiesGroups();
  }

  // 显示消息提示
  showMessage({
    required String title,
    required InlineSpan message,
    Function()? onTab,
    String? confirmText,
  }) {
    showCommonDialog(
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
                onPressed: onTab ??
                    () {
                      Navigator.of(context).pop();
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
    final onlyProxy = config.appSetting.onlyProxy;
    final traffic = await clashCore.getTraffic(onlyProxy);
    if (Platform.isAndroid && isVpnService == true) {
      vpn?.startForeground(
        title: clashLib?.getCurrentProfileName() ?? "",
        content: "$traffic",
      );
    } else {
      if (appFlowingState != null) {
        appFlowingState.addTraffic(traffic);
        appFlowingState.totalTraffic =
            await clashCore.getTotalTraffic(onlyProxy);
      }
    }
  }

  // 显示底部消息通知
  showSnackBar(
    BuildContext context, {
    required String message,
    SnackBarAction? action,
  }) {
    final width = context.viewWidth;
    EdgeInsets margin;
    if (width < 600) {
      margin = const EdgeInsets.only(
        bottom: 16,
        right: 16,
        left: 16,
      );
    } else {
      margin = EdgeInsets.only(
        bottom: 16,
        left: 16,
        right: width - 316,
      );
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        action: action,
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1500),
        margin: margin,
      ),
    );
  }

  // 执行异步方法并捕获异常，显示错误提示
  Future<T?> safeRun<T>(
    FutureOr<T> Function() futureFunction, {
    String? title,
  }) async {
    try {
      final res = await futureFunction();
      return res;
    } catch (e) {
      showMessage(
        title: title ?? appLocalizations.tip,
        message: TextSpan(
          text: e.toString(),
        ),
      );
      return null;
    }
  }

  // 打开外部链接
  openUrl(String url) {
    showMessage(
      message: TextSpan(text: url),
      title: appLocalizations.externalLink,
      confirmText: appLocalizations.go,
      onTab: () {
        launchUrl(Uri.parse(url));
      },
    );
  }
}

final globalState = GlobalState();
