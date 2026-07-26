import '/src/core/raw_key.dart';

/// The fixed raw key every single-value box stores its one value under.
///
/// `0` is a deliberate compatibility invariant: the 0.0.x single managers used slot `0`, so their
/// boxes read in place under 1.0. Never exported; never change it. Already raw, so a single-value box
/// needs no key codec: this form is what observers hear.
const singleValueSlotKey = 0;

/// [singleValueSlotKey] pre-wrapped for the engines, which admit only [RawKey].
const singleValueRawSlotKey = RawKey(singleValueSlotKey);
