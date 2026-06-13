import Foundation

let sampleAppointments: [Appointment] = [
    .init(
        patientName: "Anjali Desai",
        startTime: Date.now.setTime(9, 0),
        durationMinutes: 60,
        status: .scheduled
    ),
    .init(
        patientName: "Ubaid Khan",
        startTime: Date.now.setTime(12, 0),
        durationMinutes: 15,
        status: .scheduled
    ),
    .init(
        patientName: "Arjun Sethi",
        startTime: Date.now.setTime(12, 15),
        durationMinutes: 15,
        status: .scheduled
    ),
    .init(
        patientName: "Arjun Sethi",
        startTime: Date.now.setTime(12, 30),
        durationMinutes: 30,
        status: .scheduled
    ),
    .init(
        patientName: "Nandini Iyer",
        startTime: Date.now.setTime(20, 0),
        durationMinutes: 60,
        status: .scheduled
    ),
]
