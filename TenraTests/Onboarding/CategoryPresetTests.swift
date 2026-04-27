//
//  CategoryPresetTests.swift
//  TenraTests
//

import Testing
@testable import Tenra

@MainActor
struct CategoryPresetTests {
    @Test func defaultExpenseHas15Entries() {
        #expect(CategoryPreset.defaultExpense.count == 15)
    }

    @Test func allPresetsAreExpenseType() {
        for preset in CategoryPreset.defaultExpense {
            #expect(preset.type == .expense)
        }
    }

    @Test func allPresetsHaveSFSymbol() {
        for preset in CategoryPreset.defaultExpense {
            if case .sfSymbol = preset.iconSource {
                continue
            }
            Issue.record("Preset \(preset.id) is not an SF symbol")
        }
    }

    @Test func allPresetsHaveValidHexColor() {
        for preset in CategoryPreset.defaultExpense {
            #expect(preset.colorHex.hasPrefix("#"))
            #expect(preset.colorHex.count == 7)
        }
    }

    @Test func presetIDsAreUnique() {
        let ids = CategoryPreset.defaultExpense.map { $0.id }
        #expect(Set(ids).count == ids.count)
    }

    @Test func makeSelectableTogglesIsSelected() {
        let preset = CategoryPreset.defaultExpense[0]
        let selected = preset.makeSelectable(isSelected: true)
        #expect(selected.preset.id == preset.id)
        #expect(selected.isSelected == true)
    }
}
