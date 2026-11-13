import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/destination_selection.dart';
import 'navigation_controller.dart';

/// Resolve the current notifier for each command, not a retained screen instance.
class RiverpodDestinationSelectionCommands
    implements DestinationSelectionCommands {
  const RiverpodDestinationSelectionCommands(this.ref);
  final Ref ref;
  @override
  bool confirm(DestinationSelectionRequest request) =>
      ref.mounted &&
      ref.read(navigationControllerProvider.notifier).confirm(request);
  @override
  bool reject(DestinationSelectionRequest request) =>
      ref.mounted &&
      ref.read(navigationControllerProvider.notifier).reject(request);
}
