import Foundation

let samplePatients: [Patient] = [
    .init(
        name: nil,
        phone: "+91 98201 44532",
        dob: Date.now.setTime(0, 0),
        gender: .male,
        createdDate: Date.now.setTime(9, 0)
    ),
    .init(
        name: nil,
        phone: "+91 98209 46617",
        dob: nil,
        gender: .female,
        createdDate: Date.now.setTime(17, 45)
    ),
    .init(
        name: "Aarav Mehta",
        phone: "+91 98201 44532",
        dob: Date(timeIntervalSinceReferenceDate: -459_561_600),
        gender: .male
    ),
    .init(
        name: "Anjali Desai",
        phone: "+91 98209 46617",
        dob: Date(timeIntervalSinceReferenceDate: -711_244_800),
        gender: .female
    ),
    .init(
        name: "Arjun Sethi",
        phone: "+91 98100 60234",
        dob: nil,
        gender: .male
    ),
    .init(
        name: "Dev Malhotra",
        phone: "+91 98920 13472",
        dob: Date(timeIntervalSinceReferenceDate: 282_096_000),
        gender: .male
    ),
    .init(
        name: "Ishaan Verma",
        phone: "+91 98112 55309",
        dob: Date(timeIntervalSinceReferenceDate: 408_240_000),
        gender: nil
    ),
    .init(
        name: "Nandini Iyer",
        phone: "+91 98112 55310",
        dob: Date(timeIntervalSinceReferenceDate: 408_240_000),
        gender: nil
    ),
    .init(
        name: "Ubaid Khan",
        phone: "+91 98112 55311",
        dob: Date(timeIntervalSinceReferenceDate: 408_240_000),
        gender: nil
    ),
]

let samplePatientListItems: [PatientListItem] = samplePatients.enumerated().map { offset, patient in
    PatientListItem(
        patient: patient,
        nextAppointmentDate: sampleNextAppointmentDate(forPatientAt: offset)
    )
}

private func sampleNextAppointmentDate(forPatientAt offset: Int) -> Date? {
    switch offset {
    case 0:
        Date.now.setTime(18, 30)
    case 2:
        Date.now.setTime(10, 0)
    case 3:
        Date.now.setTime(12, 30)
    default:
        nil
    }
}
