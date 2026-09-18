# Clipboard History

Open **Clipboard History**, select an entry, and press Return to copy its captured content.
Command-K opens the action menu. Text, images, file URLs, names, collections, pins, and search
enrichment remain in memory until Commandly quits. They are not uploaded, logged, or persisted.

## Names and collections

Choose **Rename & Organize** from Actions or **Organize** in the information pane. Add an optional
display name and collection, then Save with Command-Return. Return also saves from either metadata
field. Escape or Cancel discards the draft. Clearing a name restores the original preview; clearing
the collection removes that assignment.

A name can have up to 120 characters and a collection up to 40. Whitespace is normalized. Existing
collection names are reused without case/diacritic duplicates, and **Choose Existing** offers the
current collection list. The collection filter appears when at least one collection exists.
Search matches custom names and collections as well as the existing captured content. Root launcher
search also matches stored metadata without reading the live clipboard or running extraction again.

Renaming and organizing do not replace the underlying text, image bytes, or file URLs and do not
change the system clipboard. Copy still uses the exact captured payload. Editing text later
preserves its name, collection, and pin.

## Pins and bounded history

Use **Pin Entry** / **Unpin Entry** in Actions or the labeled pin button in Information. Pinned
entries appear first under **Pinned** and have an icon and accessible pinned value. The **Pinned**
filter can be combined with the collection filter and query. Keyboard selection follows the same
order as the visible sections.

Pinned entries are protected from ordinary history-capacity eviction. The oldest unpinned entry is
removed when a new capture exceeds the configured bound. One slot always remains available for
fresh captures; pinning is refused with an explanation when all other slots are pinned. Pinning
does not make the history persistent. Delete and Clear History still remove pinned entries, and
the existing sensitive-value exclusion removes matching pinned entries as well.

## Verification

`ClipboardOrganizationTests` exercises payload preservation, named-pasteboard write suppression,
search metadata, bounded pin eviction, collection normalization, validation, keyboard/filter order,
text-edit metadata preservation, editor save, and cancellation. It uses named test pasteboards,
seeded entries, and no real clipboard, network, permissions, or image-analysis service.

Live release review still needs keyboard focus/Return/Command-Return/Escape, action menu navigation,
VoiceOver labels, Larger Text, light/dark appearance, and permission-free named-pasteboard fixture
flows. No live result is claimed by this document.
