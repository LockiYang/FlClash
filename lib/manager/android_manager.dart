import 'package:fl_clash/clash/clash.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// for android
/// SystemUiMode.edgeToEdge：使得界面布局延伸到系统状态栏和导航栏的位置，让应用内容显示在整个屏幕上。
/// 当config.appSetting.hidden为true时，app?.updateExcludeFromRecents(hidden)会将应用排除在最近任务列表中。
class AndroidManager extends StatefulWidget {
  final Widget child;

  const AndroidManager({
    super.key,
    required this.child,
  });

  @override
  State<AndroidManager> createState() => _AndroidContainerState();
}

class _AndroidContainerState extends State<AndroidManager> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  Widget _updateCoreState(Widget child) {
    return Selector2<Config, ClashConfig, CoreState>(
      selector: (_, config, clashConfig) => CoreState(
        enable: config.vpnProps.enable,
        accessControl: config.isAccessControl ? config.accessControl : null,
        ipv6: config.vpnProps.ipv6,
        allowBypass: config.vpnProps.allowBypass,
        bypassDomain: config.networkProps.bypassDomain,
        systemProxy: config.vpnProps.systemProxy,
        onlyProxy: config.appSetting.onlyProxy,
        currentProfileName:
            config.currentProfile?.label ?? config.currentProfileId ?? "",
        routeAddress: clashConfig.routeAddress,
      ),
      builder: (__, state, child) {
        clashLib?.setState(state);
        return child!;
      },
      child: child,
    );
  }

  Widget _excludeContainer(Widget child) {
    return Selector<Config, bool>(
      selector: (_, config) => config.appSetting.hidden,
      builder: (_, hidden, child) {
        app?.updateExcludeFromRecents(hidden);
        return child!;
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return _updateCoreState(
      _excludeContainer(
        widget.child,
      ),
    );
  }
}
