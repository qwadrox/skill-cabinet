import 'package:flutter/widgets.dart';

import '../app/cabinet_controller.dart';

// Hands the controller down the tree; widgets that read it rebuild when
// it notifies.
class CabinetScope extends InheritedNotifier<CabinetController> {
  const CabinetScope({super.key, required CabinetController controller, required super.child})
    : super(notifier: controller);

  static CabinetController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CabinetScope>()!.notifier!;

  // For callbacks: no rebuild dependency.
  static CabinetController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<CabinetScope>()!.notifier!;
}
