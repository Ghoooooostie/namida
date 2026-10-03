// Minimal local stand-in for the `nampack/reactive` primitives that the
// playlist_manager shim depends on. Compile-only stubs (no reactive behavior).
// Classes only (no extensions) so it is safe to import anywhere; call sites use
// constructors directly (e.g. `Rx<bool>(false)`) instead of the `.obs` getter.

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
