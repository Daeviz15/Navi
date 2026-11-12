import 'dart:async';

import 'package:navi/features/location/domain/location_gateway.dart';

class FakeLocationGateway implements LocationGateway {
  FakeLocationGateway({this.result = LocationAccess.denied});

  LocationAccess result;
  Completer<LocationAccess>? pendingAccess;
  final permissionRequests = <bool>[];
  final positions = StreamController<LocationFix>.broadcast();
  final services = StreamController<bool>.broadcast();
  int watchCalls = 0;

  @override
  Future<LocationAccess> access({required bool requestPermission}) {
    permissionRequests.add(requestPermission);
    return pendingAccess?.future ?? Future.value(result);
  }

  @override
  Stream<LocationFix> watch() {
    watchCalls++;
    return positions.stream;
  }

  @override
  Stream<bool> serviceChanges() => services.stream;

  @override
  Future<void> openAppSettings() async {}

  @override
  Future<void> openLocationSettings() async {}

  Future<void> close() async {
    await positions.close();
    await services.close();
  }
}
