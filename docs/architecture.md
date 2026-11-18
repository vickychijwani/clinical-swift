# Architecture boundaries

Keep shared models and persistence independent of Apple-only services so they can
run on Linux. The [dependency checker](../scripts/check_architecture.swift) enforces
package boundaries. See [persistence](persistence.md) for database ownership and
cross-process rules.
