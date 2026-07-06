# Testing

This document captures testing rules that are easy to miss under strict Swift concurrency.

## Async Database Access

- In an `async` test, calls to `DatabaseWriter.read` and `DatabaseWriter.write` resolve to their asynchronous overloads. Always write `try await database.read { ... }` and `try await database.write { ... }`.
- This applies even when the database is an in-memory `DatabaseQueue` and the closure itself contains no suspension point. Overload selection follows the surrounding async context, not whether the closure appears synchronous.
- Keep purely synchronous database tests synchronous when practical. When a test must be async, audit every database read and write in that test for the required `await`.
