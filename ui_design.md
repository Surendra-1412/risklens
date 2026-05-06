# RiskLens UI/UX Design Specification

## Overview
RiskLens is a high-performance, multi-chain crypto wallet tracker and QR scanner built with Flutter. The design focuses on a "cute" yet professional aesthetic, featuring rounded elements, soft gradients, and high-contrast typography.

## Core Design Tokens

### Color Palette
- **Dark Mode Background**: `#121212` (Deep Obsidian)
- **Light Mode Background**: `#FFFBFE` (Crisp Off-White)
- **Primary Accent**: `#2196F3` (Blue)
- **Success State**: `Colors.blue` / `Colors.greenAccent`
- **Error State**: `Colors.red` (with "Invalid QR" capsule feedback)

### Typography
- **Primary Font**: [Quicksand](https://fonts.google.com/specimen/Quicksand) (Rounded, modern, and "cute")
- **Scale**:
  - Main Balance: 36px Bold
  - Section Headers: 20px Bold
  - Subtitles/Description: 18px-20px Medium
  - Tab Labels: 20px-22px
  - Filter Labels: 15px Medium

### Components & UI Patterns

#### 1. QR Scanner (ScannerScreen)
- **Layout**: Fullscreen camera view.
- **Visual Feedback**: 
  - 4 Custom rounded corner brackets (Painter).
  - Ready State: White corners.
  - Success State: Blue corners.
  - Invalid State: Red corners + "Invalid QR" capsule.
- **Controls**: Top-right vertical stack for Torch and Gallery access.

#### 2. Portfolio Dashboard (LedgerScreen)
- **Header**: Large Quicksand typography with a glass-morphism search bar.
- **Performance Card**: 
  - Glass-morphism container (low-opacity white/black with blur).
  - Real-time price info capsule (toggles on "i" button click).
  - Interactive `fl_chart` graph.
- **Time Filters**: Rounded selection pills (1H, 1D, etc.).
- **Transaction History**: Date-grouped transaction rows with dynamic type/direction icons.

#### 3. Navigation
- **Style**: Floating "Glass-morphism" bottom navigation bar.
- **Contrast**: Slightly darkened (`0.4` opacity) in light mode for optimized visibility against `#FFFBFE`.
- **Blur**: `20.0` sigma value.

### Interactive Filters & Search

#### 1. Search Bar (Global & History)
- **Style**: Glass-morphism design with `BackdropFilter` (sigma 10).
- **Behavior**: Animates a blue border and glow (shadow) when focused.
- **Typography**: Uses Quicksand for both input and hint text.

#### 2. Time Filters (Portfolio Tab)
- **Buttons**: "1H", "1D", "1W", "1M", "1Y", "Max".
- **Selected State**: Rounded background pill (Grey 850 in Dark, Light Blue in Light).
- **Text**: Transitions to Bold blue/white upon selection.

#### 3. Transaction Filters (History Tab)
- **Layout**: Three equal-width columns (Date, Type, Direction).
- **Alignment**: Perfectly centered text using a "Balanced Row" technique (18px left spacer to offset the 14px icon + 4px gap on the right).
- **Feedback**: Text and icon turn **Blue** only when a specific filter is active (i.e., not default).

### Empty States
- **Style**: Centered Quicksand typography.
- **Content**: "Enter a wallet address to begin tracking" (Size 18, Medium weight).
- **Contrast**: Optimized for each theme (White70 in Dark, Black54 in Light).

## Assets
- **Launcher Icon**: `launcher.png` (Rounded design with `#87CEEB` background).
- **Brand Icon**: `icon.png`.

---
*Created by Antigravity AI for RiskLens Development.*
