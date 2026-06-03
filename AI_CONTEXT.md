# Briefly AI Context

## Product

Briefly is a warm, simple iOS news reader for business, tech, and startup stories. The tone is casual, short, and readable by non-experts.

## Design Rules

- Prefer rounded shapes and warm cream, peach, and orange surfaces.
- Headlines should feel conversational, not like wire-service copy.
- Keep screens clean and high-contrast.
- Article titles should visually clamp to 2 lines on detail.
- Summary cards should visually clamp to 6 lines.

## Engineering Rules

- Use SwiftUI and MVVM-style state separation.
- Prefer REST integrations over SDK packages when external dependency setup slows delivery.
- Keep secrets out of source code and load from a local plist file.
- Fail gracefully when API keys are missing by showing usable mock content.

## Chat Rules

- Keep AI answers to 1 or 2 short sentences.
- Use simple language.
- Stay anchored to the article context.
