# LabVolt personal relays

Windows launcher builds bundle Node.js and Wrangler. Players who want to host
open **Host Game**, select **Relay account**, and sign in through Cloudflare in
their browser. They select an account and LabVolt deploys the Worker. A new
account may need to activate its workers.dev subdomain in the browser first.
Cloudflare OAuth credentials use Wrangler's named profile and OS keyring.
LabVolt stores the public hostname and a separate key for creating rooms.

Share the complete room code, including the part after @. It identifies the
host's personal relay. Guests join without a Cloudflare account. The host's game
runs the simulation, and the Worker closes the room when the host disconnects.

**Settings → Host Server** shows the room code, this installation's estimate of
requests remaining, and movement settings. Open Cloudflare for account-wide
usage and compute limits.

## Development

Run `npx wrangler dev --config relay/wrangler.jsonc --ip 127.0.0.1 --port 8787`
from the repository root. Launch LabVolt with
`LABVOLT_RELAY_URL=ws://127.0.0.1:8787` to test hosting without Cloudflare login.
For the multiplayer fixture, start host, client, and late client with the same
relay URL and an unused absolute `LABVOLT_TEST_ROOM_FILE` path. The release
workflow bundles the account tools and runs the menu smoke test with a local relay.
