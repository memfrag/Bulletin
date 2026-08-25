//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

struct EmptyPane: View {
    var body: some View {
        Pane {
            ContentUnavailableView {
                Label("No Article Selected", systemImage: "doc.text")
            } description: {
                Text("Select an article to read it.", comment: "Reader empty state")
            }
        }
    }
}

#Preview {
    EmptyPane()
}
