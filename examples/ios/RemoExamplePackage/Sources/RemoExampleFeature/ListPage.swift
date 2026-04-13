import SwiftUI
import RemoSwift

struct ListPage: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        NavigationStack {
            Group {
                if store.items.isEmpty {
                    ContentUnavailableView(
                        "No Items",
                        systemImage: "tray",
                        description: Text("Replace the shared items state to repopulate this demo list.")
                    )
                } else {
                    List {
                        ForEach(store.items, id: \.self) { item in
                            NavigationLink(item) {
                                DetailPage(item: item)
                            }
                        }
                        .onDelete { indexSet in
                            withAnimation { store.items.remove(atOffsets: indexSet) }
                        }
                    }
                    .animation(.default, value: store.items)
                }
            }
            .navigationTitle("Items (\(store.items.count))")
            .toolbar {
                if !store.items.isEmpty {
                    Button("Clear") {
                        withAnimation { store.items.removeAll() }
                    }
                }
            }
        }
    }
}

struct DetailPage: View {
    let item: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "cube.box")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(item)
                .font(.title)
            Text("Detail view for \(item)")
                .foregroundStyle(.secondary)
        }
        .navigationTitle(item)
        .task {
            await #Remo {
                struct DetailInfoResponse: Encodable {
                    let item: String
                }

                enum DetailGetInfo: RemoCapability {
                    static let name = "detail.getInfo"
                    typealias Response = DetailInfoResponse
                }

                await #remoScope {
                    #remoCap(DetailGetInfo.self) { [item] _ in
                        return DetailInfoResponse(item: item)
                    }
                }
            }
        }
    }
}
