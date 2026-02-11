//
//  SkeletonView.swift
//  AIFinanceManager
//
//  Created on 2026
//
//  Skeleton loading view for better UX during data loading

import SwiftUI

/// Simple skeleton view for loading states
struct SkeletonView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: AppRadius.sm)
            .fill(Color.gray.opacity(0.2))
    }
}

// MARK: - Unused skeleton components (kept for reference)
// These were causing image creation errors, so we use simple ProgressView instead

/*
/// Skeleton for account card
struct AccountCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            // Bank logo placeholder
            SkeletonView()
                .frame(width: 40, height: 40)
            
            Spacer()
            
            // Account name
            SkeletonView()
                .frame(height: 16)
                .frame(maxWidth: 100)
            
            // Balance
            SkeletonView()
                .frame(height: 24)
                .frame(maxWidth: 120)
        }
        .padding(AppSpacing.md)
        .frame(width: 200, height: 140)
        .background(Color(.systemBackground))
        .clipShape(.rect(cornerRadius: AppRadius.md))
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}
*/

/*
/// Skeleton for analytics card
struct AnalyticsCardSkeleton: View {
    var body: some View {
        VStack(spacing: AppSpacing.md) {
            HStack {
                SkeletonView()
                    .frame(width: 100, height: max(20, AppSpacing.md))
                Spacer()
            }
            
            HStack(spacing: AppSpacing.lg) {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    SkeletonView()
                        .frame(width: 60, height: max(14, AppSpacing.sm))
                    SkeletonView()
                        .frame(width: 100, height: max(24, AppSpacing.lg))
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                    SkeletonView()
                        .frame(width: 60, height: max(14, AppSpacing.sm))
                    SkeletonView()
                        .frame(width: 100, height: max(24, AppSpacing.lg))
                }
            }
            
            HStack {
                SkeletonView()
                    .frame(width: 80, height: max(14, AppSpacing.sm))
                Spacer()
                SkeletonView()
                    .frame(width: 100, height: max(20, AppSpacing.md))
            }
        }
        .frame(minHeight: 120)
        .padding(AppSpacing.md)
        .background(Color(.systemBackground))
        .clipShape(.rect(cornerRadius: AppRadius.md))
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

/// Loading state for main screen
struct MainScreenLoadingView: View {
    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            // Accounts section skeleton
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.md) {
                    ForEach(0..<3, id: \.self) { _ in
                        AccountCardSkeleton()
                    }
                }
                .padding(.vertical, AppSpacing.xs)
            }
            .frame(height: 160)
            .padding(.horizontal, AppSpacing.md)
            
            // Analytics card skeleton
            AnalyticsCardSkeleton()
                .padding(.horizontal, AppSpacing.md)
            
            // Quick add placeholder
            VStack(spacing: AppSpacing.md) {
                SkeletonView()
                    .frame(height: 20)
                SkeletonView()
                    .frame(height: 50)
            }
            .padding(AppSpacing.md)
            
            Spacer()
        }
        .padding(.vertical, AppSpacing.md)
    }
}
*/

/*
#Preview {
    VStack(spacing: 20) {
        SkeletonView()
            .frame(width: 200, height: 40)
    }
    .padding()
}
*/
