# Shelf

Commandly Shelf is a built-in launcher application for keeping temporary local content and
file/folder references on a floating board while moving between macOS applications. It uses
Commandly's own visual language and interaction model; the general temporary-staging category is
inspiration, not a source for copied branding, assets, wording, or layout.

## User behavior

Open **Shelf** from the launcher, use the menu-bar commands, or press the system-wide shortcuts
**New Shelf** (`⌥⇧Space`) and **New Shelf From Clipboard** (`⌥⇧A`). Commandly captures the active
display before taking focus, then opens the single floating board in that display's preferred corner
on the active macOS Space, including over another application's full-screen Space. Shelf configures
that cross-application overlay role and its captured display placement before Commandly activates.
The same live board follows every Space until it is explicitly closed, preserving its items,
selection, and detail state. Repeating either command replaces the current board with a fresh empty or
clipboard-seeded board, respectively.

Drag the board from any unoccupied part of its surface. Buttons, menus, and staged-item interactions
keep their own behavior, and window movement is disabled while a staged item or selection is being
dragged out. A newly presented board fades and scales its initial content into place; Reduce Motion
shows that content immediately.

### Stage content

- Drop one or more file or folder URLs onto the board. Shelf keeps references to the originals; it
  does not copy them merely because they were staged.
- While a compatible drag is over Shelf, the board gains a blue outline and glow. The prompt also
  changes to say how many items will be added, so the drop state does not rely on color alone. If
  macOS has not reported the incoming count yet, the prompt says `files and folders` instead of
  displaying an incorrect zero.
- A file or folder already referenced by the board is not added twice.
- **New Shelf From Clipboard**, **Add From Clipboard**, and `⌘V` accept file URLs, folder URLs,
  standalone images, or plain text from the pasteboard. File and folder URLs remain references to
  their originals. Shelf materializes image bytes and UTF-8 text as private files owned by that
  board so every staged item can use the same preview, drag-out, sharing, and file-action pipeline.
  Reading the pasteboard does not modify it.
- If **Play drop sound** is enabled, an accepted drop or clipboard import plays a local macOS sound.

When a drag enters Shelf, direct action targets appear below the board. Dropping file or folder URLs
on **AirDrop**, **Messages**, or **Mail** opens that native sharing service without first adding the
items to Shelf. The matching commands in Shelf's action menu share the items currently selected on
the board, or all staged items when there is no explicit selection. Availability is determined by
macOS, and the direct targets use each service's native macOS artwork.

### Inspect, select, and drag out

Choose the item-count control to expand Shelf into its detail view. The detail grid shows native
previews, names, folder/file status, sizes when available, and whether a referenced item has become
unavailable. A homogeneous collection is described by its content, such as `2 images`, `3 PDFs`, or
`1 folder`; mixed collections use `items`. Click an item to toggle its selection; **Select All** and
**Clear Selection** are also available. When nothing is explicitly selected, actions apply to all
staged items.

Drag a staged item or multi-item selection into Finder or another compatible application. Shelf
offers copy only outside Commandly, so drag-out never moves or deletes an original and always leaves
the Shelf references in place. An outgoing Shelf drag is kept separate from incoming-drop targeting,
so it does not reveal the direct-action tray or move/resize the board. Use an explicit **Move To**,
**Move to Trash**, **Remove From Shelf**, or **Clear Shelf** action when that is the intended result.
Removing an external file/folder reference from Shelf never deletes the original. Removing a
clipboard-derived text/image item does delete the temporary file that Shelf owns for that item.

### Native actions

The compact context menu and detail action menu provide native, explicit operations for the active
items:

- Open in the default application, choose a compatible **Open With** application, reveal in Finder,
  or preview with Quick Look
- Share through AirDrop, Messages, Mail, or another compatible macOS sharing service
- Add supported content from the clipboard, copy staged item URLs back to the clipboard, or copy
  their newline-separated paths as text
- Duplicate on disk, copy to a chosen folder, move to a chosen folder, or rename one item
- Remove items from Shelf, clear the board, or move selected filesystem items to Trash after
  confirmation

Copy, move, duplicate, rename, and Trash operate on the actual files or folders. Sandbox access,
destination permissions, name conflicts, or target-application availability can still prevent an
operation; Shelf reports the failure instead of assuming it succeeded.

## Keyboard controls

| Keys | Shelf behavior |
|------|----------------|
| `Space` | Quick Look the active items |
| `Tab` | Toggle compact and detail views when Shelf has items |
| `⌘C` | Copy the active staged-item URLs to the pasteboard |
| `⌘V` | Add file/folder URLs, an image, or text from the pasteboard |
| `Delete` or Forward Delete | Clear the current board |
| `Esc` or `⌘W` | Close Shelf |

## Settings

