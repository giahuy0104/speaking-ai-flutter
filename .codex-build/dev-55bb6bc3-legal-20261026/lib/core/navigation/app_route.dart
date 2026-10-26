/// An in-memory navigation request. View creation belongs to the registered
/// presentation factory, never to the caller or to core.
class AppRoute<A> {
  const AppRoute({
    required this.name,
    required this.arguments,
    required this.bindings,
  });

  final String name;
  final A arguments;

  /// Lazily supplies the existing dependencies/callbacks when the view builds.
  /// Keeps live app state and audio ownership semantics unchanged during migration.
  final Object Function() bindings;
}
