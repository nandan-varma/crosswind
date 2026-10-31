# 0001: License AGPL-3.0-or-later, name Crosswind

Date: 2026-10-31. Status: accepted (owner decision, public GitHub repository).

## Context
The owner chose a public repository under AGPLv3. The strongest existing per-window macOS compositor candidate, Cocoa-Way, is GPL-3.0 (see research/mac-compositors.md).

## Options
1. GPL-3.0 app. Rejected: owner decided AGPL.
2. AGPL-3.0 app that incorporates GPL-3.0 code. GPLv3 section 13 and AGPLv3 section 13 explicitly allow linking/combining the two; the combined work is governed by AGPL for the network-interaction clause and GPL for the rest.
3. Permissive-only stack (Smithay + new macOS backend). Months of custom work, no gain once GPL code is acceptable.

## Decision
The project is **Crosswind**, licensed AGPL-3.0-or-later. GPL-3.0 dependencies are acceptable. Dependencies under licenses incompatible with AGPLv3 (e.g. GPLv2-only, proprietary, SSPL) are not.

## Consequences
- Mac App Store distribution is excluded in practice (App Store terms conflict with GPL-family licenses). Distribution is Developer ID + notarization, updates via Sparkle.
- Source headers carry `SPDX-License-Identifier: AGPL-3.0-or-later`.

## Revisit when
A relicensing request or a dependency with an incompatible license becomes necessary.
