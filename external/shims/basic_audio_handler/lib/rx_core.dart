// Minimal local stand-in for the `nampack/reactive` class primitives that
// namida's audio/playlist shims depend on. Compile-only stubs (no reactive
// behavior) so the app builds; runtime reactivity is intentionally absent.
// This file intentionally contains NO extensions, so it is safe to import into
// the main app without polluting the global extension namespace.

class RxBaseCore<T> {}

class Rx<T> {
  final T value;
  Rx(this.value);
}

class Rxn<T> {
  final T? value;
  Rxn([this.value]);
}

class RxList<T> {
  final List<T> value;
  RxList(this.value);
}

class RxMap<K, V> {
  final Map<K, V> value;
  RxMap(this.value);
}
