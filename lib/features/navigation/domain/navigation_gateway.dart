/// Future integration seam, not an implementation.
/// Google Maps/Routes should be adapted behind a repository and platform service.
abstract interface class NavigationGateway {
  Future<void> planJourney({required String destination, required bool byBus});
}
