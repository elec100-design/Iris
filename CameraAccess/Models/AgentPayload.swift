import UIKit

enum AgentAttachment {
    case metaCamera(UIImage)
    // Future: case album(UIImage), case iCloud(URL)
}

struct AgentPayload {
    let text: String
    let attachment: AgentAttachment?
}
