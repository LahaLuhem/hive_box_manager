typedef BoxUpdater<T> = T Function(T currentValue);

typedef Decomposer<I1, I2> = Iterable<I2> Function(I1 index);
typedef Encoder<I1, I2, O extends Object> = O Function(I1 primaryIndex, I2 secondaryIndex);

typedef LogCallback = void Function(String message);
typedef LogPattern<I, T> = String Function(String key, I index, T value);
