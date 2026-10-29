# Implementation status, business rules & assumptions

## Stack
Flutter · Dart 3 · Drift (SQLite) · Riverpod · GoRouter · flutter_localizations (ar-EG default, RTL).
No server; the on-device SQLite file is the source of truth.

## Status
All 7 phases are **written**. None of it has been compiled yet (the development sandbox had no
access to the Flutter SDK). Expect a round of compile fixes on the first build.

| # | Scope | Code |
|---|---|---|
| 1 | Arabic RTL shell, 5-tab nav, DB + migrations, settings, setup | ✔ |
| 2 | Product types/brands/categories/units, structured specs + extra specs, tags, makes/models, compatibility (confirmed / needs verification), unified search & filters, details, archive | ✔ |
| 3 | Movement ledger + balances, opening stock (once), receipt/issue/damage/adjustment, stocktaking (draft/resume/post), history, reconciliation | ✔ |
| 4 | Suppliers, purchase orders, partial goods receipts with rejected qty, cost history, supplier returns | ✔ |
| 5 | Customers (wholesale/retail), walk-in, invoice builder, mode + line overrides, post, payments + reversal, balances, returns (restock/damaged, refund or credit), void | ✔ |
| 6 | Dashboard from real data, low-stock alerts, 29 reports, CSV (UTF-8 BOM), activity log | ✔ |
| 7 | Backup create/export/restore with validation + safety backup, PIN lock, tests | ✔ (biometrics not included) |

## Core rules
- Money = integer piastres; quantities = integer milli-units. No floating point in storage.
- Stock changes only via `InventoryService.apply()` inside the posting document's transaction.
- Posting re-checks `status == draft` inside the transaction → no double posting.
- Posted documents are never edited/deleted; corrections = returns, reversals, adjustments, void.
- Negative stock blocked.
- Costing: moving weighted average. `SaleLine.unitCostAtSale` snapshots it; restocked returns re-enter at that cost; damaged returns stay in COGS as a loss.
- Mode switch updates only non-manual lines; if manual prices exist the user chooses keep / reset.
- Gross profit = net revenue − COGS. Net profit is not computed (no expenses module).
- Search: each query term must appear in the product's normalized search key (names, codes, brand, type, category, specs, tags, vehicles). Exact SKU/barcode/T.C ranks first. Tag filter: any (default) or all.

## Assumptions
- One warehouse, one admin, one device. T.C codes not unique; SKU unique (auto `P-00001`).
- Customer balance per invoice = total − returns + cash refunds − payments. A negative balance is customer credit (kept on that invoice; applying it to another invoice is not implemented).
- Payments cannot exceed outstanding (no advances).
- Stocktaking: adjustment = counted − expected-at-start, so sales during the count are not overwritten.
- Restore = full replacement after validation, with an automatic safety backup; app restarts and re-verifies balances.

## Known limitations
- Not yet compiled/tested on a device (see Status).
- No biometric unlock (PIN only), no alternative units of measure/conversions, no taxes (disabled), no PDF invoices, no CSV import of opening stock, no barcode scanning.
- PIN protects the UI only; data is not encrypted at rest. Keep backups off the device.
