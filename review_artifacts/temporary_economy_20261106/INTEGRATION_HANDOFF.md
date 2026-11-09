# Temporary economy integration handoff

The stable API is `res://scripts/economy/temporary_playtest/policy.gd`.

These existing files were intentionally not edited because they are owned by
other active work. Apply only after verifying the exact SHA-256 preimage below;
otherwise rebase the same decision points onto the owner's latest version.

| File | SHA-256 preimage |
|---|---|
| `scripts/inventory_authority/ledger.gd` | `230E616950EF6A15410EB9AE8D1DFC1C9FB3B1D7F552D78687815472D17D06DA` |
| `scripts/electronics_profile.gd` | `F1E6904A806A597E9C4BE582E8D7B8E926E0C2543D55E7AD50ABAD6FE27ADA14` |
| `scripts/campus/facilities/ledger_adapter.gd` | `1ECD214FB8B48FFE8313A31F2542E772E711F928947ED952C13AC26EE8C23588` |
| `scripts/avatar_cosmetics/persistence/profile_adapter.gd` | `1FF0BDB9EBE3C296C8D3098628FB79FF69C4EB210CCB718B3BBFACDCFE29147A` |
| `scripts/school_session.gd` | `960FAEAE29C96F1701A51CB90679A998A65B0D036DB51E27C42753D0DD0369DD` |
| `scripts/lab_challenges/ledger_adapter.gd` | `F922DA0AA4725E8D92C51E2ED7EA7B789156B3A06D8EC51451DAB33DE7C63BF4` |

## Required minimal integration

1. In the host ledger, preload `Policy`. After all current receipt/request/
   catalog/quantity/ownership checks, replace each funds comparison and debit
   with `Policy.purchase_debit(p.data.dollars, host_price, true)`. Assign only
   `decision.next_balance`. Include `capacity` in the success-required operation
   list so failed validation cannot be committed. Never read policy state from
   `args`, metadata, the bound profile, or an RPC.
2. Refactor `ElectronicsProfile` purchase helpers to accept an authority-supplied
   debit decision/callable, or have the ledger perform the debit after the helper
   validates and stages ownership. Cover `buy`, `purchase_bundle`, paid
   `obtain_ic`, `buy_analyzer`, `buy_box`, `buy_cosmetic`, and
   `upgrade_capacity`. Crafting with owned materials remains material-consuming
   and has no monetary debit. Atomic rollback retains the original balance.
3. In both facilities adapters, keep authority, sequence, facilities schema,
   pending-trade and atomic-save checks. Convert the negative `dollar_delta` to a
   host price and use the policy decision; persist `next_balance`, not `+=`.
4. In avatar cosmetic `purchase`, keep known-item, valid-price and already-owned
   checks. Use the decision for `purchased.dollars` before appending ownership.
   The surrounding ledger must retain its transaction receipt/replay guard.
5. Rewards: calculate the normal amount, persist the existing reward ID/receipt,
   then use `Policy.earning_credit(..., true)` and store its `next_balance`.
   Return/report `credit` (zero while enabled). In team challenges, do not treat
   a zero credited amount as failure when the reward receipt was newly written;
   grading, mastery, history, achievements and unlocks must still commit.
6. UI receives only the host-produced `Policy.display_snapshot(true)`. Render
   `Unlimited` in the electronics header and other balance surfaces. Prices may
   remain visible. Do not render a huge number or mutate a profile for display.

## Route audit

- Components and server-derived bundles: `inventory_authority/ledger.gd` →
  `electronics_profile.gd`.
- Analyzer, random boxes, legacy accessories, capacity: same host ledger/profile.
- Custom IC: paid obtain uses unlimited funding; craft mode still consumes owned
  materials and respects deployment reservations.
- Food: `facility_host.gd` derives menu price; authoritative facilities adapters
  atomically commit food state and dollars.
- New cosmetics: `avatar_cosmetics/persistence/profile_adapter.gd`; permanent
  ownership duplicate rejection stays mandatory.
- Courses: `school_session.gd` grading records continue; `ledger.award` and
  `ElectronicsProfile.reward` retain reward deduplication while crediting zero.
- Team challenges: mastery/history/evidence and reward IDs continue, dollars do
  not increase.
- Trading: inventory-only exchange remains unchanged. No tradable currency is
  introduced and no participant can select the mode.
- No separate paid crafting/facility route was found beyond the seams above.

No save, profile, engine, or live server was opened or mutated during this work.
