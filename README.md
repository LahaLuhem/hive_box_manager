# 📦 Hive Box Manager

Type-safe, FP-style abstraction layers for Hive's boxes. Provides Managers for almost all conceivable use-cases and scenarios.

---

## 📚 Table of Contents

- [Understanding Box Types](#-understanding-box-types)
  - [Box vs LazyBox](#box-vs-lazybox)
- [Manager Types](#-manager-types)
  - [Simple Managers](#1-simple-managers-boxmanager--lazyboxmanager)
  - [Single Index Managers](#2-single-index-managers)
  - [Collection Managers](#3-collection-managers)
  - [Dual Index Managers](#4-dual-index-managers)

---

## 🎯 Understanding Box Types

### Box vs LazyBox

The fundamental distinction in Hive (and this library) is between **Box** and **LazyBox**. Understanding when to use each is crucial for optimal performance.

#### 📦 **Box** (Eager Loading)

**What it does:** Loads **all** data into memory when opened.

**✅ Pros:**
- ⚡ **Instant reads** - Data is already in memory (synchronous access)
- 🎯 **Simple API** - No async/await needed for reads
- 🚀 **Best for frequent access** - Perfect when you need to read data repeatedly
- 💪 **Predictable performance** - No I/O delays during reads

**❌ Cons:**
- 💾 **High memory usage** - Entire box contents loaded into RAM
- 🐌 **Slower startup** - Takes time to load all data when opening
- ⚠️ **Not suitable for large datasets** - Can cause memory issues with >10MB of data
- 📱 **Mobile unfriendly** - Limited RAM on mobile devices

**When to use:**
- Small datasets (< 1MB)
- Frequently accessed data (e.g., user preferences, app settings)
- Data that needs to be read synchronously
- When memory is not a constraint

---

#### 💤 **LazyBox** (Lazy Loading)

**What it does:** Loads data **on-demand** from disk only when requested.

**✅ Pros:**
- 🪶 **Minimal memory footprint** - Only loads what you need
- ⚡ **Fast startup** - Opens instantly regardless of data size
- 📊 **Scales well** - Can handle large datasets (100MB+)
- 📱 **Mobile friendly** - Conserves precious device memory

**❌ Cons:**
- ⏱️ **Async reads** - Every read requires disk I/O (slower)
- 🔄 **More complex API** - Must use async/await for all operations
- 🐌 **Slower for frequent access** - Repeated reads hit disk each time
- 💻 **I/O overhead** - Each access has file system overhead

**When to use:**
- Large datasets (> 1MB)
- Infrequently accessed data (e.g., cached images, historical logs)
- Memory-constrained environments (mobile apps)
- When you only need specific items, not the whole dataset

---

## 🛠️ Manager Types

### 1. **Simple Managers** (`BoxManager` & `LazyBoxManager`)

**Purpose:** Multi-item storage with custom indices (int or String keys).

**Use cases:**
- Storing multiple users, products, or entities
- Key-value storage where you control the keys
- Collections that need individual item access

**Example:**
```dart
// Eager loading - all users in memory
final userBox = BoxManager<User, int>(
  boxKey: 'users',
  defaultValue: User.empty(),
);

// Lazy loading - users loaded on demand
final userLazyBox = LazyBoxManager<User, String>(
  boxKey: 'users_lazy',
  defaultValue: User.empty(),
);

// Usage
await userBox.init();
await userBox.put(index: 1, value: user1).run(); // Synchronous read later
final user = userBox.get(1); // Instant!

await userLazyBox.init();
await userLazyBox.put(index: 'user_123', value: user2).run();
final user2 = await userLazyBox.get('user_123').run(); // Async read
```

**Trade-offs:**
| Aspect | BoxManager | LazyBoxManager |
|--------|-----------|----------------|
| Read Speed | ⚡ Instant | 🐌 Disk I/O |
| Memory | 💾 High | 🪶 Low |
| Startup | 🐌 Slow | ⚡ Fast |
| Best for | Small, frequent | Large, occasional |

---

### 2. **Single Index Managers**

**Purpose:** Store **one** value per box (like a single setting or configuration).

**Why needed:** Simplified API when you only need to store a single value without managing indices.

**Variants:**
- `SingleIndexBoxManager<T>` - Eager loading
- `SingleIndexLazyBoxManager<T>` - Lazy loading

**Use cases:**
- App theme preference
- User authentication token
- Last sync timestamp
- App configuration object

**Example:**
```dart
final themeBox = SingleIndexBoxManager<AppTheme>(
  boxKey: 'app_theme',
  defaultValue: AppTheme.light,
);

await themeBox.init();
await themeBox.put(value: AppTheme.dark).run();
final theme = themeBox.get(); // No index needed!
```

**Trade-offs:**
- ✅ **Simpler API** - No index management
- ✅ **Clear intent** - Obvious it's a single value
- ❌ **Limited to one value** - Can't store multiple items
- 💡 **Choose Lazy variant** if the value is large (e.g., cached JSON)

---

### 3. **Collection Managers**

**Purpose:** Store **collections** (Lists, Sets) of custom types as values.

**Why needed:** Hive has limitations reading `Iterable<CustomType>` directly ([issue #150](https://github.com/IO-Design-Team/hive_ce/issues/150)). This manager works around that limitation.

**Variant:**
- `CollectionLazyBoxManager<T, I>` - Stores `Iterable<T>` at each index

**Use cases:**
- Storing lists of items per category
- Multiple tags per entity
- Historical records grouped by date
- Batch data storage

**Example:**
```dart
final tagsBox = CollectionLazyBoxManager<String, int>(
  boxKey: 'post_tags',
  defaultValue: <String>[],
);

await tagsBox.init();
await tagsBox.put(
  index: 1, // Post ID
  value: ['flutter', 'dart', 'mobile'],
).run();

final tags = await tagsBox.get(1).run(); // Returns Iterable<String>
```

**Trade-offs:**
- ✅ **Solves Hive limitation** - Enables storing custom type collections
- ✅ **Type-safe** - Proper generic typing
- ⚠️ **Lazy only** - No eager variant (memory concerns with collections)
- 💡 **Use for grouped data** - Perfect for one-to-many relationships

---

### 4. **Dual Index Managers**

**Purpose:** Store data with **two indices** (composite keys) - like a 2D grid or matrix.

**Why needed:** When your data naturally has two dimensions (e.g., user + date, row + column).

**Variants:**

#### **A. Standard Dual Index Managers**

Store and retrieve by two indices simultaneously.

- `DualIntIndexBoxManager<T>` - Eager, int + int indices
- `DualIntIndexLazyBoxManager<T>` - Lazy, int + int indices

**Encoding Strategy: Bit-Shift**

**✅ Pros:**
- ⚡ **Maximum performance** - Bit operations are the fastest CPU operations
- 🎯 **Perfect distribution** - Uses all 32 bits efficiently (16 bits each)
- 💾 **No wasted space** - Can represent 0 to 65,536 for both indices
- 🔒 **Collision-free** - Mathematically proven unique encoding

**❌ Cons:**
- 📏 **Fixed range** - Limited to 16-bit integers (0-65,536)
- ➖ **No negative numbers** - Without additional handling
- 🕳️ **Not great for sparse data** - Wastes encoding space if data is sparse
- ⚠️ **Platform dependency** - Potential issues if Dart's integer behavior changes

**Use cases:**
- Grid-based games (x, y coordinates)
- Time-series data (user ID + day index)
- Matrix storage (row + column)
- Relational data with two keys

**Example:**
```dart
final gameBoard = DualIntIndexLazyBoxManager<Tile>.bitShift(
  boxKey: 'game_tiles',
  defaultValue: Tile.empty(),
);

await gameBoard.init();
await gameBoard.put(
  primaryIndex: 5,   // X coordinate
  secondaryIndex: 10, // Y coordinate
  value: tile,
).run();

final tile = await gameBoard.get(
  primaryIndex: 5,
  secondaryIndex: 10,
).run();
```

---

#### **B. Query Dual Index Managers**

**Purpose:** Retrieve data by **either** index independently (reverse lookups).

- `QueryDualIntIndexBoxManager<T>` - Eager variant
- `QueryDualIntIndexLazyBoxManager<T>` - Lazy variant

**Why needed:** Sometimes you need to find all items matching one index:
- "Give me all tiles at X=5" (any Y)
- "Give me all events on day 10" (any user)

**✅ Pros:**
- ✅ **Perfect accuracy** - Always reflects current box state
- 💾 **Zero storage overhead** - No additional boxes or memory structures
- 🪶 **Memory efficient** - Only stores seen indices during iteration
- 🛡️ **Simple & robust** - Less code, fewer failure points
- ⚡ **Leverages Hive optimizations** - Uses Hive's built-in key indexing

**❌ Cons:**
- 🐌 **O(K) per query** - Performance degrades with total records
- 🔄 **No pre-computation** - Each query scans all keys
- ⚠️ **Not optimal for very large datasets** - >100K records may cause UI jank
- 📊 **No indexing benefits** - Each decomposition is a full scan

**Use cases:**
- Finding all events for a specific user
- Getting all data points for a specific date
- Querying one dimension of a 2D dataset

**Example:**
```dart
final userEvents = QueryDualIntIndexLazyBoxManager<Event>.bitShift(
  boxKey: 'user_events',
  defaultValue: Event.empty(),
);

await userEvents.init();

// Store events
await userEvents.put(
  primaryIndex: userId,
  secondaryIndex: dayIndex,
  value: event,
).run();

// Query all events for a user (any day)
final allUserEvents = await userEvents
  .getAllByPrimaryIndex(userId)
  .run();

// Query all events on a specific day (any user)
final dailyEvents = await userEvents
  .getAllBySecondaryIndex(dayIndex)
  .run();
```

**Trade-offs:**
| Aspect | Standard Dual | Query Dual |
|--------|--------------|------------|
| Storage | Single box | Single box |
| Retrieval | By both indices | By either index |
| Performance | O(1) lookup | O(K) scan |
| Use case | Exact lookups | Partial queries |
| Complexity | Simple | Moderate |

---

## 🎨 Quick Decision Guide

```
Need to store...

├─ Single value?
│  ├─ Small (< 100KB)? → SingleIndexBoxManager
│  └─ Large (> 100KB)? → SingleIndexLazyBoxManager
│
├─ Multiple items with one key?
│  ├─ Small dataset (< 1MB), frequent access? → BoxManager
│  ├─ Large dataset (> 1MB), occasional access? → LazyBoxManager
│  └─ Collections of custom types? → CollectionLazyBoxManager
│
└─ Multiple items with two keys?
   ├─ Only need exact lookups (both keys)? → DualIntIndexBoxManager/LazyBoxManager
   └─ Need to query by either key? → QueryDualIntIndexBoxManager/LazyBoxManager
```

---

## 📖 Additional Resources

- [Hive Documentation](https://docs.hive.isar.community/#/)
- [fpdart Documentation](https://pub.dev/packages/fpdart) - For understanding `Task` and functional patterns

---

## 📄 License

See [LICENSE](LICENSE) file for details.