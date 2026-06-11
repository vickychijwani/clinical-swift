import Foundation

let samplePatients: [Patient] = {
    return [
        Patient(
            name: nil,
            phone: "+91 98201 44532",
            dob: Date.now.setTime(0, 0),
            gender: .male,
            nextAppointmentDate: Date.now.setTime(18, 30),
            createdDate: Date.now.setTime(9, 0)
        ),
        Patient(
            name: nil,
            phone: "+91 98209 46617",
            dob: nil,
            gender: .female,
            nextAppointmentDate: nil,
            createdDate: Date.now.setTime(17, 45)
        ),
        Patient(
            name: "Aarav Mehta",
            phone: "+91 98201 44532",
            dob: Date(timeIntervalSinceReferenceDate: -459_561_600),
            gender: .male,
            nextAppointmentDate: Date.now.setTime(10, 0)
        ),
        Patient(
            name: "Anjali Desai",
            phone: "+91 98209 46617",
            dob: Date(timeIntervalSinceReferenceDate: -711_244_800),
            gender: .female,
            nextAppointmentDate: Date.now.setTime(12, 30)
        ),
        Patient(
            name: "Arjun Sethi",
            phone: "+91 98100 60234",
            dob: nil,
            gender: .male,
            nextAppointmentDate: nil
        ),
        Patient(
            name: "Dev Malhotra",
            phone: "+91 98920 13472",
            dob: Date(timeIntervalSinceReferenceDate: 282_096_000),
            gender: .male,
            nextAppointmentDate: nil
        ),
        Patient(
            name: "Ishaan Verma",
            phone: "+91 98112 55309",
            dob: Date(timeIntervalSinceReferenceDate: 408_240_000),
            gender: nil,
            nextAppointmentDate: nil
        ),
    ]
}()
