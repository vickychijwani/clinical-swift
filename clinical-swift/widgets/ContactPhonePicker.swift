import ContactsUI
import Foundation
import SwiftUI

struct ContactPhonePicker: UIViewControllerRepresentable {
    var onPick: (_ phone: String, _ contactName: String?) -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator

        // Only show/select phone numbers
        picker.displayedPropertyKeys = [CNContactPhoneNumbersKey]
        picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
        picker.predicateForSelectionOfContact = NSPredicate(value: false)
        picker.predicateForSelectionOfProperty =
            NSPredicate(format: "key == %@", CNContactPhoneNumbersKey)

        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context)
    {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onPick: (_ phone: String, _ contactName: String?) -> Void

        init(onPick: @escaping (_ phone: String, _ contactName: String?) -> Void) {
            self.onPick = onPick
        }

        func contactPicker(
            _ picker: CNContactPickerViewController,
            didSelect contactProperty: CNContactProperty
        ) {
            guard
                let phone = contactProperty.value as? CNPhoneNumber
            else { return }

            onPick(phone.stringValue, contactProperty.contact.formattedName)
        }
    }
}

extension CNContact {
    var formattedName: String? {
        var components = PersonNameComponents()
        components.namePrefix = namePrefix
        components.givenName = givenName
        components.middleName = middleName
        components.familyName = familyName
        components.nameSuffix = nameSuffix

        return components.formatted().nilIfBlank
            ?? organizationName.nilIfBlank
    }
}
