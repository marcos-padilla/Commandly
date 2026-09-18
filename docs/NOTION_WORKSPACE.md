# Notion workspace browser

`workspace.notion` and its `workspace.notion.search` tool browse a user's own internal integration.
Setup validates `/v1/users/me` and a read-only search before saving one connection and its token in
the existing Keychain adapter (`notion.workspace.connection.v1`). Replacing/removing a connection
invalidates old request authority. A new session waits for an in-progress secure mutation and then
reads committed storage. No OAuth installation, account creation or workspace mutation is performed.

Explicit Search submits the title query to Notion. An empty query lists accessible content; Load More
requests another 100 entries. Page/block children, database data sources and data-source rows are
navigable with Back history. Text, headings, checked items and table cells have readable previews;
unsupported media and richer presentation remain in Notion. The UI offers copy and canonical Notion
links, without fetching images/attachments or arbitrary response-supplied URLs. Search is limited to
content shared with the integration and is not a full-text workspace index.

The API version is pinned to `2025-09-03`. Primary references checked September 17, 2026:
[title search](https://developers.notion.com/reference/post-search),
[bot identity](https://developers.notion.com/reference/get-self),
[block children](https://developers.notion.com/reference/get-block-children), and
[version changes](https://developers.notion.com/reference/changes-by-version).

Requests go only to `https://api.notion.com/v1`, with a bearer header; redirects, URL credentials,
cookies and caches are disabled. Responses are bounded to 4 MiB, title queries to 512 bytes, page
sizes to 100, a visible list to 1,000 entries and navigation to 32 levels. Server rate limits produce
an explicit retry deadline. No token, content, URL or query is logged. Page data is session-only and
never enters AI context. Clipboard History may retain explicit copies.

Native controls provide search submission, Arrow/Return navigation, Back, Copy, Open and scrollable
setup with a fixed Done/Cancel control. Existing network-client access is sufficient; no new macOS
permission or dependency is added. Production fixture mode leaves this connector unavailable rather
than reading real credentials.

Three focused tests cover parsing/pagination, credential validation/request routing/stale connection
refusal, and registry integration. Root build/test evidence is recorded in the video parity ledger.
Live workspace credentials and native provider acceptance remain unverified.
