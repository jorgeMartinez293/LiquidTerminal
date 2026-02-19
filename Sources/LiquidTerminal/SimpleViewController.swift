import Cocoa

class SimpleViewController: NSViewController {
    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        self.view.wantsLayer = true
        self.view.layer?.backgroundColor = NSColor.blue.cgColor
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        print("SimpleViewController loaded")
    }
}
