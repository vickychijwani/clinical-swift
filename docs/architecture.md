# Architecture boundaries

The dependency policy lives in [the Swift checker](../scripts/check_architecture.swift).
Keep package models and persistence independent of Apple-only services so they can
run and be tested on Linux. For cross-process database ownership, widget access,
and restore coordination, see [shared database access](persistence.md#shared-database-access).
