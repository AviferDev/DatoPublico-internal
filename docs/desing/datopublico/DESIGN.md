---
name: DatoPublico
colors:
  surface: '#f9f9ff'
  surface-dim: '#d3daef'
  surface-bright: '#f9f9ff'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f1f3ff'
  surface-container: '#e9edff'
  surface-container-high: '#e1e8fd'
  surface-container-highest: '#dce2f7'
  on-surface: '#141b2b'
  on-surface-variant: '#434750'
  inverse-surface: '#293040'
  inverse-on-surface: '#edf0ff'
  outline: '#737782'
  outline-variant: '#c3c6d2'
  surface-tint: '#305ea1'
  primary: '#00366f'
  on-primary: '#ffffff'
  primary-container: '#1a4d8f'
  on-primary-container: '#9dc0ff'
  inverse-primary: '#a9c7ff'
  secondary: '#006a63'
  on-secondary: '#ffffff'
  secondary-container: '#99efe5'
  on-secondary-container: '#006f67'
  tertiary: '#4f3000'
  on-tertiary: '#ffffff'
  tertiary-container: '#6e4400'
  on-tertiary-container: '#ffae3c'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#d6e3ff'
  primary-fixed-dim: '#a9c7ff'
  on-primary-fixed: '#001b3e'
  on-primary-fixed-variant: '#0e4688'
  secondary-fixed: '#9cf2e8'
  secondary-fixed-dim: '#80d5cb'
  on-secondary-fixed: '#00201d'
  on-secondary-fixed-variant: '#00504a'
  tertiary-fixed: '#ffddb8'
  tertiary-fixed-dim: '#ffb95f'
  on-tertiary-fixed: '#2a1700'
  on-tertiary-fixed-variant: '#653e00'
  background: '#f9f9ff'
  on-background: '#141b2b'
  surface-variant: '#dce2f7'
typography:
  headline-lg:
    fontFamily: Inter
    fontSize: 28px
    fontWeight: '700'
    lineHeight: 36px
    letterSpacing: -0.01em
  headline-lg-mobile:
    fontFamily: Inter
    fontSize: 24px
    fontWeight: '700'
    lineHeight: 32px
    letterSpacing: -0.01em
  title-lg:
    fontFamily: Inter
    fontSize: 22px
    fontWeight: '600'
    lineHeight: 28px
    letterSpacing: -0.005em
  title-md:
    fontFamily: Inter
    fontSize: 18px
    fontWeight: '600'
    lineHeight: 24px
  body-lg:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  body-md:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
  label-md:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '600'
    lineHeight: 16px
    letterSpacing: 0.02em
  label-sm:
    fontFamily: Inter
    fontSize: 11px
    fontWeight: '500'
    lineHeight: 14px
    letterSpacing: 0.03em
rounded:
  sm: 0.125rem
  DEFAULT: 0.25rem
  md: 0.375rem
  lg: 0.5rem
  xl: 0.75rem
  full: 9999px
spacing:
  gutter: 1rem
  gutter-lg: 1.5rem
  margin: 1rem
  margin-md: 1.5rem
  margin-lg: 2.5rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 1rem
  space-lg: 1.5rem
  space-xl: 2rem
---

## Brand & Style

This design system establishes an institutional, highly structured civic portal designed to provide unambiguous access to official gazette publications and public administration data. The visual character rejects decorative trends in favor of systematic clarity, high legibility, and administrative sobriety. 

### Brand Personality & Visual Language
- **Institutional Authority:** Built upon calm, predictable structures that project trust, precision, and official accountability.
- **Cognitive Clarity:** Dense legal and administrative transcripts are parsed into scannable hierarchical blocks with explicit categorization and source citations.
- **Accessibility & Inclusion:** Visual decisions are strictly optimized for WCAG AA compliance, ensuring universal access for citizens, legal professionals, and civil servants.
- **Tone:** Neutral, objective, and restrained. Interfaces convey credibility through strict functional alignments rather than superficial ornamentation.

## Colors

The color system enforces strict semantic meaning and functional hierarchy. The interface operates exclusively in a light mode environment to mirror official printed gazettes and legal documentation standards.

