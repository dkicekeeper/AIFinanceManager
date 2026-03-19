# UI Components & Design System Guide

> Reference for Claude: which components to use, where, and how.

---

## Table of Contents

1. [Design Tokens](#1-design-tokens)
2. [View Modifiers](#2-view-modifiers)
3. [Shared Components](#3-shared-components)
4. [View Patterns](#4-view-patterns)
5. [Decision Trees](#5-decision-trees)
6. [Formatting & Display](#6-formatting--display)
7. [Haptics](#7-haptics)
8. [Remaining Native Form Views](#8-remaining-native-form-views)

---

## 1. Design Tokens

All tokens live in `Utils/`. Never use raw values — always reference the token.

### Colors (`AppColors`)

| Token | Value | Use For |
|-------|-------|---------|
| `backgroundPrimary` | `.systemBackground` | Screen backgrounds |
| `surface` / `cardBackground` | `.secondarySystemBackground` | Card fill (pre-iOS 26 fallback) |
| `secondaryBackground` | `.systemGray5` | Secondary surfaces, card backgrounds |
| `textPrimary` | `.primary` | Main text |
| `textSecondary` | `.secondary` | Subtitles, metadata |
| `textSecondaryAccessible` | Custom adaptive | WCAG AA 4.5:1 secondary text |
| `textTertiary` | `.gray` | Hints, placeholders |
| `accent` | `.blue` | Interactive elements, links |
| `destructive` | `.red` | Delete, errors |
| `success` | `.green` | Positive feedback |
| `warning` | `.orange` | Caution feedback |
| `income` | `.green` | Income amounts |
| `expense` | `.primary` | Expense amounts |
| `transfer` | Cyan-teal | Internal transfer amounts |
| `planned` | `.blue` | Future/planned transactions |
| `divider` | `.separator` | Row dividers |
| `border` | `.systemGray4` | Input borders, selection rings |
| `statusActive` | `success` | Active entity badge |
| `statusPaused` | `warning` | Paused entity badge |
| `statusArchived` | `.systemGray` | Archived entity badge |

**Category colors:** Use `CategoryColors.hexColor(for:opacity:customCategories:)` — 14-color hex palette with custom category override.

### Spacing (`AppSpacing`)

4pt grid system:

| Token | Value | Use For |
|-------|-------|---------|
| `xxs` | 2 | Minimum micro spacing |
| `xs` | 4 | Icon-to-text inline gaps |
| `compact` | 6 | Tight chip/button padding |
| `sm` | 8 | Row vertical padding, small gaps |
| `md` | 12 | Default VStack/HStack spacing, card internal padding |
| `lg` | 16 | Screen horizontal padding, between-card spacing |
| `xl` | 20 | Between major sections |
| `xxl` | 24 | Between screen sections |
| `xxxl` | 32 | Large screen margins |

**Semantic aliases:** `pageHorizontal` (16), `sectionVertical` (24), `cardPadding` (12), `listRowSpacing` (8), `iconText` (4), `labelValue` (12).

### Corner Radius (`AppRadius`)

| Token | Value | Use For |
|-------|-------|---------|
| `xs` | 4 | Badges, indicators |
| `compact` | 6 | Compact chips |
| `sm` / `chip` | 8 | Chips, small buttons |
| `md` / `card` / `button` | 10 | Standard cards and buttons |
| `lg` / `sheet` | 12 | Large cards, sheets |
| `xl` | 20 | Pills, filter chips, `.cardStyle()` default |
| `circle` | `.infinity` | Avatars, icon backgrounds |

### Icon Sizes (`AppIconSize`)

| Token | Value | Use For |
|-------|-------|---------|
| `xs` | 12 | Micro icons |
| `indicator` | 14 | Small dots/badges |
| `sm` | 16 | Inline icons in text |
| `md` | 20 | Toolbar, list default |
| `lg` | 24 | Emphasized list icons, `UniversalRow` leading icons |
| `xl` | 32 | Bank logos in rows |
| `avatar` | 40 | Subscription icons in rows |
| `xxl` | 44 | Category circles (QuickAdd) |
| `categoryIcon` | 52 | Category row icons |
| `fab` | 56 | Floating action buttons |
| `coin` | 64 | Category coins |
| `budgetRing` | 72 | Budget ring |
| `largeButton` | 80 | Voice input button |

### Container Sizes (`AppSize`)

Key tokens: `rowHeight` (60), `chartHeightLarge` (200), `chartHeightSmall` (80), `skeletonHeight` (16), `cursorHeight` (36), `cursorHeightLarge` (44), `buttonSmall` (40), `buttonMedium` (56), `buttonLarge` (64).

### Typography (`AppTypography`)

All use Inter variable font with Dynamic Type scaling:

| Token | Size | Weight | Use For |
|-------|------|--------|---------|
| `h1` / `screenTitle` | 34 | bold | Screen titles |
| `h2` | 28 | semibold | Detail view balances |
| `h3` | 24 | semibold | Section titles (Insights) |
| `h4` | 20 | semibold | Card headers, `EmptyStateView` titles |
| `bodyEmphasis` | 18 | medium | Row names, button labels, section subheaders |
| `body` / `bodyPrimary` | 18 | regular | Default text |
| `bodySmall` / `bodySecondary` | 16 | regular | Secondary text, subtitles |
| `label` | 16 | medium | Form labels |
| `amount` | 18 | semibold | Inline amounts |
| `caption` / `sectionHeader` | 14 | regular/medium | Timestamps, metadata, section headers |
| `captionEmphasis` | 14 | medium | Important helper text |
| `caption2` | 12 | regular | Non-critical decorative text only |

### Animations (`AppAnimation`)

| Token | Type | Use For |
|-------|------|---------|
| `spring` | response:0.3 damping:0.6 | Bounce effects |
| `contentSpring` | response:0.3 damping:0.7 | Content transitions, toggles |
| `gentleSpring` | response:0.4 damping:0.8 | Smooth value animations, amounts |
| `fast` | 0.1s | Button press |
| `standard` | 0.25s | State changes |
| `slow` | 0.35s | Modals |
| `chartAppearAnimation` | spring(0.55, 0.82) | Chart entrance |
| `chartUpdateAnimation` | spring(0.5, 0.85) | Chart data updates |

All have Reduce Motion-aware variants (`adaptiveSpring`, `fastAnimation`, etc.) that return `.linear(duration: 0)` when enabled.

**`BounceButtonStyle`:** `scaleEffect(0.96)` + `brightness(-0.05)` on press. Apply via `.buttonStyle(.bounce)`.

---

## 2. View Modifiers

### Layout Modifiers (`AppModifiers`)

| Modifier | Effect | When to Use |
|----------|--------|-------------|
| `.cardStyle(radius:)` | Liquid Glass (iOS 26+) or `.ultraThinMaterial` card background. Default radius: `AppRadius.xl` (20pt) | Every card container in detail/list views |
| `.filterChipStyle(isSelected:)` | Glass chip styling with accent tint when selected | Filter buttons, `UniversalFilterButton` |
| `.screenPadding()` | `.padding(.horizontal, AppSpacing.pageHorizontal)` (16pt) | Screen-level horizontal insets |
| `.cardContentPadding()` | `.padding(AppSpacing.cardPadding)` (12pt) | Internal card content padding |
| `.futureTransactionStyle(isFuture:)` | `.opacity(0.55)` when future | Planned/future transaction rows |
| `.chartAppear(delay:)` | Scale(0.94→1.0) + opacity entrance animation | Outermost chart container |

### Button Styles (`AppButton`)

| Style | Visual | Usage |
|-------|--------|-------|
| `.primaryButton(disabled:)` | Full-width, accent background, white text | Primary CTA (save, submit) |
| `.secondaryButton()` | Full-width, secondary background, primary text | Secondary action (cancel, alternative) |
| `.buttonStyle(.bounce)` | Scale 0.96 on press | Interactive card taps |

---

## 3. Shared Components

### Container Components

#### `EditSheetContainer`
**Purpose:** Universal modal edit-sheet shell.

```swift
EditSheetContainer(
    title: String,
    isSaveDisabled: Bool,
    wrapInForm: Bool = true,     // false for hero-style edit views
    onSave: { },
    onCancel: { }
) {
    // Content
}
```

| Mode | `wrapInForm` | Content Structure | Used By |
|------|-------------|-------------------|---------|
| Hero-form | `false` | `ScrollView` → `VStack` → `EditableHeroSection` + `FormSection` | Account, Subscription, Category edit |
| Native form | `true` | `Form` → `Section` groups | Deposit, Loan edit, Payment/Rate forms |

#### `FormSection`
**Purpose:** Groups form rows with optional header/footer.

```swift
FormSection(header: "Settings", footer: nil, style: .card) {
    UniversalRow(config: .standard) { ... }
    Divider()
    MenuPickerRow(...)
}
```

| Style | Background | Use For |
|-------|-----------|---------|
| `.card` | `.cardStyle()` (Liquid Glass) | Default; hero-form sections |
| `.list` | None | Inside `List` |
| `.plain` | None | Raw passthrough |

#### `EditableHeroSection`
**Purpose:** Animated hero section for entity edit views.

```swift
EditableHeroSection(
    iconSource: $iconSource,
    title: $name,
    balance: $balance,        // only if config.showBalance
    currency: $currency,      // only if config.showCurrency
    selectedColor: $colorHex, // only if config.showColorPicker
    titlePlaceholder: "Name",
    config: .accountHero
)
```

| Preset | Shows |
|--------|-------|
| `.accountHero` | Balance + Currency |
| `.categoryHero` | Color picker |
| `.subscriptionHero` | Balance + Currency |

---

### Row Components

#### `UniversalRow`
**The atomic building block for ALL form rows.** Every row inside `FormSection(.card)` must use it.

```swift
UniversalRow(
    config: .standard,
    leadingIcon: .sfSymbol("star", color: .blue, size: .lg)
) {
    Text("Label").font(AppTypography.body)
} trailing: {
    Text("Value").font(AppTypography.bodySmall)
}
```

**Configurations:**

| Preset | V-Padding | H-Padding | Context |
|--------|-----------|-----------|---------|
| `.standard` | 8 | 12 | Form rows in `FormSection` |
| `.settings` | 4 | 0 | Settings list rows |
| `.selectable` | 8 | 12 | Checkmark selection lists |
| `.sheetList` | 8 | 16 | Modal selection sheets |
| `.info` | 6 | 12 | Read-only label+value |

**IconConfig factories:**

```swift
.sfSymbol("star", color: .blue, size: .lg)  // SF Symbol with color
.bankLogo(.kaspi, size: .xl)                 // Bank logo
.brandService("netflix", size: .xl)          // Brand service icon
.custom(source: iconSource, style: style)    // Custom IconSource + IconStyle
```

**Interaction modifiers:**

```swift
row.navigationRow { DetailView() }           // NavigationLink wrapper
row.actionRow(role: .destructive) { delete() } // Button wrapper
row.selectableRow(isSelected: true) { select() } // Tap gesture wrapper
```

#### `InfoRow`
Read-only label + value. Wrapper for `UniversalRow(config: .info)`.

```swift
InfoRow(icon: "calendar", label: "Next Payment", value: "March 15, 2026")
```

Use in: detail views for metadata display. NOT for editable fields.

#### `MenuPickerRow`
In-form single-select picker with dropdown menu.

```swift
MenuPickerRow(
    icon: "arrow.triangle.2.circlepath",
    title: "Frequency",
    selection: $frequency,
    options: [("Monthly", .monthly), ("Weekly", .weekly)]
)
```

Use in: form sections for frequency, period, reminder, etc.

#### `DatePickerRow`
Inline `DatePicker` inside `UniversalRow`.

```swift
DatePickerRow(icon: "calendar", title: "Start Date", selection: $startDate)
```

Use in: subscription/deposit/loan form sections. NOT for transaction dates (use `DateButtonsView`).

#### `BudgetSettingsSection`
Pre-built budget config card: amount + period + reset day.

```swift
BudgetSettingsSection(
    budgetAmount: $budgetAmount,
    selectedPeriod: $period,
    resetDay: $resetDay
)
```

Use in: `CategoryEditView` only.

---

### Icon Components

#### `IconView`
**The single rendering engine for all entity icons.**

```swift
// Auto-style (convenience)
IconView(source: .sfSymbol("star.fill"), size: AppIconSize.xl)

// Explicit style
IconView(source: .bankLogo(.kaspi), style: .bankLogo(size: AppIconSize.xl))
```

**When to use `IconView`:** Entity/category icons with styled backgrounds — accounts, categories, subscriptions, brand logos.

**When to use `Image(systemName:)` directly:** Semantic UI indicators — chevron, checkmark, xmark, toolbar actions, inline arrows.

**IconStyle presets:**

| Preset | Shape | Context |
|--------|-------|---------|
| `.categoryIcon(size:)` | Circle, accent tint | Category rows, chips |
| `.categoryCoin(size:)` | Circle, surface bg | Large category coins |
| `.bankLogo(size:)` | RoundedSquare, md radius | Account rows |
| `.bankLogoLarge(size:)` | RoundedSquare, lg radius | Account cards |
| `.serviceLogo(size:)` | RoundedSquare, md radius | Subscription cards |
| `.serviceLogoLarge(size:)` | RoundedSquare, lg radius | Subscription detail |
| `.placeholder(size:)` | Circle, secondary tint | Nil source fallback |
| `.glassHero(size:)` | Circle + glass | Detail view hero |
| `.glassService(size:)` | RoundedSquare + glass | Service hero |
| `.inline(tint:)` | Small circle | Text fields, chips |
| `.toolbar(tint:)` | Medium circle | Toolbar buttons |
| `.emptyState()` | XL circle | Empty state illustration |

---

### Carousel & Filter Components

#### `UniversalCarousel`
**The only horizontal scroll container. Never create raw `ScrollView(.horizontal) { HStack {} }`.**

```swift
UniversalCarousel(config: .filter) {
    ForEach(items) { item in
        UniversalFilterButton(title: item.name, isSelected: item.isSelected) { ... }
    }
}
```

| Preset | Spacing | H-Padding | Use For |
|--------|---------|-----------|---------|
| `.standard` | 12 | 16 | Account carousel, general horizontal lists |
| `.compact` | 8 | 8 | Color picker, tight grids |
| `.filter` | 12 | 16 | Filter chip rows |
| `.cards` | 12 | 0 | Edge-to-edge cards (apply `.screenPadding()` externally) |
| `.csvPreview` | 8 | 12 | CSV column preview (shows indicators) |

#### `UniversalFilterButton`
Filter chip in two modes.

```swift
// Button mode
UniversalFilterButton(title: "This Month", isSelected: true) { selectPeriod() }

// Menu mode
UniversalFilterButton(title: "Account", isSelected: hasFilter) {
    Button("All Accounts") { clearFilter() }
    ForEach(accounts) { acc in
        Button(acc.name) { selectAccount(acc) }
    }
}
```

---

### Input Components

#### `FormTextField`
Enhanced text field with error/help states.

```swift
FormTextField(
    text: $name,
    placeholder: "Enter name",
    style: .standard,         // or .multiline(min: 2, max: 6), .compact
    errorMessage: nameError,
    helpText: "Required field"
)
```

Use for: text inputs inside `FormSection`. NOT for amounts (use `AnimatedAmountInput`) or hero titles (use `AnimatedTitleInput`).

#### `AnimatedAmountInput`
Hero-style large formatted amount with `.numericText()` transition.

```swift
AnimatedAmountInput(amount: $amountString, baseFontSize: 48, color: .primary)
```

Use in: `EditableHeroSection` balance fields. NOT for compact form rows.

#### `AnimatedTitleInput`
Hero-style name input with `.interpolate` character transition.

```swift
AnimatedTitleInput(text: $name, placeholder: "Account Name", font: AppTypography.h1)
```

Use in: `EditableHeroSection` title fields only.

#### `DateButtonsView`
Yesterday / Today / Calendar picker for transaction forms.

```swift
// As safe-area bottom bar:
.dateButtonsSafeArea(selectedDate: $date, onSave: { saveDate($0) })
```

Use for: transaction entry/edit forms only. For other date fields use `DatePickerRow`.

#### `CurrencySelectorView`
Currency symbol menu button styled as filter chip.

```swift
CurrencySelectorView(selectedCurrency: $currency, availableCurrencies: ["KZT", "USD", "EUR"])
```

Use in: `EditableHeroSection` (automatic when `config.showCurrency`). Not standalone.

---

### Feedback & Status Components

#### `MessageBanner`
Transient animated feedback banner.

```swift
MessageBanner.success("Saved successfully")
MessageBanner.error("Failed to load")
MessageBanner.warning("Low balance")
MessageBanner.info("Sync completed")
```

Show conditionally: `if showBanner { MessageBanner.success("...") }` inside `.animation {}` block. Overlay above main content in `ZStack`.

#### `InlineStatusText`
Persistent inline validation/hint text.

```swift
InlineStatusText(message: "Amount must be positive", type: .error)
```

Use for: persistent form validation. NOT for transient post-action feedback (use `MessageBanner`).

#### `StatusIndicatorBadge`
Entity lifecycle status icon.

```swift
StatusIndicatorBadge(status: .active, font: AppTypography.h4)
```

Cases: `.active` (green checkmark), `.paused` (orange pause), `.archived` (gray archive), `.pending` (blue clock).

#### `EmptyStateView`
Empty/error state display.

```swift
EmptyStateView(
    icon: "tray",
    title: "No Transactions",
    description: "Add your first transaction to get started",
    actionTitle: "Add Transaction",
    action: { showAdd = true },
    style: .standard  // or .compact, .error
)
```

| Style | Context |
|-------|---------|
| `.standard` | Full-screen empty state (management views) |
| `.compact` | Inside cards (home summary) |
| `.error` | Load failures (with pulse icon + retry) |

---

### Display Components

#### `FormattedAmountText`
Currency amount with smart decimal hiding and numeric transition.

```swift
FormattedAmountText(
    amount: 1234.56,
    currency: "KZT",
    prefix: "-",
    fontSize: AppTypography.h2,
    fontWeight: .semibold,
    color: AppColors.expense
)
```

Use for: ALL display-only amounts — detail view balances, row subtitles, card totals, section headers.

#### `SectionHeaderView`
Section header text with four styles.

```swift
SectionHeaderView("Transactions", style: .default)       // bodyEmphasis
SectionHeaderView("March 10", style: .emphasized)         // bodySmall semibold
SectionHeaderView("SETTINGS", style: .compact)            // caption uppercase
SectionHeaderView("Spending", systemImage: "chart.bar", style: .insights) // h3 + icon
```

#### `DateSectionHeaderView`
Transaction list date group header with optional daily total.

```swift
DateSectionHeaderView(dateKey: "2026-03-10", amount: 45000.0, currency: "KZT")
```

#### `BudgetProgressCircle`
Circular progress arc for budget consumption.

```swift
BudgetProgressCircle(progress: 0.75, size: AppIconSize.categoryIcon, isOverBudget: false)
```

---

### Content Reveal (Loading Transitions)

#### `.contentReveal(isReady:delay:)`
Fades content in when `isReady` becomes true. Preserves view identity (no `if/else` branching).
Optional `delay` staggers multiple sections for a smooth cascading reveal.

```swift
// Single section
accountsSection
    .contentReveal(isReady: coordinator.isFastPathDone)

// Staggered reveal — sections fade in 50ms apart
historySection
    .contentReveal(isReady: coordinator.isFullyInitialized)
subscriptionsSection
    .contentReveal(isReady: coordinator.isFullyInitialized, delay: 0.05)
loansSection
    .contentReveal(isReady: coordinator.isFullyInitialized, delay: 0.1)
```

**Why not skeletons?** The previous `SkeletonLoadingModifier` used `if/else` branching which destroyed view identity — causing shimmer animation failures, UI jerk on content reveal, and layout recalculation spikes when multiple sections materialized simultaneously. `ContentRevealModifier` keeps content always in the hierarchy (just invisible) and uses simple opacity fade.

---

## 4. View Patterns

### Edit View — Hero Style
Used by: `AccountEditView`, `SubscriptionEditView`, `CategoryEditView`, `DepositEditView`, `LoanEditView`

```
EditSheetContainer(wrapInForm: false)
└── ScrollView
    └── VStack(spacing: AppSpacing.xl)
        ├── EditableHeroSection(config: .accountHero)  // icon + title + balance
        ├── FormSection(.card, header: "Details") {
        │   ├── UniversalRow { ... }
        │   ├── Divider()
        │   ├── MenuPickerRow(...)
        │   ├── Divider()
        │   └── DatePickerRow(...)
        │   }
        └── FormSection(.card, header: "More") { ... }
```

### Edit View — Native Form
Used by: `LoanPaymentView`, `LoanRateChangeView`, `LoanEarlyRepaymentView`, `DepositRateChangeView`

```
EditSheetContainer(wrapInForm: true)
└── Form (auto-wrapped)
    ├── Section(header: "Basic Info") {
    │   ├── TextField(...)
    │   ├── Picker(...)
    │   └── Toggle(...)
    │   }
    ├── Section(header: "Details") {
    │   ├── DatePicker(...)
    │   └── TextField(...)
    │   }
    └── InlineStatusText(...)  // validation below sections
```

### Detail View
Used by: `SubscriptionDetailView`, `DepositDetailView`, `LoanDetailView`

```
ScrollView
└── VStack(spacing: AppSpacing.lg)
    ├── Card 1: Header (.cardStyle())
    │   └── IconView(.glassHero) + Title + Balance
    ├── Card 2: Info (.cardStyle())
    │   └── InfoRow list
    ├── Card 3: Stats (.cardStyle())
    │   └── InfoRow / custom rows
    ├── Actions Section
    │   ├── Button { }.primaryButton()
    │   └── Button { }.secondaryButton()
    └── .toolbar { Menu("...") { edit, delete, ... } }
```

Cards use staggered `.chartAppear(delay:)` for entrance animation.

### List View — Management
Used by: `AccountsManagementView`, `CategoriesManagementView`

```
List {
    ForEach(items) { item in
        CustomRow(item)
            .swipeActions(edge: .trailing) { delete }
    }
    .onMove { reorder }
}
.toolbar { Button("Add") { showAddSheet = true } }
.sheet(isPresented: $showAddSheet) { EditView() }
```

### List View — Scrollable Cards
Used by: `SubscriptionsListView`, `LoansListView`

```
ScrollView
└── VStack(spacing: AppSpacing.lg)
    ├── Optional summary card (.cardStyle())
    └── ForEach(items) { item in
            NavigationLink(value: destination) {
                ItemCard()
            }
            .chartAppear(delay: index * 0.05)
        }
```

### Transaction List (History)
```
List {
    ForEach(sections.prefix(visibleSectionLimit)) { section in
        Section {
            ForEach(section.transactions) { tx in
                TransactionCard(transaction: tx, styleData: preComputed, ...)
            }
        } header: {
            DateSectionHeaderView(dateKey: section.dateKey, amount: total, currency: cur)
        }
    }
    // Infinite scroll trigger
    if visibleSectionLimit < sections.count {
        ProgressView().onAppear { visibleSectionLimit += 100 }
    }
}
```

### Settings
```
List {
    SettingsGeneralSection(...)
    SettingsDataManagementSection(...)
    SettingsExportImportSection(...)
    SettingsDangerZoneSection(...)
}
```

Each section uses `UniversalRow(config: .settings)` with `.navigationRow {}` or `.actionRow(role:) {}`.

### Home Screen (Dashboard)
```
ScrollView
└── VStack(spacing: AppSpacing.lg)
    ├── AccountsCarousel (UniversalCarousel)
    ├── TransactionsSummaryCard (3-state: loading/empty/data)
    ├── CategoryGridView (adaptive grid of category chips)
    ├── SubscriptionsCardView (.cardStyle())
    └── LoansCardView (.cardStyle())
```

---

## 5. Decision Trees

### "Which input component?"

```
Amount input?
├── Hero-style (large, animated) → AnimatedAmountInput
└── Compact form row → FormTextField(keyboardType: .decimalPad)

Text input?
├── Hero title (large, animated) → AnimatedTitleInput
├── Multiline description → FormTextField(style: .multiline(min:max:))
└── Single-line form field → FormTextField(style: .standard)

Date input?
├── Transaction (needs Yesterday/Today shortcuts) → DateButtonsView / .dateButtonsSafeArea()
└── Other (subscription start, deposit posting) → DatePickerRow

Single-select picker?
├── Few options (2-5) in form → MenuPickerRow
├── 2-4 exclusive modes → SegmentedPickerView
└── Many options → NavigationLink to selection list

Currency?
└── CurrencySelectorView (inside EditableHeroSection, automatic)
```

### "Which row component?"

```
Inside FormSection(.card)?
└── Always use UniversalRow(config: .standard)
    ├── Read-only label+value → InfoRow (wrapper)
    ├── Picker → MenuPickerRow (wrapper)
    ├── Date → DatePickerRow (wrapper)
    └── Custom content → UniversalRow directly

Inside List (settings)?
└── UniversalRow(config: .settings)
    ├── With navigation → .navigationRow { }
    ├── With action → .actionRow(role:) { }
    └── With toggle → trailing: { Toggle(...) }

Transaction list row?
└── TransactionCard (NOT UniversalRow)

Account list row?
└── AccountRow (custom, NOT UniversalRow)
```

### "Which container?"

```
Modal edit form?
└── EditSheetContainer
    ├── Entity edit (account/category/subscription/deposit/loan) → wrapInForm: false (hero-form)
    └── Simple action form (payment, rate change) → wrapInForm: true

Grouping form rows?
├── Inside hero-form → FormSection(.card)
├── Inside native Form → Section(header:)
└── Inside List → FormSection(.list) or Section

Horizontal scroll?
└── UniversalCarousel with appropriate preset

Card-style container?
└── VStack { ... }.cardStyle()
```

### "Which icon approach?"

```
Entity icon with styled background?
└── IconView(source:style:)
    ├── Account → .bankLogo(size:) or .bankLogoLarge(size:)
    ├── Category → .categoryIcon(size:) or .categoryCoin(size:)
    ├── Subscription → .serviceLogo(size:) or .glassHero(size:)
    └── Nil/unknown → .placeholder(size:)

Semantic UI indicator?
└── Image(systemName:) directly
    Examples: chevron.right, checkmark, xmark, plus, ellipsis
```

### "Which feedback component?"

```
Transient post-action result?
└── MessageBanner (.success/.error/.warning/.info)

Persistent form validation?
└── InlineStatusText (.error/.warning/.info/.success)

Entity lifecycle status?
└── StatusIndicatorBadge (.active/.paused/.archived/.pending)

No data to show?
└── EmptyStateView
    ├── Full screen → .standard
    ├── Inside card → .compact
    └── Error/failure → .error
```

---

## 6. Formatting & Display

### Amount Formatting

| Context | Function | Decimals |
|---------|----------|----------|
| Display (smart) | `Formatting.formatCurrencySmart(_:currency:)` | 0 or 2 |
| Display (always .00) | `Formatting.formatCurrency(_:currency:)` | Always 2 |
| Storage/validation | `AmountFormatter.format(_:)` / `.parse(_:)` | Always 2 |
| Input component | `AmountInputFormatting.displayAmount(for:)` | 0-2 |
| List/ForEach hot path | `AmountDisplayConfiguration.formatter` (cached) | Configured |

**Never call `AmountDisplayConfiguration.makeNumberFormatter()` in List/ForEach** — use `.formatter` (cached).

### Currency Symbols

```swift
Formatting.currencySymbol(for: "KZT") // → "₸"
```

Supported: KZT→₸, USD→$, EUR→€, RUB→₽, GBP→£, CNY→¥, JPY→¥. Unknown → code string.

### Transaction Amount Color/Prefix

```swift
TransactionDisplayHelper.amountColor(for: .income)   // → .green
TransactionDisplayHelper.amountPrefix(for: .expense)  // → "-"
```

Deposit-aware overloads accept `targetAccountId`, `depositAccountId`, `isPlanned`.

### Date Formatting

| Formatter | Format | Use For |
|-----------|--------|---------|
| `DateFormatters.dateFormatter` | `yyyy-MM-dd` | Storage, parsing |
| `DateFormatters.displayDateFormatter` | `d MMMM` | Display ("10 March") |
| `DateFormatters.displayDateWithYearFormatter` | `d MMMM yyyy` | Display with year |
| `DateFormatters.timeFormatter` | `HH:mm` | Time display |

### Category Styling

Pre-compute at ForEach call site, not inside row views:

```swift
let styleData = CategoryStyleHelper.cached(
    category: tx.category,
    type: tx.type,
    customCategories: customCategories
)
// Pass styleData (Equatable struct) to TransactionCard
```

`CategoryStyleCache.shared` handles caching. Invalidate on category edit via `.invalidateCategory(_:type:)`.

---

## 7. Haptics

Use `HapticManager` for all haptic feedback:

| Event | Call |
|-------|------|
| Navigation tap, filter change | `HapticManager.selection()` |
| Sheet open, picker tap | `HapticManager.light()` |
| Save/confirm success | `HapticManager.success()` |
| Destructive action initiation | `HapticManager.warning()` |
| Validation failure | `HapticManager.error()` |
| Drag/reorder | `HapticManager.medium()` |

View modifier: `.hapticFeedback(.light)` attaches tap gesture haptic.

---

## 8. Remaining Native Form Views

The following views still use `EditSheetContainer(wrapInForm: true)` with native `Form`/`Section`. This is intentional — they are simple single-purpose forms (payment entry, rate change) where hero-style UI would be overkill:

- `LoanPaymentView` — single amount + date entry
- `LoanRateChangeView` — single rate + date entry
- `LoanEarlyRepaymentView` — amount + type selection
- `DepositRateChangeView` — single rate + date entry

All primary entity edit views (`Account`, `Subscription`, `Category`, `Deposit`, `Loan`) now use the hero-form pattern consistently.

---

*Last Updated: 2026-03-10*
