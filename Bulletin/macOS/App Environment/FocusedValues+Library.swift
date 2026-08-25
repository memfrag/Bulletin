//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

extension FocusedValues {

    /// The reading session belonging to the focused window.
    ///
    /// Menu commands live outside any view hierarchy, so this is how they reach
    /// the window they apply to.
    @Entry var library: Library?
}
