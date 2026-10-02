/// Carries demo-mode events between app instances. Outside the browser there
/// is only one instance, so nothing is delivered.
class LocalBus {
  LocalBus(String name);

  void Function(Map<String, dynamic> message)? onMessage;

  void post(Map<String, dynamic> message) {}

  void close() {}
}
