# Temporary playtest economy policy

This project currently uses one server-wide/host-wide playtest policy:

- purchases have unlimited fictional game-dollar funding;
- purchases leave the persisted `dollars` value unchanged;
- monetary rewards are recorded/deduplicated normally but credit zero dollars;
- existing balances, inventory, ownership, marks, achievements, unlocks and
  receipts remain untouched;
- disabling the two constants in `policy.gd` restores ordinary stored-balance
  behavior without save migration.

The mode is source-owned host configuration. It must never be populated from an
RPC, request payload, profile/save, metadata operation, or client UI flag. The
host may send `display_snapshot(true)` to UI; while enabled the balance label is
`Unlimited`, not a fabricated integer. The stored balance remains available for
normal behavior after the policy is disabled.

## Integration rule

Callers must perform every existing check first: authenticated authority,
transaction ID/replay verification, request shape, catalog membership, host-
derived nonnegative price, quantity bounds, ownership/duplicate checks,
deployment/trade constraints and atomic-save readiness. Then call
`purchase_debit(stored_balance, authoritative_price, true)` and apply only its
`next_balance`. The policy only replaces the insufficient-funds decision and
debit; it never authorizes an item or transaction.

For rewards, grading/completion/mastery/unlock and receipt-deduplication logic
must run as before. Compute the normal authoritative reward, call
`earning_credit(stored_balance, amount, true)`, persist the receipt and all
nonmonetary results, and apply only `next_balance`. A suppressed reward should
report zero dollars while retaining its receipt so replay cannot pay later.

Trading remains inventory-for-inventory. Never mint money or accept a policy
flag from either participant.
