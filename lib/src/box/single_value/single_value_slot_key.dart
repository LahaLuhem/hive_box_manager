import '/src/core/raw_key.dart';

/// The fixed raw key every single-value box stores its one value under.
///
/// `0` is a compatibility invariant, since the 0.0.x single managers used that slot and their boxes
/// have to keep reading. Never change it. It is already raw, so a single-value box needs no key codec,
/// and this is the form observers hear.
const singleValueSlotKey = 0;

/// [singleValueSlotKey] pre-wrapped for the engines, which admit only [RawKey].
const singleValueRawSlotKey = RawKey(singleValueSlotKey);
