# Architecture boundaries

The dependency policy lives in [the Swift checker](../scripts/check_architecture.swift).
Keep package models and persistence independent of Apple-only services so they can
run and be tested on Linux. The app owns platform setup, migrations, and writes;
the widget is a read-only client. See [shared database access](persistence.md#shared-database-access)
for the cross-process constraints that dependency checks cannot enforce.
