# Computer commons implementation checklist

The existing M203 classroom desktop has persistent course documents and is not
the requested public computer. Its behavior should remain available.

- [x] Place public workstations around campus: eight in M209, two in the lobby,
  and six in the hallways. The commons and a hallway station were rendered.
- [x] Provide power, session and idle shutdown for the 16 commons/lobby/hallway
  stations; `test_scattered_workstations.gd` exercises each and checks the
  hallway center route. M203 also has one public pilot workstation.
- [x] Add USB persistence for supported text and folder operations. Temporary
  public desktop files clear on power-off.
- [ ] Complete an actual tabbed browser with file upload. The desktop UI and
  calculator exist; `test_scattered_workstations.gd` opens the calculator and
  exercises its keypad. The browser remains unavailable.
- [x] Purchasable, renamable USB drives with capacities up to 150 MB, correct
  insertion/removal and disconnect-to-lost-and-found behavior. The core flow
  is implemented; cross-host interrupted-transaction resolution remains limited.
- [x] Purchasable portable laptop tiers with their requested performance and
  graphics differences, using the same computer and USB behavior.
- [ ] Validate power, idle timeout, sessions, persistence, inventory, concurrent
  users, reconnect/disconnect, real browser interaction and the assembled room.

The `test_public_network.gd` host/client scenario passed for simultaneous use
of two separate stations, file isolation, remote power-on and text save,
disconnect with the computer left on, and host power-off. It does not cover
USB insertion or USB disconnect handling.

Public desktops use the existing versioned text editor with per-station
temporary storage and `device_filesystem.gd` folder operations. Connected USB
drives support those text and folder operations. Browser integration and
arbitrary binary file editing remain unavailable.
`test_usb_between_workstations.gd` verifies that a file saved to one player's
USB is readable at another workstation and after rejoining, while another
player's local archive cannot read it. Without a USB, workstation files still
clear on power-off as requested.
The assembled-scene `test_usb_gameplay.gd` now also moves the drive between two
commons stations before reclaiming it; the isolated native run passed on
2026-11-13 (`USB_GAMEPLAY PASS`).

Browser candidate: Godot WRY v1.0.2, MIT licensed, Windows WebView2 backend,
from https://github.com/doceazedo/godot_wry/releases/tag/v1.0.2. The release
archive was staged under `.godot` and matched SHA-256
`706b407aca47df0626df26997a3e825a49c91985a199cead3d0b75d35fca783c`.
The isolated editor probe crashed at shutdown with the release's reloadable
configuration; an isolated headless runtime loaded the class and exited after
setting `reloadable = false`; the isolated headless editor also exited with that
configuration. A native probe reported that its default URL conflicted with
supplied HTML and did not complete its bounded teardown. A second isolated
graphical probe cleared the default URL, but still stalled before its 15-second
local-page callback; its own process was stopped at the 25-second bound.
Native rendering, tabs, upload and lifecycle remain unverified,
and the extension has not been installed in the game.

`usb_archive.gd` has isolated tests for per-owner/per-drive local archives,
binary content, capacities, names and rejected malformed records. USB metadata
now supports distinct purchases, names, capacities and hotbar/cabinet transfers;
`test_usb_inventory.gd` passes those authority-level operations. USB entries
also have hotbar and dorm-cabinet presentation. These backend purchases are
now exposed in the equipment shop. The singleplayer and host/client coverage
is described below.

`usb_transfer.gd` stages ordered, size-limited chunks and verifies a SHA-256
digest before returning a complete payload. `test_usb_transfer.gd` covers
completion, incorrect offsets, incomplete data, corrupt checksums and timeout.
It is now used by the authenticated multiplayer insertion path; completed
uploads are validated before inventory ownership is committed. Remote desktop
edits are staged locally and acknowledged after host commit and owner save.

