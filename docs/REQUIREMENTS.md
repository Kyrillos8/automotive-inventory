# Requirements (condensed from the owner's master prompt)

A specialized, production-quality, Arabic-first, offline-first mobile app for an automotive
spare-parts wholesaler (piston rings / شنابر, pistons / بساتم, other engine parts). Not a generic
inventory template. One admin, one device, no sync, no cloud, no server.

## Must-have capabilities
1. **Products** — internal SKU (unique), barcode, manufacturer T.C code (NOT unique), Arabic/English
   names, type (configurable; controls which spec fields show), brand, category, country of origin,
   base unit, purchase cost / wholesale / retail price, min & max stock, active/archived, notes.
   Structured searchable specs: diameter mm, size/oversize, ring dimensions, engine capacity,
   cylinders, engine code, pin diameter, compression height, label notes; extra key-value specs.
   Form sections: basic, type/category, manufacturer & label, specs, vehicles, pricing, inventory,
   tags, notes. Create tags/vehicles inline without losing form data. Stock never edited on the
   product form. Never delete products with posted transactions; archive instead.
2. **Tags** — many-to-many, admin-managed, normalized duplicate prevention, rename/archive/delete-if-unused,
   counts, filter any (default) / all. Chips on cards, details, search results, pickers.
3. **Vehicle compatibility** — makes, models, compatibility rows (years, engine capacity, engine code,
   status confirmed / needs verification, notes). Never infer compatibility automatically.
4. **Unified search component** reused everywhere products are picked; Arabic normalization
   (diacritics, tatweel, alef forms, digits, case); multi-term; ranks exact SKU/barcode/T.C first;
   filters: type, brand, category, tags, vehicle (make/model/engine), stock status; sorting;
   target ~300 ms for 10k products.
5. **Pricing** — customer type (wholesale/retail, walk-in = retail) sets default mode; invoice-level
   mode override; line-level price override recorded and never silently overwritten; historical
   documents keep snapshot prices; moving weighted-average cost; gross profit ≠ net profit.
6. **Inventory** — movement ledger + balance projection, reconciliation; opening stock (once),
   manual receipt/issue, damaged, adjustment (recorded vs physical, reason required),
   stocktaking (draft, resume, review variances, post once). Negative stock blocked.
7. **Purchasing** — suppliers; purchase orders (draft/ordered/partial/received/cancelled; no stock
   effect); goods receipts linked or direct, partial, rejected qty, actual costs; cost history;
   supplier returns.
8. **Sales** — fast invoice builder; drafts don't touch stock; posting deducts once; payments full /
   partial; outstanding balances; payment reversal (auditable); returns ≤ returnable qty,
   restock vs damaged, refund or customer credit; void via controlled reversal.
9. **Dashboard** — real metrics only (products, units, valuation, low/out of stock, today/period
   sales, wholesale vs retail, receivables, pending POs, recent movements/invoices) + shortcuts.
10. **Reports** — inventory, sales, purchasing, financial; date filters; CSV export UTF-8 with BOM.
11. **Backup/restore** — full DB backup, export to user location, versioned, validated, confirmed
    full-replacement restore, integrity check, safe against interruption.
12. **Security** — optional PIN (hashed, never plaintext) + biometrics where available.
13. **UI** — Arabic RTL, 5 tabs: الرئيسية، المنتجات، المخزون، المبيعات، المزيد (More: purchases, customers,
    suppliers, vehicle compatibility, stocktaking, reports, activity log, settings, backup).
    Loading/empty/error states, no fake buttons, no placeholder features presented as done.

## Acceptance tests (owner's list)
A product creation persists · B multi-vehicle compatibility & safe removal · C Arabic/English/code/
tag/vehicle/diameter search · D tag filter any/all + rename · E opening stock 20, no double post ·
F wholesale invoice 2 × 300 = 600, stock 20→18 · G retail 2 × 350 = 700 · H mode switch preserves
manual price · I 600 invoice, pay 400 → 200 due, partially paid · J PO 10, receive 6 then 4 ·
K return linked, restock vs damaged, cap · L persistence after restart · M backup/restore ·
N offline · O ledger = balances.
Automated coverage: A–K and O in `test/`. L, M, N require manual testing on a device.