Shelf stays visible across application focus and Space changes until explicitly closed. Its generic
**Settings → Applications** configuration schema includes:

- **Close when empty** dismisses a board after its last staged item is explicitly removed or
  trashed. Copy-only drag-out does not empty the board. A newly opened empty board does not
  immediately close.
- **Preferred corner** selects the initial Bottom right, Bottom left, Top right, or Top left anchor.
  It does not prevent manually repositioning the board afterward.
- **Play drop sound** plays a local system sound after Shelf accepts new staged content.

These values are non-secret preferences. They do not contain paths or staged content.

## Architecture

| Piece | Role |
|-------|------|
| `ShelfApplication` | Registration, settings schema, launcher open action, and in-app documentation |
| `ShelfLaunchController` / `AppRuntime` | Routes launcher, menu-bar, and fixed global-shortcut requests into per-presentation generations while capturing the active display before activation |
| `ShelfBoardModel` | Owns one board's external references, board-private clipboard files, selection, actions, security-scoped access, and cleanup |
| `ShelfBoardView` and focused subviews | Compact/detail presentation, whole-surface window movement, drag destinations and sources, native previews, opening motion, and accessible feedback |
| `ShelfApplicationServices` | Focused initializer-injected metadata, file action, Finder, URL, pasteboard, preview, and sound boundaries |
| `WorkspaceShelfFileActionService` and related adapters | AppKit/FileManager implementations behind Infrastructure protocols |
| `LocalShelfTemporaryContentStore` | Actor-confined, per-board materialization and deletion of private clipboard text/image files |
| `ShelfWindowConfigurator` | Borderless floating-window behavior, rounded host-layer masking, focus handling, keyboard dispatch, active-display placement, and active-Space behavior |

The app target owns the concrete macOS adapters. Collection-aware file metadata, sharing, preview,
and mutation contracts live in `Infrastructure` with in-memory implementations for tests.

## Privacy, permissions, and safety

- Dropped and pasted file/folder items are temporary URL references held in memory for the lifetime
  of the open board. Shelf does not copy those originals merely to stage them.
- Pasted text and image data is written only beneath a private, per-board directory in Commandly's
  temporary container. The directory is created with owner-only permissions. Shelf removes an owned
  file when its item leaves the board and removes the entire owned directory when the board closes
  or is replaced.
- Shelf does not persist a board, upload items, or log file names, paths, clipboard values, previews,
  temporary payloads, or contents.
- Shelf starts security-scoped access for accepted URLs when macOS supplies it, keeps that access only
  while the reference is staged, and releases it when the reference leaves or the board closes.
- Dropping a file URL or explicitly importing clipboard content does not introduce a new automatic
  TCC prompt. The App Sandbox can still deny protected locations or operations outside granted
  scope.
- Active-display placement reads macOS screen geometry and the fixed global shortcuts use the
  existing Carbon hot-key adapter. Neither requires Screen Recording or Accessibility permission.
- Native sharing is user initiated. The selected macOS service or receiving application—not
  Commandly—controls recipients, sign-in, transfer, and any network use.
- Destructive on-disk behavior is separate from clearing Shelf. Moving originals to Trash requires a
  confirmation in the detail view.

## Accessibility review

- Drop targeting combines the blue outline with a changing icon and item-count prompt.
- The board exposes its empty or semantic item-count value; direct action targets, close/back
  controls, selection, unavailable items, progress, and clipboard controls have VoiceOver labels or
  values.
- Item cells identify their selection state and explain that they can be dragged to another app.
- Shelf honors Reduce Motion for its initial fade/scale reveal, board transitions, and direct-action
  transitions.
- Whole-surface window movement yields to controls and staged-item drag sources. While an outgoing
  item drag is active, the board remains fixed in place.
- All core board operations have keyboard routes or menu/button equivalents. Native drag-and-drop is
  still inherently pointer-oriented; clipboard import/export and action menus provide alternatives.

## Current limits

- Commandly presents one temporary Shelf board. There are no simultaneous boards, recent/pinned
  shelves, docking, persistence, restore after quit, or item reordering.
- Drag input is limited to concrete file and folder URLs. Clipboard import accepts file/folder URLs,
  one standalone image representation, or plain text; it does not preserve rich-text formatting,
  materialize promised files from apps such as Photos or a browser, or stage arbitrary pasteboard
  representations.
- There is no notch/menu-bar drop zone, shake gesture, modifier-key activation, folder monitoring, or
  automatic activation while dragging elsewhere on screen. Shelf opens only through its launcher,
  menu-bar commands, the two fixed global shortcuts, or a configured registered-application
  shortcut.
- Commandly does not provide hosted links, cloud-provider OAuth/upload destinations, team sharing,
  image transformations, archive/transcode/OCR actions, custom scripts, or shell commands in Shelf.
  System sharing services may expose their own capabilities independently.