Public workstation ports now route local singleplayer connections into the
power object and desktop. `test_usb_gameplay.gd` opens the actual game scene,
inserts a pre-created drive, saves a desktop file, checks powered removal is
denied, removes it after shutdown and reopens the file after reinsertion.
This automated test calls the interaction action directly. A rendered
`visual_usb_port.gd` check inspected the physical tower port and verified its
interaction ray reaches the target. A two-process host/client test in `test_usb_network_port.gd`
verified a bounded archive upload, connected ownership, safe removal and a
separate owner-disconnect case that marks the host record lost while retaining
the original client archive. The test now also verifies editing and writing
back a text file, removal and reinsertion, and owner reconnect followed by
lost-and-found reclaim. A connected local drive is marked lost
on session reset or after an interrupted profile reload and appears in the
owner's lost-and-found journal if its archive validates. The gameplay test
checks that a full hotbar leaves the item available and that owner reclaim
preserves the saved file. `test_usb_interrupted_recovery.gd` also verifies a
missing archive is not replaced. Other-player pickup uses a staged handoff that reserves the
sender, transfers and validates the archive, and commits both ledger profiles
only after the recipient saves it. `test_usb_network_port.gd` verifies a normal
host/client handoff and a sender disconnect during upload followed by reconnect;
`test_usb_handoff_target_abort.gd` verifies recipient disconnect during download.
`test_usb_handoff_ledger.gd` covers stale sender and recipient profiles after a
commit. These checks do not yet simulate every crash window or multiple hosts.
The host/client `save_error`
fixture verifies a missing owner archive rejects and rolls back a write before
a subsequent successful save; `interrupted_write` uses a timed-out pending
write fixture to check that the host powers down and marks the drive lost while
the owner's file remains intact. `test_usb_handoff_lost_ack.gd` simulates a
recipient losing the final inventory acknowledgement and verifies recovery on
reconnection to the same host. A client-local pending marker retains the staged
archive and warns when confirmation is unresolved. With no shared service, an
interrupted handoff cannot safely be declared committed or cancelled by a
different host; reconnecting to the original host resolves it.

The equipment shop lists 8, 32, 64 and 150 MB drives. `test_usb_inventory.gd`
checks products, distinct IDs, capacities and initialized local archives;
`test_usb_gameplay.gd` exercises the rename dialog and singleplayer use; the
host/client `purchase` case buys a drive and uses it at a workstation.
`test_usb_purchase_reconcile.gd` checks committed and uncommitted lost-reply
reconciliation. `visual_usb_shop.gd` rendered the equipment card and rename
dialog and exercised repeat purchase/rename clicks, invalid blank names and
cancel. `test_usb_inventory.gd` also checks invalid names/capacities and full
hotbar and cabinet behavior. `test_usb_cross_host_pending.gd` uses two isolated
ledger stores plus the game UI to verify the pending warning and retained
archive on a different host, then resolution through the original ledger. It
is not a two-server network test. Additional cross-host scenarios remain
unverified.

Portable laptops are offered in the equipment shop. The tier inventory and
portable computer-session foundation have isolated tests. The
portable session test covers a local USB mount, save, power-off and removal;
the lower-tier desktop has processing delays and a desktop-only display filter.
The world prototype can place and pick up an owned laptop, connect a
USB and open the desktop. The game-scene test exercises save, pickup and session
reset recovery. `visual_portable_laptop.gd` exercises F placement, ray targeting,
opening the laptop, USB insertion and power-button input, and renders the basic
tier desktop. Its pickup and file-saving checks remain in the separate direct-call
test. `test_portable_network.gd` checks host/client placement, duplicate and
non-owner rejection, a USB write, owner pickup and replacement, and laptop and
USB recovery after the owner disconnects and reconnects. Other disconnect windows
remain untested. `test_laptop_purchase_reconcile.gd` covers lost replies for
committed and uncommitted purchases in the ledger fixture; the purchase variant
of `test_portable_network.gd` exercises a successful host/client purchase and
the laptop lifecycle. `test_laptop_purchase_lost_reply.gd` simulates a host
commit after the client leaves and verifies recovery over a real reconnect.
`test_laptop_cross_host.gd` runs two independent hosts and a client, checks the
cross-host pending guard and USB archive, then returns to the original host.
The `host_loss` variant of `test_portable_network.gd` exercises an acknowledged
write followed by a host-staged write interrupted before delivery to the owner.
Remote writes now stage an owner-local archive and durable pending marker before
the host records a commit; the original archive is replaced only after commit.
The `host_loss_commit` and `host_loss_uncommitted` variants create the prepared
state and host decision as fixtures over real host/client sessions. The
`production_prepare` and `production_commit` variants interrupt the production
write path at preparation and durable host commit, respectively, and verify
reconnect and archive contents; the commit case also reconnects a second time.
They do not interrupt every instruction boundary. Basic, standard and premium
desktop rendering was visually checked. The shop now offers all three tiers;
`visual_portable_laptop.gd` exercises purchase, placement, USB use and pickup.
