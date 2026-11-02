# Changelog

All notable changes to the GrowthBook Roku SDK.

## [Unreleased]

## [2.0.0] - 2026-10-30

### Breaking
- **Strict types in condition evaluation** (spec 0.10.0, growthbook/growthbook#7379) - an attribute whose type differs from the condition value now fails the operator and matches its negation. No coercion: `"10"` no longer equals `10`, a string number no longer satisfies `$gt`/`$lt` against a number (or vice versa), a missing attribute fails comparison operators, booleans are not ordered, and version operators (`$veq`, `$vgt`, ...) need both sides to be strings or both numbers. `$exists` and `$type` are unchanged.
- **Unsupported operators fail** (spec 0.11.0, growthbook/growthbook#7346) - a condition that depends on an operator or saved group type this SDK doesn't support now fails, including under `$not` and `$nor`, where it used to pass
- **Rollout boundary** (spec 0.11.1, growthbook/growthbook#7425) - a rollout includes a user only when their hash is below the coverage, so a coverage of k/10000 includes exactly k hash buckets
- **Hash attribute values** (spec 0.12.0) - only a non-empty string or a non-zero number identifies a user. `0`, `false`, `true`, `null`, `""`, arrays and objects count as missing, so the fallback attribute is tried, or the user is left out of the experiment or rollout. Integral numbers hash without a decimal part (`1.0` hashes as `"1"`)
- **Fallback attribute** (spec 0.12.0) - `fallbackAttribute` is only used when sticky bucketing is enabled for the rule, like the JS SDK
- **Double precision bucketing** (growthbook-roku#22) - hashes and bucket ranges are computed in double precision, and range ends round `coverage * weight` before adding it, so users whose hash lands on a range end are bucketed like the JS SDK

### Added
- **Case-insensitive operators** - `$ini`, `$nini`, `$alli` and `$regexi`

### Fixed
- **Condition edge cases** (spec 0.11.0) - `$elemMatch` with `$or`/`$and`/`$nor`/`$savedGroup` tests each element's fields; a condition value of `{}` always passes; `$or`/`$and`/`$nor`/`$savedGroup` on a value never match; `$inGroup`/`$notInGroup` read typed `list` saved groups, and a missing group no longer ends evaluation of the whole condition
- **Prerequisite gates** - a prerequisite's condition alone decides whether it passes; a gate no longer also fails when the parent is off (growthbook-roku#23)
- **Non-blocking prerequisites** - a failing prerequisite that is not a gate now skips the rule instead of blocking the feature, so a malformed prerequisite condition falls through to the next rule
- **Version strings** - an empty version is treated as `0`, and empty segments (`"1..2"`) are kept, matching the JS SDK
- **Sticky bucketing** - assignments stored under the fallback attribute are merged even when they lack the current bucket version, so `minBucketVersion` blocks old fallback assignments
- **Non-string hash attributes** - a boolean, array or object hash attribute, namespace attribute or filter attribute no longer stops evaluation with a `Str()` runtime error
- **Force rule filters and namespaces** - a force rule's filters no longer need the rule's hash attribute, a filter without an `attribute` hashes `id` (not the rule's `hashAttribute`), and namespaces only apply to experiment rules, like the JS SDK
- **`$type` on large numbers** - `$type: "number"` matches `LongInteger` and `Double` values, such as `2147483648`
- **Feature `on`/`off`** - `Double` and `LongInteger` values follow JS truthiness, so `0` of either type is off
- **Native test runner** - `run-native.js` now fails when the interpreter stops before printing a result, instead of reporting a pass

### Changed
- **Spec tests** - `tests/cases.json` updated from spec 0.7.1 to 0.12.0; contextual bandit feature cases are skipped (not implemented), and remote saved groups (`savedGroupReferencesRemote`) are not implemented. `tests/regression-cases.json` can also hold `run`, `feature` and `stickyBucket` cases, and the JS validator compares array and object feature values deeply. Both test runners list the spec sections they don't run, with a reason, and fail on a section that is neither run nor listed. The payload reduction methods (`pruneCondition`, `reducePayload`) are not implemented for client SDKs to start with

## [1.4.1] - 2026-02-18

### Fixed
- **Namespace hash seed** - `_inNamespace` now uses the required `"__"` prefix for the hash seed, matching the GrowthBook specification
- **Regex case sensitivity** - `$regex` operator now defaults to case-sensitive matching, consistent with the reference SDK and MongoDB behavior
- **Native test runner (Windows)** - Replaced `spawnSync` with `execSync` in `run-native.js` for reliable execution on Windows

### Added
- **brs-desktop test channel** - `test-channel/` for on-device SDK validation via [brs-desktop](https://github.com/lvcabral/brs-desktop), with runtime smoke tests and full `cases.json` spec coverage

### Improved
- **Documentation** - TESTING.md rewritten to reflect actual test infrastructure (JS validator + native BrightScript runner + brs-desktop test channel)

---

## [1.4.0] - 2026-02-10

### Added
- **Encrypted Features** - AES-128-CBC decryption for encrypted feature payloads (`roEVPCipher`, Roku OS 9.2+)
  - Supports `encryptedFeatures` and `encryptedSavedGroups` in API responses
  - Configure with `decryptionKey` option
- **Sticky Bucketing** - Persistent experiment assignments across sessions
  - `GrowthBookInMemoryStickyBucketService()` for testing and simple use
  - `GrowthBookRegistryStickyBucketService()` for persistent storage via `roRegistrySection`
  - Supports `fallbackAttribute` for anonymous-to-logged-in user transitions
  - Version blocking via `minBucketVersion` and `bucketVersion`
- **Tracking Plugin System** - Extensible plugin architecture for event tracking
  - `registerTrackingPlugin()` to add plugins at runtime
  - Plugins receive `onExperimentViewed` and `onFeatureUsage` events
  - Built-in `GrowthBookTrackingPlugin` for data warehouse integration with batched HTTP delivery
- **Refresh Features API** - On-demand feature updates via `refreshFeatures()`
- **Fallback Attribute Support** - `fallbackAttribute` in hash context for sticky bucketing prerequisites
- **Decrypt & Sticky Bucket Test Coverage** - Both test runners (BrightScript + JS validator) now cover all spec categories

### Improved
- **Platform Compatibility** - Cipher operations wrapped in try/catch for cross-platform resilience
- **Feature Parsing** - `_parseFeatures()` now handles encrypted payloads, encrypted saved groups, and plain saved groups

---

## [1.3.1] - 2026-02-03

### Changes
- **Ropm support** - Added support for ropm
- Minor documentation updates

---

## [1.3.0] - 2026-01-28

### Added
- **BrightScript Test Runner** - Native BrightScript test runner that parses and executes `cases.json` directly on device
- **Tracking Callbacks**
  - `trackingCallback` - Triggered when a user is exposed to an experiment (includes de-duplication)
  - `onFeatureUsage` - Triggered for every feature evaluation
- **Experiment De-duplication** - Prevents duplicate tracking calls for the same experiment/variation/user combination
- **CI/CD Workflows**
  - `ci.yml` - Automated testing and syntax checking on PRs
  - `release.yml` - Automated GitHub releases on version tags

### Improved
- **Documentation** - Expanded API docs and Integration Guide
- **Code Organization** - Refactored test suite to use `cases.json` as source of truth

### Fixed
- **JSON Primitive Parsing** - Fixed crash when parsing boolean strings from primitive types using robust `LCase()` utility

---

## [1.2.0] - 2025-12-11

### Added
- **Group operators** - `$inGroup` and `$notInGroup` for saved group targeting
  - Target users based on pre-defined group membership (beta testers, VIP users, etc.)
  - Requires `savedGroups` configuration parameter
- **savedGroups parameter** - Pass saved groups to SDK for group-based targeting
- **Deep equality checks** - Proper object comparison for targeting conditions
- **2 new examples**
  - `examples/group_targeting.brs` - Demonstrates $inGroup/$notInGroup usage
  - `examples/complex_conditions.brs` - Advanced targeting with $elemMatch and nested conditions

### Fixed
- **$elemMatch operator** - Now correctly handles flat arrays and nested object conditions
- **Unknown operators** - Properly returns false for unrecognized operators (e.g., typos like "$regx")
- **Logical operators** - Fixed $not and $or edge cases with multiple conditions
- **Object comparison** - Fixed deep equality for extra/missing property detection

### Improved
- **Test coverage** - evalCondition: 220/221 (99.5%), up from 204/221 (92.3%)
- **Code quality** - Simplified $elemMatch implementation, removed duplicate code

---

## [1.1.0] - 2025-12-04

### Added
- **Coverage parameter** - Support for progressive rollouts with percentage-based user inclusion
- **Bucket range functions** - Precise variation assignment using `_getBucketRanges`, `_chooseVariation`, `_inRange`
- **Array intersection for `$in`/`$nin`** - Tag-based targeting when user attribute is an array
  - Example: User tags `["premium", "beta"]` matches condition `["beta", "qa"]`

### Improved
- **JavaScript validator** - Comprehensive test coverage without a device
  - Added hash, getBucketRange, chooseVariation test categories (all 100%)
  - Added version operators to evalCondition tests
  - Total coverage: 72.3% → 79.5% (245/308 tests passing)

### Documentation
- Progressive rollout example (`examples/coverage_rollout.brs`)
- Array targeting example (`examples/array_targeting.brs`)
- Enhanced inline documentation in bucket range functions
- Debug logging for experiment bucketing

---

## [1.0.0] - 2025-11-28

### Added
- Version comparison operators for semantic version targeting
  - `$veq`, `$vne`, `$vgt`, `$vgte`, `$vlt`, `$vlte`
  - Supports semantic versioning (e.g., "1.4.0"), pre-release versions (e.g., "1.0.0-beta")
  - Handles version prefixes and build metadata

### Fixed
- **Weight extraction bug** - Experiments now correctly use weights from rule level, enabling custom traffic splits (70/30, etc.)
- **Seeded hash function** - Implemented FNV-1a 32-bit hash for consistent user bucketing across sessions and platforms

### Documentation
- Integration guide for production deployment
- Quick start guide
- API reference with targeting operators
- Working examples for version targeting, weighted experiments, and consistent hashing

---

## [0.9.0] - 2025-11

Initial release with basic feature flag and experiment support.
