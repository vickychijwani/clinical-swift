import ClinicalModels
import Foundation

let sampleAppointments: [Appointment] = [
    .init(
        patientName: "Anjali Desai",
        start: Date.now.setTime(9, 0),
        durationMinutes: 60,
        status: .scheduled
    ),
    .init(
        patientName: "Priya Narayanan",
        start: Date.now.setTime(10, 0),
        durationMinutes: 45,
        status: .scheduled
    ),
    .init(
        patientName: "Kabir Malhotra",
        start: Date.now.setTime(10, 0),
        durationMinutes: 45,
        status: .scheduled
    ),
    .init(
        patientName: "Nandini Iyer",
        start: Date.now.setTime(10, 0),
        durationMinutes: 15,
        status: .scheduled
    ),
    .init(
        patientName: "Meera Subramanian",
        start: Date.now.setTime(10, 15),
        durationMinutes: 30,
        status: .scheduled
    ),
    .init(
        patientName: "Ubaid Khan",
        start: Date.now.setTime(12, 0),
        durationMinutes: 15,
        status: .scheduled
    ),
    .init(
        patientName: "Arjun Sethi",
        start: Date.now.setTime(12, 15),
        durationMinutes: 15,
        status: .scheduled
    ),
    .init(
        patientName: "Arjun Sethi",
        start: Date.now.setTime(12, 30),
        durationMinutes: 30,
        status: .scheduled
    ),
    .init(
        patientName: "Nandini Iyer",
        start: Date.now.setTime(20, 0),
        durationMinutes: 60,
        status: .scheduled
    ),
]
