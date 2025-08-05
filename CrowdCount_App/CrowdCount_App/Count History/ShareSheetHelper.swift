import UIKit

class CSVActivityItemProvider: NSObject, UIActivityItemSource, @unchecked Sendable {
    let fileData: Data
    let fileName: String

    init(fileData: Data, fileName: String) {
        self.fileData = fileData
        self.fileName = fileName
        super.init()
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return fileData
    }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        return fileData
    }

    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        return fileName
    }

    func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
        return "public.comma-separated-values-text"
    }
}

func presentShareSheet(data: Data, fileName: String, from viewController: UIViewController) {
    let itemProvider = CSVActivityItemProvider(fileData: data, fileName: fileName)
    let activityViewController = UIActivityViewController(activityItems: [itemProvider], applicationActivities: nil)
    activityViewController.popoverPresentationController?.sourceView = viewController.view

    DispatchQueue.main.async {
        viewController.present(activityViewController, animated: true, completion: nil)
    }
}
