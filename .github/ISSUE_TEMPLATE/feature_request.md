---
name: Feature request
about: Suggest a new box variant, Manager capability, or integration
title: ''
labels: ''
assignees: ''

---

**What would you like?**
A new box-manager variant, a method on an existing Manager, or an integration
(fpdart helpers, a Flutter binding, serialisation)?

**The scenario it serves**
What storage shape or access pattern does it cover (single value, a collection per
key, a dual / composite index, a reverse lookup, something else)? A concrete example
of the data and how you'd read and write it helps a lot.

**Why isn't an existing Manager enough?**
What goes wrong or gets awkward today when you use the current Managers for this?

**Does it fit the core, or a companion?**
Pure-Dart behaviour over hive_ce belongs in core; anything Flutter-specific or with a
heavy dependency is likely a companion package. Where do you think this sits?

**Additional context**
Alternatives you've considered, prior art in other packages, anything else.
