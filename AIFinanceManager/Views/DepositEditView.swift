//
//  DepositEditView.swift
//  AIFinanceManager
//
//  View for creating and editing deposits
//

import SwiftUI

struct DepositEditView: View {
    @ObservedObject var viewModel: TransactionsViewModel
    let account: Account?
    let onSave: (Account) -> Void
    let onCancel: () -> Void
    
    @State private var name: String = ""
    @State private var bankName: String = ""
    @State private var principalBalanceText: String = ""
    @State private var currency: String = "KZT"
    @State private var selectedBankLogo: BankLogo = .none
    @State private var interestRateText: String = ""
    @State private var interestPostingDay: Int = 1
    @State private var capitalizationEnabled: Bool = true
    @State private var showingBankLogoPicker = false
    @FocusState private var isNameFocused: Bool
    
    private let depositCurrencies = ["KZT", "USD", "EUR"]
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Название депозита")) {
                    TextField("Название", text: $name)
                        .focused($isNameFocused)
                }
                
                Section(header: Text("Банк")) {
                    TextField("Название банка", text: $bankName)
                    
                    Button(action: { showingBankLogoPicker = true }) {
                        HStack {
                            Text("Выбрать логотип")
                            Spacer()
                            selectedBankLogo.image(size: 24)
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                }
                
                Section(header: Text("Валюта")) {
                    Picker("Валюта", selection: $currency) {
                        ForEach(depositCurrencies, id: \.self) { curr in
                            Text("\(Formatting.currencySymbol(for: curr)) \(curr)").tag(curr)
                        }
                    }
                }
                
                Section(header: Text("Начальная сумма")) {
                    TextField("0.00", text: $principalBalanceText)
                        .keyboardType(.decimalPad)
                }
                
                Section(header: Text("Процентная ставка")) {
                    HStack {
                        TextField("0.0", text: $interestRateText)
                            .keyboardType(.decimalPad)
                        Text("% годовых")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("День начисления процентов")) {
                    Picker("День месяца", selection: $interestPostingDay) {
                        ForEach(1...31, id: \.self) { day in
                            Text("\(day)").tag(day)
                        }
                    }
                    Text("Если в месяце меньше дней, начисление произойдет в последний день месяца")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section(header: Text("Капитализация")) {
                    Toggle("Включить капитализацию", isOn: $capitalizationEnabled)
                    Text("При включенной капитализации проценты добавляются к основной сумме каждый месяц")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle(account == nil ? "Новый депозит" : "Редактировать депозит")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        guard let principalBalance = AmountFormatter.parse(principalBalanceText),
                              let interestRate = AmountFormatter.parse(interestRateText) else {
                            return
                        }
                        
                        let depositInfo = DepositInfo(
                            bankName: bankName,
                            principalBalance: principalBalance,
                            capitalizationEnabled: capitalizationEnabled,
                            interestRateAnnual: interestRate,
                            interestPostingDay: interestPostingDay
                        )
                        
                        let balance = NSDecimalNumber(decimal: principalBalance).doubleValue
                        let newAccount = Account(
                            id: account?.id ?? UUID().uuidString,
                            name: name,
                            balance: balance,
                            currency: currency,
                            bankLogo: selectedBankLogo,
                            depositInfo: depositInfo
                        )
                        onSave(newAccount)
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(name.isEmpty || bankName.isEmpty || principalBalanceText.isEmpty || interestRateText.isEmpty)
                }
            }
            .onAppear {
                if let account = account, let depositInfo = account.depositInfo {
                    name = account.name
                    bankName = depositInfo.bankName
                    principalBalanceText = String(format: "%.2f", NSDecimalNumber(decimal: depositInfo.principalBalance).doubleValue)
                    currency = account.currency
                    selectedBankLogo = account.bankLogo
                    interestRateText = String(format: "%.2f", NSDecimalNumber(decimal: depositInfo.interestRateAnnual).doubleValue)
                    interestPostingDay = depositInfo.interestPostingDay
                    capitalizationEnabled = depositInfo.capitalizationEnabled
                    isNameFocused = false
                } else {
                    currency = "KZT"
                    selectedBankLogo = .none
                    principalBalanceText = ""
                    interestRateText = ""
                    interestPostingDay = 1
                    capitalizationEnabled = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isNameFocused = true
                    }
                }
            }
            .sheet(isPresented: $showingBankLogoPicker) {
                BankLogoPickerView(selectedLogo: $selectedBankLogo)
            }
        }
    }
}

#Preview {
    NavigationView {
        DepositEditView(
            viewModel: TransactionsViewModel(),
            account: nil,
            onSave: { _ in },
            onCancel: {}
        )
    }
}
