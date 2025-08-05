import SwiftUI

struct TotalCountView: View {
    let totalCount: Int

    var body: some View {
        VStack {
            Text("Total Count from All Devices")
                .font(.title)
                .padding(.top)

            Text("\(totalCount)")
                .font(.system(size: 75))
                .fontWeight(.bold)
                .padding()
            
        }
        .padding()
        .navigationBarItems(leading: NavigationLink(destination: InformationView()) {
            Image(systemName: "info.circle")
                .foregroundColor(.primary)
                .padding()
        })
    }
}

struct TotalCountView_Previews: PreviewProvider {
    static var previews: some View {
        TotalCountView(totalCount: 0)
    }
}
