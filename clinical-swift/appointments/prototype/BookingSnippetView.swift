#if DEBUG
    import AppIntents
    import ClinicalModels
    import SwiftUI

    struct BookingSnippetSnapshot {
        let id: String
        let patientName: String
        let date: Date
        let start: Date
        let end: Date
        let duration: Int
        let appointments: [Appointment]
        let suggestions: [Date]
        let isBooked: Bool

        init(_ session: BookingSnippetSession) {
            let draft = session.model.draft
            id = session.id
            patientName = draft.selectedPatient?.displayName ?? "Patient"
            date = draft.selectedDate
            start = draft.start
            end = draft.start.addingTimeInterval(TimeInterval(draft.durationMinutes * 60))
            duration = draft.durationMinutes
            appointments = session.schedule
            suggestions = session.suggestedStarts
            isBooked = session.booked != nil
        }
    }

    /// Both hosts use this content. Only the playground supplies local button actions.
    struct BookingSnippetView: View {
        let snapshot: BookingSnippetSnapshot
        var onAdjust: (@MainActor (BookingSnippetAction, Int) async -> Void)?
        var onChangePatient: (@MainActor () -> Void)?

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(
                        snapshot.isBooked ? "Demo booked" : "Book appointment",
                        systemImage: snapshot.isBooked
                            ? "checkmark.circle.fill" : "calendar.badge.plus"
                    )
                    .font(.headline)
                    Spacer()
                    Text("DEMO")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.teal.opacity(0.12), in: .capsule)
                }
                .foregroundStyle(.teal)

                if snapshot.isBooked {
                    BookingSnippetReceipt(snapshot: snapshot)
                } else {
                    HStack {
                        Text(snapshot.patientName).font(.title3.bold()).lineLimit(1)
                        Spacer()
                        if let onChangePatient {
                            Button("Change", action: onChangePatient)
                        }
                    }

                    HStack {
                        BookingSnippetButton(
                            snapshot: snapshot, action: .day, value: -1, onAdjust: onAdjust
                        ) {
                            Label("Previous day", systemImage: "chevron.left").labelStyle(.iconOnly)
                        }
                        Spacer()
                        Text(
                            snapshot.date,
                            format: .dateTime.weekday(.abbreviated).day().month(.abbreviated)
                        )
                        .font(.headline)
                        .contentTransition(.numericText())
                        Spacer()
                        BookingSnippetButton(
                            snapshot: snapshot, action: .day, value: 1, onAdjust: onAdjust
                        ) {
                            Label("Next day", systemImage: "chevron.right").labelStyle(.iconOnly)
                        }
                    }
                    Text(
                        "Scroll to see all \(snapshot.appointments.count - 1) appointments"
                    )
                    .font(.caption).foregroundStyle(.secondary)
                    Divider()
                    HStack {
                        BookingSnippetButton(
                            snapshot: snapshot, action: .time, value: -15, onAdjust: onAdjust
                        ) { Text("−15m").font(.subheadline.monospacedDigit()) }
                        Spacer()
                        VStack(spacing: 2) {
                            Text(snapshot.start, format: .dateTime.hour().minute())
                                .font(.title2.bold()).monospacedDigit()
                                .contentTransition(.numericText())
                            Text(
                                "Until \(snapshot.end.formatted(date: .omitted, time: .shortened))"
                            )
                            .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        BookingSnippetButton(
                            snapshot: snapshot, action: .time, value: 15, onAdjust: onAdjust
                        ) { Text("+15m").font(.subheadline.monospacedDigit()) }
                    }

                    HStack {
                        ForEach([15, 30, 45, 60], id: \.self) { minutes in
                            BookingSnippetButton(
                                snapshot: snapshot, action: .duration, value: minutes,
                                onAdjust: onAdjust
                            ) {
                                Text("\(minutes)m")
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .background(
                                        snapshot.duration == minutes ? .teal.opacity(0.18) : .clear,
                                        in: .capsule)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if !snapshot.suggestions.isEmpty {
                        HStack {
                            Text("Open").font(.caption).foregroundStyle(.secondary)
                            ForEach(snapshot.suggestions, id: \.self) { start in
                                BookingSnippetButton(
                                    snapshot: snapshot, action: .slot,
                                    value: TimeOfDay(date: start).totalMinutes, onAdjust: onAdjust
                                ) {
                                    Text(start, format: .dateTime.hour().minute())
                                        .font(.caption.bold()).lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                        .background(.teal.opacity(0.08), in: .capsule)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Divider()
                    HStack {
                        Text("Day schedule").font(.subheadline.bold())
                        Spacer()
                        Text("\(snapshot.appointments.count - 1) appointments")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(spacing: 6) {
                        ForEach(snapshot.appointments) { appointment in
                            BookingSnippetScheduleRow(appointment: appointment)
                        }
                    }
                }
            }
            .padding()
            .tint(.teal)
        }
    }

    private struct BookingSnippetButton<Label: View>: View {
        let snapshot: BookingSnippetSnapshot
        let action: BookingSnippetAction
        let value: Int
        let onAdjust: (@MainActor (BookingSnippetAction, Int) async -> Void)?
        @ViewBuilder var label: () -> Label

        var body: some View {
            if let onAdjust {
                AsyncButton {
                    await onAdjust(action, value)
                } label: {
                    label()
                }
            } else {
                Button(
                    intent: AdjustBookingSnippetIntent(
                        sessionID: snapshot.id, action: action, value: value)
                ) { label() }
            }
        }
    }

    private struct BookingSnippetScheduleRow: View {
        let appointment: Appointment

        var body: some View {
            HStack {
                RoundedRectangle(cornerRadius: 2)
                    .fill(appointment.status == .draft ? .teal : .secondary.opacity(0.4))
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(appointment.patientName).font(.subheadline).lineLimit(1)
                        if appointment.status == .draft {
                            Text("NEW").font(.caption2.bold()).foregroundStyle(.teal)
                        }
                    }
                    Text("\(appointment.durationMinutes) min")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(appointment.start, format: .dateTime.hour().minute())
                    .font(.subheadline.monospacedDigit())
            }
            .padding(8)
            .background(
                appointment.status == .draft ? .teal.opacity(0.08) : .secondary.opacity(0.04),
                in: .rect(cornerRadius: 10))
        }
    }

    private struct BookingSnippetReceipt: View {
        let snapshot: BookingSnippetSnapshot

        var body: some View {
            VStack(alignment: .leading) {
                Text(snapshot.patientName).font(.title2.bold())
                Text(snapshot.start, format: .dateTime.weekday().day().month().hour().minute())
                    .font(.headline)
                Text("\(snapshot.duration) minutes · Bitehaus Dental Clinic")
                    .foregroundStyle(.secondary)
                Text("Demo only. Your clinic schedule has not changed.")
                    .font(.caption).foregroundStyle(.secondary).padding(.top)
            }
        }
    }

    struct BookingSnippetPlayground: View {
        @Environment(BookingSnippetStore.self) private var store
        @State private var session: BookingSnippetSession?
        @State private var isChoosingPatient = false
        @State private var errorMessage: String?

        var body: some View {
            ScrollView {
                VStack(spacing: 24) {
                    Text(
                        "Try a quick booking with your patients and day schedule. All bookings here are temporary."
                    )
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if let session {
                        BookingSnippetView(
                            snapshot: BookingSnippetSnapshot(session),
                            onAdjust: { action, value in
                                do {
                                    try await store.adjust(session.id, action: action, value: value)
                                } catch { errorMessage = error.localizedDescription }
                            },
                            onChangePatient: { isChoosingPatient = true }
                        )
                        .background(.background, in: .rect(cornerRadius: 24))
                        .overlay {
                            RoundedRectangle(cornerRadius: 24).stroke(.teal.opacity(0.15))
                        }

                        if session.booked == nil {
                            Button {
                                do { try store.book(session.id) } catch {
                                    errorMessage = error.localizedDescription
                                }
                            } label: {
                                Text("Book demo appointment").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent).controlSize(.large)
                        } else {
                            AsyncButton("Book another", systemImage: "plus") {
                                guard let patient = session.model.draft.selectedPatient else {
                                    return
                                }
                                do { self.session = try await store.begin(patient: patient) } catch
                                { errorMessage = error.localizedDescription }
                            }
                            .buttonStyle(.borderedProminent).controlSize(.large)
                        }
                    } else {
                        ContentUnavailableView {
                            Label(
                                "Start with a patient", systemImage: "person.crop.circle.badge.plus"
                            )
                        } description: {
                            Text("Search by name, then choose a day and time.")
                        } actions: {
                            Button("Choose patient") { isChoosingPatient = true }
                                .buttonStyle(.borderedProminent)
                        }
                    }

                    VStack(spacing: 8) {
                        Text("Try the system snippet").font(.headline)
                        Text(
                            "Open Clinical in Shortcuts and run Try Snippet Booking. The system provides patient search and the Book button."
                        )
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(
                            .center)
                        ShortcutsLink()
                    }
                }
                .padding()
            }
            .background(Color("AppBackground"))
            .tint(.teal)
            .navigationTitle("Booking prototype")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $isChoosingPatient) {
                BookingPrototypePatientPicker { patient in
                    do {
                        if let session, session.booked == nil {
                            try store.selectPatient(patient, sessionID: session.id)
                        } else {
                            session = try await store.begin(patient: patient)
                        }
                        isChoosingPatient = false
                    } catch { errorMessage = error.localizedDescription }
                }
            }
            .alert(
                "Booking prototype",
                isPresented: Binding(
                    get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private struct BookingPrototypePatientPicker: View {
        @Environment(BookingSnippetStore.self) private var store
        @Environment(\.dismiss) private var dismiss
        @State private var patients: [Patient] = []
        @State private var search = ""
        @State private var loadError: String?
        let onSelect: @MainActor (Patient) async -> Void

        var body: some View {
            NavigationStack {
                List {
                    if let loadError { Text(loadError).foregroundStyle(.secondary) }
                    ForEach(
                        patients.filter { PatientNameSearch.matches($0.name, searchText: search) }
                    ) { patient in
                        AsyncButton {
                            await onSelect(patient)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(patient.displayName).foregroundStyle(.primary)
                                if let phone = patient.phone {
                                    Text(phone).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                        }
                    }
                }
                .searchable(text: $search, prompt: "Patient name")
                .navigationTitle("Choose patient")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel) { dismiss() }
                    }
                }
                .task {
                    do { patients = try await store.patients() } catch {
                        loadError = error.localizedDescription
                    }
                }
            }
        }
    }
#endif
