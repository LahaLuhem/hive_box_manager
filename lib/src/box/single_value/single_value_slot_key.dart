/// The fixed raw key every single-value box stores its one value under.
///
/// `0` is a deliberate compatibility invariant: the 0.0.x single managers used slot `0`, so
/// their boxes read in place under 1.0. Never exported; never change it.
const singleValueSlotKey = 0;
