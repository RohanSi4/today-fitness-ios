//
//  ContentView.swift
//  Health Tracker
//
//  Created by Rohan Singh on 6/17/25.
//

import SwiftUI
import HealthKit


struct HealthAppView: View {
    @State var selectedTab = "Home"
    
    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
            .tag("Home")
            .tabItem {
                Image(systemName: "house")
                }
            
            ContentView()
                .tag("Content")
                .tabItem {
                    Image(systemName: "person")
                }
            
            ActivityCard()
                .tag( "Activity")
                .tabItem {
                    Image(systemName: "bed.double")
                }
            
        }
        
    }
        
}




#Preview {
    HealthAppView()
}