### Color Tokens & Semantic Roles
- **Primary (`#1A4D8F`):** Used for primary navigation, high-level headers, interactive links, primary action triggers, and legal category tags.
- **On-Primary (`#FFFFFF`):** High-contrast text and icons positioned directly on primary fills.
- **Primary Container (`#DCE6F5`):** Subtle tinted background used for highlighting verified references, interactive citations, and active selection filters.
- **On-Primary Container (`#102C52`):** Deep navy text providing high-legibility contrast against container backgrounds.
- **Secondary (`#0F766E`):** Distinctive deep teal applied to administrative classification, civil service notices, and cross-departmental markers.
- **On-Secondary (`#FFFFFF`):** Plain contrast glyphs and labels over secondary fills.
- **Tertiary / Accent (`#F59E0B`):** Warm amber restricted strictly to time-sensitive alerts, active deadlines, and pending official periods.
- **On-Tertiary (`#1F2937`):** Dark slate text ensuring accessible contrast ratios over accent surfaces.
- **Background (`#F7F9FC`):** Cool civic canvas separating content structures from structural viewport margins.
- **Surface (`#FFFFFF`):** Pure white container surfaces providing clean structural separation for official publications and conversational outputs.
- **Surface Variant (`#EFF3F8`):** Desaturated surface striping used exclusively for AI-assisted summaries, metadata strips, and secondary information cards.
- **Outline (`#CBD5E1`):** Structural borders separating tabular cards, input regions, and systematic dividers.
- **Text Primary (`#111827`):** High-density dark neutral for continuous legal prose and primary headings.
- **Text Secondary / On-Surface Variant (`#4B5563`):** Neutral gray applied to metadata, dates, publication serial numbers, and supporting labels.

## Typography

Typography prioritizes continuous readability across variable-length legal items. Standardizing on `Inter` maintains uniform tabular metrics, crisp micro-letterforms, and balanced vertical rhythm.

### Editorial Hierarchies
- **Headline Large (`28px / 36px`):** Reserved for document title screens, daily gazette summary pages, and major analytical sections.
- **Title Large (`22px / 28px`):** Used for individual publication headers and section identifiers.
- **Title Medium (`18px / 24px`):** Used for card titles, query summaries, and grouping headlines.
- **Body Large (`16px / 24px`):** Standard reading level for analytical summaries, conversational answers, and official quotes.
- **Body Medium (`14px / 20px`):** Secondary description text, supporting criteria, and system alerts.
- **Label Scales (`11px - 12px`):** Uppercase and semi-bold labels applied to administrative classifications, official gazette department codes, and timestamp badges.

## Layout & Spacing

The layout structure is engineered around a content-first, 12-column grid system optimized for desktop administrative research and linear mobile inspection.

### Structural Framework
- **Desktop (min 1024px):** Max container width capped at `1280px` centered with `2.5rem` outer canvas margins and `1.5rem` gutters. Splits cleanly between standard search feeds (`8 cols`) and contextual metadata panels (`4 cols`).
- **Tablet (768px - 1023px):** Fluid 8-column configuration with `1.5rem` margins and `1rem` gutters. Collapses auxiliary legal context beneath the primary item view.
- **Mobile (< 768px):** Single-column stacked layout with `1rem` margins and `0.5rem` vertical separation between related items.

### Spacing Scale Application
- **`space-xs` (4px):** Micro spacing between badge icons and label strings.
- **`space-sm` (8px):** Gap between stacked metadata tags, chip elements, and inner field controls.
- **`space-md` (16px):** Standard internal container padding for standard publication cards and question input rows.
- **`space-lg` (24px):** Layout separation between distinct document chapters and summary modules.
- **`space-xl` (32px):** Top-level separation between major search views, conversational panels, and publication listings.

## Elevation & Depth

To sustain an institutional aesthetic, depth is established using structural outlines and surface value contrast rather than ambient drop shadows.

