# Hive Box Manager
Type-safe, FP-style abstraction layers for Hive's boxes. Provides Managers for almost all conceivable use-cases and scenarios.

## Features
- Simple BoxManagers
    - Collection BoxManagers
- Single BoxManagers
- Dual Index LazyBoxManager: allows CRUD on two indices (primary and secondary)
  - int-int
  - String-int | int-String
  - Query variants for retrieving by either of the indices