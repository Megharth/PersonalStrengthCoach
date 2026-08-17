---
name: Personal Strength Coach
description: A quiet, premium native iOS training companion that makes real progress and recovery context legible.
colors:
  primary: "Color.mint"
  positive: "Color.mint"
  caution: "Color.yellow"
  alert: "Color.red"
  performance: "Color.orange"
  recovery: "Color.indigo"
  heart: "Color.pink"
  neutral-bg: "Color(uiColor: .systemGroupedBackground)"
  neutral-surface: "Color(uiColor: .secondarySystemGroupedBackground)"
  primary-label: "Color.primary"
  secondary-label: "Color.secondary"
  tertiary-label: "Color.tertiary"
  material: ".thinMaterial"
typography:
  display:
    fontFamily: "SF Pro Display / system"
    fontSize: ".largeTitle"
    fontWeight: 700
    lineHeight: "system"
  headline:
    fontFamily: "SF Pro / system"
    fontSize: ".headline"
    fontWeight: 600
    lineHeight: "system"
  title:
    fontFamily: "SF Pro / system"
    fontSize: ".title3"
    fontWeight: 700
    lineHeight: "system"
  body:
    fontFamily: "SF Pro / system"
    fontSize: ".body"
    fontWeight: 400
    lineHeight: "system"
  label:
    fontFamily: "SF Pro / system"
    fontSize: ".caption"
    fontWeight: 400
    lineHeight: "system"
rounded:
  tile: "16pt"
  card: "18pt"
  readiness: "24pt"
spacing:
  compact: "4pt"
  small: "8pt"
  medium: "12pt"
  card: "16pt"
  large: "18pt"
components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "Color.white"
    typography: "{typography.body}"
    rounded: "system borderedProminent"
  metric-card:
    backgroundColor: "{colors.neutral-surface}"
    textColor: "{colors.primary-label}"
    rounded: "{rounded.card}"
    padding: "14pt"
    height: "120pt minimum"
  coach-card:
    backgroundColor: "{colors.neutral-surface}"
    textColor: "{colors.primary-label}"
    rounded: "{rounded.card}"
    padding: "17pt"
  readiness-card:
    backgroundColor: "{colors.material}"
    textColor: "{colors.primary-label}"
    rounded: "{rounded.readiness}"
    padding: "18pt"
  trend-chart:
    backgroundColor: "{colors.neutral-surface}"
    textColor: "{colors.primary-label}"
    rounded: "{rounded.card}"
    padding: "16pt"
    height: "130pt"
---

# Design System: Personal Strength Coach

## Overview

**Creative North Star: "The Recovery Compass"**

Personal Strength Coach should feel like a calm instrument panel for a solo lifter: a trustworthy compass that helps them orient around today's training without competing with the work itself. The interface is native iOS first—quiet, legible, and familiar—while its mint accent gives moments of progress and readiness a distinct signal. The visual system supports the product's core promise of making real history and recovery context understandable, not of manufacturing a spectacle from sparse data.

The tone is quiet and premium. Spacious grouped surfaces, system typography, restrained icon color, and soft tonal separation do the visual work. Density increases where logging requires it, but the surrounding hierarchy remains composed. Use the platform's semantic colors, materials, navigation, lists, forms, sheets, and controls rather than imitating a web dashboard. The confirmed anti-reference is fake dashboards: decorative metrics, unsupported precision, and chart ornament without meaningful history are out of character.

**Key Characteristics:**
- Native iOS fluency over bespoke chrome.
- Calm, dark-mode-first tonal layering with one mint signal.
- Progress and recovery presented as honest, contextual guidance.
- Compact task surfaces balanced by generous review surfaces.

## Colors

The palette is semantic rather than hex-driven. The source of truth is SwiftUI/UIKit system color behavior, so colors adapt to Dark Mode, contrast settings, and the platform appearance. Mint is the product signal; other hues identify distinct training or recovery meanings and should not become decoration.

### Primary
- **Training Mint** (`Color.mint`): The single interactive and progress accent. Use for the app tint, completed states, readiness-positive states, progression lines, and primary emphasis.

### Secondary
- **Performance Orange** (`Color.orange`): Estimated 1RM and performance-oriented metric iconography.
- **Recovery Indigo** (`Color.indigo`): Sleep and recovery-duration context.
- **Heart Pink** (`Color.pink`): HRV and physiologic recovery context.

### Tertiary
- **Caution Yellow** (`Color.yellow`): Personal-record indicators and caution/recovering states.
- **Alert Red** (`Color.red`): Fatigued, destructive, or explicitly negative states only.

