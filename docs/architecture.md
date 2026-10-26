# Architecture boundaries

The policy is defined in [the Swift checker](../scripts/check_architecture.swift).
The app uses `ClinicalModels` and `ClinicalPersistence`. Persistence uses models.
The widget uses models and compiles `ClinicalShared` with the app. Shared database
code keeps the widget a coordinated read-only client. The app owns migrations
and writes. Keep the standard SwiftPM `Sources/` and `Tests/` layout.

App-owned appearance colors use a shared palette. Debug builds can override it
with the local [design tools](design-tools.md). Keep these preferences outside
clinic data and widget storage.
