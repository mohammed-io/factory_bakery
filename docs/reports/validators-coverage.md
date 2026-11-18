# Validators coverage audit — 2026-11-18

**Gem under test:** working tree of this repo @ `e8ca916` (post v0.0.2 rewrite + A1–A7). All 284 specs green at audit time.
**Rails source audited:** `rails/rails` @ `78f4f0df` (2026-11-18, sparse clone of `activemodel` + `activerecord`).
**Empirical harness:** minimal empty Rails app (Rails 8.1.4.1, SQLite), gem path-injected; 30 probe models (one per validator, concrete options) + 3 supplementary probes. Reusable: `${TMPDIR}/factory_bakery-workspace/coverage-app`.
**Support matrix (Appraisals):** Rails 7.1 / 7.2 / 8.0. **Nothing New-upstream** — the newest validator (Comparison) is exactly the 7.1 floor; 7.2/8.0 added no validator classes.

## Gap summary (ranked; evidence below)

1. **Uniqueness is never enforced — dead flag.** `unique_required?` has zero call sites. First bake passes (empty table); the **second** bake of any constrained value space collides deterministically. Measured: forced-value (`inclusion: {in: ["FIXED"]}` + `uniqueness: true`) → second bake invalid 100% of the time; random-word strings 0/5 collisions (value space hides it). Real apps with format/inclusion-constrained unique fields (emails, codes) hit this constantly — Discourse smoke showed the same class.
2. **Presence semantics broken in three ways.** (a) boolean columns: `[true,false].sample` → `false.blank?` → **10/20 invalid (measured 50%)**; (b) defaulted columns route to NoopFiller *before* any validator check → nil → fails presence every bake; (c) `ActiveRecord::Validations::PresenceValidator` name not matched (masked today only because the flag is dead). `must_be_present?` is dead code.
3. **Symbol/Proc comparison options crash the bake.** `comparison: {less_than: :price}` on a float column → `NoMethodError: to_f for Symbol` (probe 16, measured); on dates the symbol bound resolves to nil → `NoMethodError: '+' for nil` (probe 17, measured). Rails documents value/proc/symbol for every comparison option.
4. **Proc `:in` inclusion is broken twice.** (a) probe 10 (`inclusion: {in: ->(r){%w[basic pro]}}`) baked **invalid — "Tier is not included in the list"** (measured); (b) Discourse smoke: procs are called eagerly at *filler initialization*, and app procs touching not-yet-loaded constants raise `NameError` inside `bake`.
5. **Format failure paths.** `:without` ignored; FFaker `from_regexp` rescue falls back to name-pattern words that violate the regex (Discourse `ColorSchemeColor` "Hex is invalid"); `adjust_length` truncation/padding runs *after* regex generation and can break compliance. Probe 6 (`/[a-z]+-\d+/`) passed — simple regexes work; the gap is the failure paths.
6. **Numeric constraint hygiene.** `other_than` stored but never enforced (probe 14 passed by luck — 1/100 draw); odd/even parity fix-up does `value + 1` with no bound check → `even: true, <= 7` produces 8 (fails); exclusion retry exhausts after 10/20 attempts and **returns the forbidden value**.
7. **json/jsonb columns have no filler.** Routed to StringFiller; Discourse `AppearanceChange` feeds a String into a Hash-expecting validator (fails on real PG too).

## Inventory — static vs empirical

| Validator | Static | Empirical (probe) | Notes |
|---|---|---|---|
| Absence (AM+AR) | Handled | ✅ P02 valid | nil emitted when flagged |
| Length (AM+AR) | Handled | ✅ P03–P05 valid | min/max/is/in honored; AR wrapper matched |
| Acceptance (AM+AR) | Handled | ✅ P18–P20 valid | `accept:` array/string/default all honored |
| Confirmation | Handled | ✅ P21 valid | builder propagates source→`_confirmation` |
| Inclusion, literal array/range | Handled | ✅ P08, P09 valid | type-coercion edge: integer `in:` on string column yields `"5"` |
| **Inclusion, proc `:in`** | Partial | ❌ **P10 invalid** | proc result not honored at pick time |
| Exclusion | Partial | ✅ P11 (single draw) | finite retry can return forbidden value |
| Presence (AM) | Partial | ✅ P01 (string) / ❌ **boolean 10/20, defaulted-cols 100%** | dead flag; three failure modes |
| **AR Uniqueness** | Partial (dead flag) | ✅ single bake / ❌ **second bake deterministic** | no enforcement mechanism |
| Numericality (AM+AR) | Partial | ✅ P12, P13 (single draws) | `other_than` dead; parity fix-up can breach bounds; Proc/Symbol crash |
| Comparison, numeric literal | Partial | ✅ within P16 until symbol | literal bounds honored |
| **Comparison, symbol/proc** | Partial | ❌ **P16, P17 crash (NoMethodError)** | float `.to_f` on Symbol; date nil bound |
| Format `:with` simple | Partial | ✅ P06 | works when FFaker can synthesize |
| Format `:without` / complex / proc | Partial | ✅ P07 (single draw, luck) | failure paths unguarded |
| Enum plumbing | Handled | ✅ P30 valid | `defined_enums` + inclusion fallback |
| `validates_with` / `validates_each` | N/A by design | ✅ P28, P27 (passed via name-pattern luck) | opaque to shaping; custom validators happened to pass |
| `validates!` strict | N/A by design | ✅ P29 | strictness changes error delivery, not values |
| `:if/:unless/:on` | N/A by design | ✅ P25, P26 | conditionals only relax; create-context respected |
| `allow_nil`/`allow_blank` | N/A by design | ✅ P24 | generated non-nil values are strictly stronger |
| `validates_associated` | N/A by design | — | per-model validity, outside attribute filling |

**Single-draw caveat:** probes bake once each; probabilistic gaps (exclusion, `other_than`, parity bounds, `:without`) passing one draw does **not** clear them — the supplementary probes (20× boolean, 5×2 uniqueness) exist precisely to measure rates where it matters.

## Structural notes

- Routing order in `FillerSelector` is confirmation → acceptance → (PORO: inclusion → length/format → numericality → presence-fallthrough), then column-type routing. Verified, not as earlier documented.
- Dead code: `CommonValidators#unique_required?` and `#must_be_present?` (zero call sites).
- `ActiveRecord::Validations::NumericalityValidator` and `AR::AcceptanceValidator` exist in 7.1–8.0 and are matched by the fillers; `AR::PresenceValidator` is not (see gap 2c).

## Reproduce

Harness app + probe sources live outside the repo (temp workspace): `rails runner` over 30 probe models, one JSON line each; supplementary probes for boolean-presence rate and uniqueness second-bake. The `rails-validators-coverage` skill re-runs the whole audit on demand.

## Cross-references

- Discourse smoke (docs/reports/smoke/20261118-discourse.md): same signatures at real-app scale — proc `:in` NameError, format regex, required belongs_to (→ associations epic #31), jsonb gap.
- Associations epic: FK/polymorphic/counter/STI gaps are already ticketed there (#14–#16, done) — deliberately not duplicated here.