### Neutral
- **Grouped Background** (`Color(uiColor: .systemGroupedBackground)`): The page canvas behind scrollable content.
- **Grouped Surface** (`Color(uiColor: .secondarySystemGroupedBackground)`): Cards, metric tiles, coach messages, and other contained surfaces.
- **Primary Label** (`Color.primary`): Main titles, values, and actionable content.
- **Secondary Label** (`Color.secondary`): Supporting dates, units, explanations, and lower-priority metadata.
- **Tertiary Label** (`Color.tertiary`): Fine-grained supplemental metadata.
- **Thin Material** (`.thinMaterial`): The readiness card's translucent system surface when it sits above the grouped background.

### Named Rules

**The One Signal Rule.** Mint is the product's primary voice. Keep it for interaction, completion, readiness, and progress; do not spread accent color across every label or surface.

**The Evidence Color Rule.** A color must explain a state or metric category. Never use a hue to make an empty, estimated, or unsupported value look more authoritative.

## Typography

**Display Font:** SF Pro Display through the system `.largeTitle` style.
**Body Font:** SF Pro / SF Compact through SwiftUI system text styles.
**Label/Mono Font:** System caption styles for labels; monospaced system text only for pasted Strong export content.

**Character:** System typography makes the app feel at home on iPhone and keeps Dynamic Type available. Bold weights provide clear landmarks while secondary text stays quiet; there is no ornamental display face competing with the user's training data.

### Hierarchy

- **Display** (bold, `.largeTitle`, system line height): Top-level screen titles such as Today, Dashboard, Recovery, and exercise detail names.
- **Headline** (semibold, `.headline`, system line height): Workout titles, exercise names, card headings, and list-row anchors.
- **Title** (bold, `.title2` or `.title3`, system line height): Section headings and prominent metric values.
- **Body** (regular, `.body`, system line height): User-entered content, explanations, coach responses, and native form controls.
- **Label** (regular or bold, `.subheadline`, `.caption`, or `.caption2`, system line height): Units, dates, state labels, supporting metadata, and compact readiness labels. Uppercase is reserved for the small `READINESS` eyebrow.

### Named Rules

**The System Type Rule.** Use Dynamic Type styles and system weights; do not introduce fixed-size text or a branded font that makes logging or accessibility less reliable.

## Layout

Top-level destinations use a native `TabView` and major screens use `NavigationStack`. Content is generally a vertically scrolling column with a horizontal inset supplied by `.padding()`; dashboard and recovery surfaces use an 18pt vertical rhythm between major blocks. Detail screens keep navigation titles inline, while top-level screens use large titles or an equivalent large-title header.

Cards and metric tiles are arranged in flexible two-column grids when the information is naturally comparable. Metric tiles use a minimum height of 120pt and 14pt internal padding. Readiness and coach surfaces are full-width, while small recovery tiles use 12–13pt spacing and padding. Task-heavy entry screens intentionally use native `List`, `Form`, `Section`, `Stepper`, `Picker`, and `TextField` density rather than forcing every interaction into a custom card.

Use safe-area-aware system containers. Preserve a minimum 44pt hit target for controls, Dynamic Type reflow, VoiceOver descriptions, and Reduce Motion behavior. Adapt with native layout containers and flexible columns rather than fixed dashboard widths. Do not hide meaningful chart axes or labels merely to create a cleaner silhouette when the axes are needed to interpret real progress.

## Elevation & Depth

The system is flat-by-default and uses tonal layering rather than shadows. Depth comes from `systemGroupedBackground` behind `secondarySystemGroupedBackground` surfaces, with `.thinMaterial` reserved for the readiness card. There is no custom shadow vocabulary and no hand-rolled glass effect. Native sheets, bars, and navigation surfaces may use the system material behavior supplied by iOS.

### Named Rules

**The Tonal Layer Rule.** Separate a surface from its page with semantic system backgrounds first; do not add a shadow to compensate for a missing information hierarchy.

**The Material Is Rare Rule.** Material is a contextual surface treatment, not a default card background. Keep it on the readiness card or platform-owned chrome unless a future component has a clear reason to be translucent.

## Shapes

The form language is gently rounded, with three observed radii: compact recovery tiles at 16pt, common cards and charts at 18pt, and the high-priority readiness card at 24pt. Use `RoundedRectangle` clipping for custom cards and let native `List`, `Form`, controls, and sheets retain their platform silhouettes.

Borders are not a recurring visual primitive. Avoid adding outlines to every surface; use semantic tonal contrast. Buttons, fields, toggles, menus, and destructive actions should remain recognizably native. Rounded corners should support grouping and touch confidence, not turn every row into a floating pill.

## Components

### Buttons

Buttons are native, direct, and stateful rather than decorative.

