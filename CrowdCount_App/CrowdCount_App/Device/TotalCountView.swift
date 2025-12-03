import SwiftUI

struct TotalCountView: View {
    let totalCount: Int
    let totalOvercrowdingCount: Int
    let users: [User]
    @Binding var userPasswords: [UUID: String]

    var body: some View {
        VStack {
            Spacer()
            Spacer()
            Text("Total Count from All Devices")
                .font(.title)
                .padding(.top)

            HStack {
                Text("\(totalCount)")
                    .font(.system(size: 75))
                    .fontWeight(.bold)
                if totalOvercrowdingCount > 0 {
                    Text("/ \(totalOvercrowdingCount)")
                        .font(.system(size: 75))
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                }
            }
            .padding(10)

            NavigationLink(destination: AggregatedHistoricView(users: users, userPasswords: $userPasswords)) {
                HStack {
                    Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    Text("Count History")
                }
                .padding()
                .background(Color.blue.opacity(0.75))
                .foregroundColor(.primary)
                .cornerRadius(20)
                .padding(.horizontal, 16)
            }
            .padding(.top)
            Spacer()
            Text("Counts and history are aggregated from all of your counters.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
        }
        .padding()
        .navigationBarItems(leading: NavigationLink(destination: InformationView()) {
            Image(systemName: "info")
                .foregroundColor(.primary)
                .padding()
        })
    }
}

struct TotalCountView_Previews: PreviewProvider {
    static var previews: some View {
        TotalCountView(totalCount: 0, totalOvercrowdingCount: 0, users: [], userPasswords: .constant([:]))
    }
}
