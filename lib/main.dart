import 'package:flutter/widgets.dart';
import 'package:macos_ui/macos_ui.dart';

import 'src/app/cabinet_controller.dart';
import 'src/services/cabinet_paths.dart';
import 'src/ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await const MacosWindowUtilsConfig().apply();
  final controller = CabinetController(CabinetPaths.fromEnvironment())..load();
  runApp(CabinetApp(controller: controller));
}
