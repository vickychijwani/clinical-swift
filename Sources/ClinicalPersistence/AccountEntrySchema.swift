import GRDB

nonisolated func createAccountEntrySchema(_ db: Database) throws {
    try db.execute(
        sql: """
            CREATE TABLE accountEntries (
              id TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
              kind TEXT NOT NULL CHECK (kind IN ('charge','receipt','expense','adjustment')),
              amount INTEGER NOT NULL CHECK (amount != 0 AND amount > -9223372036854775808
                AND (kind = 'adjustment' OR amount > 0)),
              entryDate TEXT NOT NULL,
              patientID TEXT REFERENCES patients(id) ON DELETE RESTRICT,
              appointmentID TEXT REFERENCES appointments(id) ON DELETE RESTRICT,
              category TEXT,
              note TEXT,
              paymentMethod TEXT CHECK (paymentMethod IS NULL OR paymentMethod IN ('cash','upi','card','other')),
              createdAt TEXT NOT NULL,
              updatedAt TEXT NOT NULL,
              CHECK (
                (kind = 'charge' AND patientID IS NOT NULL AND category IS NULL AND paymentMethod IS NULL)
                OR (kind = 'adjustment' AND patientID IS NOT NULL AND appointmentID IS NULL
                  AND category IS NULL AND paymentMethod IS NULL)
                OR (kind = 'receipt' AND appointmentID IS NULL AND category IS NOT NULL AND (
                  (category = 'patientFees' AND patientID IS NOT NULL)
                  OR (category IN ('externalConsultations','referralCommissions','otherReceipts') AND patientID IS NULL)))
                OR (kind = 'expense' AND patientID IS NULL AND appointmentID IS NULL AND category IS NOT NULL
                  AND category IN ('rent','staff','consultants','utilities','materials','repairsAndMaintenance',
                    'otherOperatingCosts','equipmentPurchases','clinicImprovements'))
              )
            ) STRICT;
            CREATE INDEX idx_accountEntries_patient ON accountEntries(patientID, entryDate, createdAt, id);
            CREATE INDEX idx_accountEntries_appointment ON accountEntries(appointmentID);
            CREATE INDEX idx_accountEntries_date ON accountEntries(entryDate);
            CREATE TABLE patientBalances (
              id TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE REFERENCES patients(id) ON DELETE CASCADE,
              balance INTEGER NOT NULL,
              createdAt TEXT NOT NULL,
              updatedAt TEXT NOT NULL
            ) STRICT;
            CREATE INDEX idx_patientBalances_positive ON patientBalances(balance) WHERE balance > 0;
            CREATE TRIGGER accountEntry_patient_insert BEFORE INSERT ON accountEntries
            WHEN NEW.appointmentID IS NOT NULL AND NOT EXISTS (
              SELECT 1 FROM appointments WHERE id = NEW.appointmentID AND patientID = NEW.patientID
            ) BEGIN SELECT RAISE(ABORT, 'charge patient must match appointment'); END;
            CREATE TRIGGER accountEntry_patient_update BEFORE UPDATE ON accountEntries
            WHEN NEW.appointmentID IS NOT NULL AND NOT EXISTS (
              SELECT 1 FROM appointments WHERE id = NEW.appointmentID AND patientID = NEW.patientID
            ) BEGIN SELECT RAISE(ABORT, 'charge patient must match appointment'); END;
            CREATE TRIGGER appointment_charged_patient BEFORE UPDATE OF patientID ON appointments
            WHEN OLD.patientID IS NOT NEW.patientID AND EXISTS (
              SELECT 1 FROM accountEntries WHERE appointmentID = OLD.id
            ) BEGIN SELECT RAISE(ABORT, 'appointment has linked charges'); END;
            """)
    // Updates subtract the old row before adding the new row. Do not reject temporary credit.
    for (event, oldRow, newRow) in [
        ("INSERT", false, true), ("UPDATE", true, true), ("DELETE", true, false),
    ] {
        var body = ""
        if oldRow { body += summaryChange(row: "OLD", removing: true) }
        if newRow { body += summaryChange(row: "NEW", removing: false) }
        try db.execute(
            sql:
                "CREATE TRIGGER accountEntry_summary_\(event.lowercased()) AFTER \(event) ON accountEntries BEGIN \(body) END;"
        )
    }
    try rebuildPatientBalances(in: db)
}

nonisolated private func summaryChange(row: String, removing: Bool) -> String {
    let delta = "(CASE WHEN \(row).kind = 'receipt' THEN -\(row).amount ELSE \(row).amount END)"
    let operation = removing ? "-" : "+"
    // SQLite converts overflowing integer addition to REAL. Reject it before STRICT storage.
    return """
        SELECT CASE WHEN \(row).patientID IS NOT NULL AND typeof(
          COALESCE((SELECT balance FROM patientBalances WHERE id = \(row).patientID), 0) \(operation) \(delta)
        ) != 'integer' THEN RAISE(ABORT, 'patient balance overflow') END;
        INSERT INTO patientBalances(id, balance, createdAt, updatedAt)
        SELECT \(row).patientID, 0 \(operation) \(delta),
          strftime('%Y-%m-%d %H:%M:%f','now'), strftime('%Y-%m-%d %H:%M:%f','now')
        WHERE \(row).patientID IS NOT NULL
        ON CONFLICT(id) DO UPDATE SET balance = patientBalances.balance \(operation) \(delta),
          updatedAt = strftime('%Y-%m-%d %H:%M:%f','now');
        """
}
