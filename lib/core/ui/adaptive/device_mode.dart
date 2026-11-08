import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum DeviceMode { tv, touch }

const bool kTvBuild = bool.fromEnvironment('TV');

final deviceModeProvider = Provider<DeviceMode>((ref) => DeviceMode.touch);

class DeviceModeDetector {
  DeviceModeDetector._();

  static const Set<String> _tvFeatures = <String>{
    'android.software.leanback',
    'android.software.leanback_only',
    'android.hardware.type.television',
    'amazon.hardware.fire_tv',
  };

  static const String _touchFeature = 'android.hardware.touchscreen';

  /// O `--dart-define=TV=true` declara a intenção; o runtime confirma.
  /// Recurso de TV no sistema decide sozinho. Sem ele, o build de TV só vira
  /// TV se a tela for larga (shortestSide > 600) ou se não houver touchscreen.
  static Future<DeviceMode> detect() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return DeviceMode.touch;
    }
    var hasTvFeature = false;
    var hasTouch = true;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      hasTvFeature = info.systemFeatures.any(_tvFeatures.contains);
      hasTouch = info.systemFeatures.contains(_touchFeature);
    } on Exception {
      hasTvFeature = false;
      hasTouch = true;
    }
    return resolve(
      tvBuild: kTvBuild,
      hasTvFeature: hasTvFeature,
      hasTouchscreen: hasTouch,
      shortestSide: _shortestSideDp(),
    );
  }

  static DeviceMode resolve({
    required bool tvBuild,
    required bool hasTvFeature,
    required bool hasTouchscreen,
    required double shortestSide,
  }) {
    if (hasTvFeature) return DeviceMode.tv;
    if (tvBuild && (shortestSide > 600 || !hasTouchscreen)) {
      return DeviceMode.tv;
    }
    return DeviceMode.touch;
  }

  static double _shortestSideDp() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return 0;
    final view = views.first;
    return (view.physicalSize / view.devicePixelRatio).shortestSide;
  }
}

/// Os componentes leem a variante daqui. Telas não consultam plataforma.
class UiVariantScope extends InheritedWidget {
  const UiVariantScope({super.key, required this.mode, required super.child});

  final DeviceMode mode;

  static DeviceMode of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<UiVariantScope>()?.mode ??
      DeviceMode.touch;

  static bool isTv(BuildContext context) => of(context) == DeviceMode.tv;

  @override
  bool updateShouldNotify(UiVariantScope oldWidget) => oldWidget.mode != mode;
}
