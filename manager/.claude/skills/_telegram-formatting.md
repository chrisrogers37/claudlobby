# Telegram Formatting Reference

Shared formatting guide for all skills that send output to Telegram (chat_id: `$TELEGRAM_GROUP_CHAT_ID`, exported from `bot.conf`).

## Always use MarkdownV2

Send all Telegram messages with `format: "markdownv2"` for consistent rich formatting.

## Escape Rules

MarkdownV2 requires escaping these characters with `\`:
```
_ * [ ] ( ) ~ ` > # + - = | { } . !
```

Every special character in the message **must** be escaped, including dollar signs, periods, parentheses, hyphens, plus signs, tilde (`~`), etc. Missing an escape causes silent failure. **Common gotcha:** `~` is strikethrough in MarkdownV2 — always escape it as `\~` (e.g., `\~/path/to/file` not `~/path/to/file`).

## Structure

Use Unicode section separators and emoji headers for visual clarity on mobile:

```
*SECTION TITLE*
━━━━━━━━━━━━
• Item one
• Item two with `code`
```

## Patterns

- **Section headers**: `*BOLD CAPS*` followed by `━━━━━━━━━━━━` separator
- **List items**: `•` (bullet) for items, indent sub-items with spaces
- **Status indicators**: `✅` success, `⚠️` warning, `❌` failure, `💤` sleeping/inactive
- **Grouping**: Use blank lines between sections, no blank lines within a section
- **Numbers**: Escape periods after numbers (`1\.`, `2\.`)
- **Conciseness**: This is mobile chat. One line per item. No prose paragraphs.

## Emoji Headers by Domain

| Domain | Emoji | Example |
|--------|-------|---------|
| Calendar | 📅 | `📅 *CALENDAR*` |
| Email | 📧 | `📧 *EMAIL*` |
| Tasks | ✅ | `✅ *TASKS*` |
| Contacts | 👥 | `👥 *CONTACTS*` |
| Finance | 💰 | `💰 *FINANCE*` |
| Deploys | 🚀 | `🚀 *DEPLOYS*` |
| Audits | 🔍 | `🔍 *AUDITS*` |
| System | 🖥️ | `🖥️ *SYSTEM*` |
| Database | 🗄️ | `🗄️ *DATABASES*` |
| Home | 🏠 | `🏠 *HOME*` |

## Fallback

If MarkdownV2 fails (usually a missed escape), retry with `format: "text"` as fallback. Plain text should still use the same structural pattern (emoji headers, bullets, separators via dashes).

## How to reference this file

Add this line to any skill that sends Telegram output:
```
See [_telegram-formatting.md](../_telegram-formatting.md) for Telegram output formatting rules.
```