- **Shape:** Use SwiftUI button styles and platform control shapes; do not build custom pill buttons for ordinary actions.
- **Primary:** Use `.borderedProminent` for prominent empty-state actions such as choosing an import file. The app tint supplies the emphasis.
- **Save / confirmation:** Use toolbar confirmation actions with semibold text (`Save`) and native disabled behavior.
- **Secondary / tertiary:** Use ordinary text buttons, labels with SF Symbols, menus, and native toolbar placement. Use `.borderless` only for compact row actions where the surrounding row already provides context.
- **Destructive:** Use `role: .destructive`, then protect irreversible actions with the native confirmation dialog.

### Cards / Containers

Cards are quiet containers for a single related idea, not miniature screens.

- **Corner Style:** 18pt for metric, coach, and chart cards; 16pt for compact recovery tiles; 24pt for readiness.
- **Background:** `secondarySystemGroupedBackground` for contained cards; `.thinMaterial` for readiness.
- **Shadow Strategy:** No custom shadows; rely on semantic tonal separation.
- **Border:** None by default.
- **Internal Padding:** 14pt for metric tiles, 16pt for charts, 17pt for coach cards, and 18pt for readiness.

### Inputs / Fields

Forms and logging use native SwiftUI inputs inside `Form` or `List` sections: `TextField`, `TextEditor`, `DatePicker`, `Stepper`, `Toggle`, `Picker`, and `Menu`.

- **Style:** Prefer the platform's default field and section treatment. Use `.roundedBorder` only where the existing flow calls for a compact standalone field, such as the coach composer or routine weight entry.
- **Focus:** Let iOS provide focus, keyboard, selection, and accessibility behavior; do not add custom glow rings.
- **Error / Disabled:** Use native alerts, disabled state, and destructive roles. Explain what failed and preserve the user's entered data where possible.

### Navigation

Use a six-destination `TabView` as currently implemented, with labels and SF Symbols for Today, Dashboard, History, Recovery, Coach, and Settings. The app tint is mint. Each major destination owns a `NavigationStack`; detail screens push within that hierarchy, and focused tasks such as routine editing, exercise selection, paste import, and workout logging use sheets or nested stacks with explicit Cancel/Save or Preview/Done actions.

The current tab structure is an observed implementation detail; if the information architecture is consolidated later, retain the same native principles and never replace the tab bar with web-shaped global navigation.

### Readiness Card

The signature component is a calm compass-like summary: a 105pt circular progress ring, a score displayed as `value / 100`, a small `READINESS` label, a concise interpretation, and supporting factors separated by middots. The ring uses the readiness state color with a low-opacity track and rounded stroke caps. Keep the score visibly subordinate to its meaning and factors; this is training guidance, not a medical instrument.

### Metric Card

Metric cards pair a small colored SF Symbol with a quiet label and a bold value/unit pair. They stretch equally in flexible grids, use a 120pt minimum height, and keep units visually secondary. Use them for comparable measurements such as sleep, HRV, estimated 1RM, best set, volume, and workout count.

### Coach Card and Messages

A coach card uses a mint SF Symbol, headline, and readable supporting detail in a full-width grouped surface. In the conversation view, the user's message uses a restrained mint-tinted surface and the coach's message uses the grouped surface. Preserve clear speaker labels, readable line lengths, and the local recommendation fallback when remote coaching is unavailable.

### Trend Chart

Charts use Swift Charts with a mint or semantically appropriate line, a subtle area fill, a 3pt line, and a 130pt frame inside an 18pt grouped card. Chart styling must serve actual history. Add accessible descriptions and meaningful axes or annotations when they are necessary to interpret dates, units, gaps, or confidence; never use a smooth decorative curve to imply data the user has not recorded.

## Do's and Don'ts

### Do:

- **Do** use SwiftUI/UIKit semantic colors so the system remains legible in Dark Mode and increased-contrast settings.
- **Do** keep mint scarce and meaningful: interaction, completion, readiness-positive states, and genuine progress.
- **Do** use system text styles, native controls, SF Symbols, sheets, lists, forms, alerts, and confirmation dialogs.
- **Do** show the user's real history honestly, distinguishing missing, estimated, and low-confidence data from a measured zero.
- **Do** use flexible grids, safe-area-aware scrolling, and at least 44pt touch targets.
- **Do** treat readiness and recommendations as wellness/training guidance, with context and uncertainty visible in the copy.
- **Do** honor Reduce Motion and preserve native navigation gestures.

### Don't:

- **Don't** create fake dashboards: no decorative KPI walls, fabricated values, unsupported precision, or charts without meaningful data.
- **Don't** use raw hex colors, bespoke web navigation, glassmorphism, custom shadows, or a third-party icon set.
- **Don't** make every surface mint, colorful, pill-shaped, or elevated; quiet tonal layering is the default.
- **Don't** hide meaningful chart axes, dates, units, gaps, or confidence information for visual cleanliness.
- **Don't** frame readiness, HRV, sleep, or recommendations as diagnosis or certainty.
- **Don't** replace native forms and controls with custom controls that reduce platform familiarity or accessibility.
