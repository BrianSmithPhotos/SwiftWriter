import PostKit
import SwiftUI

struct PostEditor: View {
    @Bindable var document: PostDocument

    var body: some View {
        Text(document.post.title)
            .padding()
    }
}
