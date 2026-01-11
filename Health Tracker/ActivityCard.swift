//
//  ActivityCard.swift
//  Health Tracker
//
//  Created by Rohan Singh on 6/17/25.
//

import SwiftUI

struct ActivityCard: View {
    var body: some View {
        VStack {
            HStack(alignment: .top){
                VStack {
                    Text("Sleep")
                    Text("Total Hrs")
                }
                
                
                Spacer()
                
                Image(systemName: "bed.double.fill")
                    .foregroundColor(.blue)
            }
            .padding()
            
            Text("8.00")
                .font(.system(size:30))
        }
    }
}

struct ActivityCard_Previews: PreviewProvider {
    static var previews: some View {
        ActivityCard()
    }
}