### Elevation Levels
- **Level 0 (Flat Canvas):** The `#F7F9FC` background canvas supports the main viewport.
- **Level 1 (Card Surface):** White containers (`#FFFFFF`) framed with a 1px solid border of `#CBD5E1`. Used for publication summaries, search results, and chat messages.
- **Level 2 (Active Focus / Floating Controls):** Filter dropdown menus, date pickers, and sticky action headers use `#FFFFFF` with a single 1px solid border (`#CBD5E1`) alongside an ultra-diffused shadow: `0 4px 12px rgba(17, 24, 39, 0.06)`.
- **Informative Strips:** System banners and generative summaries lie directly flush against content surfaces using background shifts (`#EFF3F8`) and a left accent bar (`3px solid #1A4D8F` or `#0F766E`).

## Shapes

The design system adopts a conservative geometry with minimal rounding to reinforce bureaucratic authority and structural stability.

### Geometry Hierarchy
- **Radius Small (`6px`):** Buttons, text fields, search bars, category tags, highlight chips, and citation links.
- **Radius Medium (`12px`):** Main card wrappers, publication containers, conversational answer blocks, and contextual modal frames.
- **Sharp Elements (`0px`):** Document preview panels, official split rules, and left-edge semantic indicators.

## Components

Components are optimized for structured reading, rapid data retrieval, and clear provenance of public data.

### 1. PublicationCard
- **Container:** Pure `#FFFFFF` surface with a 1px `#CBD5E1` outline and a `12px` corner radius. Internal padding: `16px`.
- **Header:** Displays the administrative identifier (e.g., "BOE-A-2024-XXXX") in `label-sm` (`#4B5563`), flanked right by publication date.
- **Content:** Publication title in `title-md` (`#111827`) with active hover transition to `#1A4D8F`. Followed by brief excerpt in `body-md`.
- **Footer:** Bottom row containing `CategoryLabel`, optional `DeadlineBadge`, and the explicit `OfficialSourceLink`.

### 2. HighlightsSection
- **Purpose:** Surfaces urgent or highly requested decrees and regulatory alterations.
- **Style:** Multi-card horizontal row or grid mounted on a `#EFF3F8` canvas strip framed with top and bottom 1px `#CBD5E1` rules.

### 3. CategoryLabel & HighlightBadge
- **CategoryLabel:** Neutral/administrative taxonomy chip. Background `#EFF3F8`, text `#1A4D8F` or `#0F766E`, font `label-md`, radius `6px`, padding `4px 8px`.
- **HighlightBadge:** Key normative changes. Background `#DCE6F5`, text `#102C52`, font `label-md`, radius `6px`.
- **DeadlineBadge:** Active administrative terms. Background `#FEF3C7`, text `#92400E` (derived from Tertiary `#F59E0B`), accompanied by a clock icon glyph.

### 4. SearchFilterBar
- **Layout:** Sticky or inline composite control combining search input and quick-filter dropdowns (Section, Department, Date Range).
- **Inputs:** Height `40px`, background `#FFFFFF`, border `1px solid #CBD5E1`, radius `6px`, typography `body-md`. Active focus state shows a `2px solid #1A4D8F` ring.

### 5. AiNotice
- **Style:** Compact strip with `#EFF3F8` fill, `1px solid #CBD5E1` border, `6px` radius, and a left accent border `3px solid #1A4D8F`.
- **Content:** Disclaims machine synthesis with clear provenance notice in `body-md` (`#4B5563`) and an official verification indicator.

### 6. Conversational BOE Interface (ChatQuestionField, ChatAnswerCard, ChatCitations)
- **ChatQuestionField:** High-prominence input box with `#FFFFFF` background, `1px solid #CBD5E1`, `12px` radius, incorporating primary submit button.
- **ChatAnswerCard:** `#FFFFFF` surface with `12px` radius and `16px` padding. Houses structured natural-language answers in `body-lg` (`#111827`).
- **ChatCitations:** Clickable citation pills within or below answers. Background `#DCE6F5`, border `1px solid #CBD5E1`, text `#102C52`, radius `6px`, leading directly to verified article lines.

### 7. OfficialSourceLink
- **Style:** Understated inline or block button. Text in `#1A4D8F` with underline on hover, paired with an external-link icon confirming redirection to the primary government publication.