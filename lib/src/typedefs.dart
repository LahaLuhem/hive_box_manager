typedef BoxUpdater<T> = T Function(T currentValue);

typedef LogCallback = void Function(String message);
typedef LogPattern<I, T> = String Function(String key, I index, T value);
