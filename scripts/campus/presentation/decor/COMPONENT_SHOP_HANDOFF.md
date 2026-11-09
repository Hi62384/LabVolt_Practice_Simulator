# Component shop fit-out handoff

`ComponentShopFitout` presents exactly two physical stations and retains the
existing action-page contract:

| Physical station | `role` | `page` | Existing flow retained |
|---|---|---|---|
| Parts counter, sloped parts display and trays | `shop_station` | `shop` | Component shopping |
| Oval negotiation table with two chairs | `shop_station` | `trade` | Player trading |

The interaction collision is an invisible envelope fitted to each shaped mesh;
it is not the visible colored box previously used as the station.

## Safe main-owned transition

1. Add `ComponentShopFitout` beneath the existing shop room and call `build()`.
2. Require `activation_contract_valid()` to return true.
3. Exercise the existing activation path once for `page == "shop"` and once for
   `page == "trade"`; the fit-out deliberately supplies no replacement economy
   or trading implementation.
4. Only after both routes mount successfully, disable/remove the six legacy
   visual station bodies. Do not remove the backing shop/trade pages or handlers.
5. Route `kits` and `inventory` only after the dorm replacement reports mounted;
   route `ics` only after the circuit-studio replacement reports mounted.
6. Keep `exit` available through the existing room/door interaction or a main-
   owned non-station return route.

This package does not add clothing/accessory sales. That belongs to the separate
clothing-store implementation.
