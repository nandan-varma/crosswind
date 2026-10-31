# 0006: Catalog: Flathub AppStream via the guest's verified Flatpak remote

Date: 2026-10-31. Status: accepted.

## Context
We need a catalog without trusting an unlicensed, undocumented API. Flathub's terms page 404s and no API rate limits are documented (flathub-flatpak.md).

## Decision
- App metadata (names, icons, screenshots, categories, releases) comes from the Flathub AppStream data (`appstream.xml.gz`, aarch64; 4,242 components measured). The guest's Flatpak fetches and verifies it against the pinned Flathub repo key (fingerprint 6E5C 05D9 79C7 6DAF 93C0 8135 4184 DD4D 907A 7CAE, to be re-verified at pin time); the host receives the bytes over the control channel and parses them in Swift.
- Install, update and permissions go through libflatpak in the guest.
- Popularity/trending ranking and download sizes come from flathub.org JSON (`/api/v2/collection/popular|trending`, `/api/v2/summary/{id}`); this data is display-only, never used for trust decisions, and the app works without it.
- Compatibility ratings come from our own test results, shipped as signed JSON with the app.

## Consequences
Only apps with aarch64 builds (about 86% of Flathub) are shown as installable; others appear as "no ARM build". We should contact Flathub about API usage before release (open item for the owner).
