# PDF Rename Whiz

Personal fork of NSHipster/Nominate (macOS app that renames PDFs from their contents).
This is my own product now. No upstream pull requests; change freely.

## Goal
A Mac app that reads receipt and medical-bill PDFs (digital and phone scans),
extracts key fields, renames them, and files them automatically.

## Naming format
`YYYY.MM.DD - Initials - $Amount - Provider.pdf`
Example: `2023.10.30 - JW - $41.00 - Flagler.pdf`
- Date: date of service; fall back to payment date
- Initials: first + last initial of patient (or guarantor); "WALDECK, JAN" → JW
- Amount: amount actually paid, two decimals
- Provider: short name of doctor, clinic, lab, hospital, or pharmacy

## Environment
- Apple Silicon, macOS 26.6, Xcode, Apple Intelligence enabled
- Primary AI: Apple Foundation Models (on-device)
- Optional backend: LM Studio, OpenAI-compatible API at http://localhost:1234/v1
- All processing stays on this Mac. No network calls except localhost.

## Hard rules
- Never overwrite a file; append " (2)", " (3)" on name collisions
- If date or amount is missing, or confidence is low: do not rename;
  move to a "Needs Review" folder with the original name
- Always offer a preview/dry-run before renaming
- Never commit PDFs; test receipts contain private medical data and this repo is public

## Roadmap
1. Build and run the unmodified app; test on copies in ~/pdf-test
2. Structured extraction: date, patient, amount, provider, confidence
   (Foundation Models guided generation, fed by the app's existing OCR text)
3. Receipt naming template in the format above
4. Inbox folder watching: new PDFs → "Processed" or "Needs Review"
5. Optional LM Studio backend, selectable in settings

## Prototype reference
A working Python prototype (receipt_ai.py) used this extraction prompt
with good structure; reuse its wording:

> You are reading a medical receipt, bill, or payment confirmation.
> Extract: date (YYYY-MM-DD, service date or payment date if none),
> patient (full name, or guarantor if no patient listed),
> amount (amount actually paid, number only), provider (short name),
> confidence (high/medium/low). Use null for anything you cannot find. Do not guess.