# LoliSnatcher_Droid — Session Handover

Paste this back to resume with full context. Last updated: 2026-07-13 (build 5210).

## Project / workflow
- Flutter Android booru gallery app. Autonomous multi-feature build.
- **Working branch: `claude/experimental-megabuild`** (NOT the auto-named
  `claude/google-oauth-refresh-token-*` — all features live on megabuild).
- Build: `export PATH="$PATH:/opt/flutter/bin"; bash build.sh test`
  (must `git config --global --add safe.directory /opt/flutter` first; flutter
  warns about running as root but works). APKs land in
  `build/app/outputs/flutter-apk/LoliSnatcher_2.5.0_<build>_<abi>_test.apk`.
- Each feature: build → commit → push → upload test APK.

## Uploading builds
- **Google Drive (primary, durable):** creds live at
  `~/.config/lolisnatcher-drive/oauth.json` (gone after container reset —
  recreate from the block the user pasted; client_id/secret/refresh_token +
  `booru_apk_folder_id: 1v27HWGKh2L_tmoxB1gBo1MaEgc3Y2eYi`). Then:
  ```
  python3 scripts/drive_upload_build.py --token <short> --descriptor "label" \
    --apk <apk_path> --changelog-file /tmp/changes_<short>.txt
  ```
  Prints folder/changelog/apk URLs — post them in chat. `--token` is just a
  short folder-name key (litterbox is down, so make one up, e.g. `login5210`).
- Fallback host: **gofile.io** (works). Litterbox = HTTP 500, catbox rejects,
  0x0.st disabled.

## DONE this session (committed to megabuild)
- xxxtik.com handler (`lib/src/boorus/xxxtik_handler.dart`) — HLS video site,
  keyset cursor pagination, creators as artist tags, autocomplete. Commit 8744616.
- **Account login (commit bd1dad5):**
  - **xxxtik** = Firebase email/password (Identity Toolkit signInWithPassword,
    key `AIzaSyAm9k1Y1GRbET-w1Z9joYMp63x1EHwZ5fY`). idToken cached statically +
    refreshed via securetoken endpoint; Bearer header when `_authedEmail` matches
    `booru.userID`. 5-min backoff on failed login. Reuses booru userID/apiKey
    fields, relabelled Email/Password in `booru_edit_page.dart`.
  - **redgifs** = WebView login (their API login needs an hCaptcha). New
    `lib/src/pages/settings/redgifs_login_page.dart` opens redgifs' login page,
    injects a fetch/XHR hook capturing the Bearer token the signed-in page sends,
    accepts it only if it's a *user* token (sub != `client/…`). Token is
    IP+User-Agent bound → WebView uses `Tools.browserUserAgent`. Stored in
    `booru.apiKey`; `RedGifsHandler._activeToken` prefers it over guest while
    JWT `exp` valid; dropped on 401. Editor shows signed-in/guest status +
    "Sign in with browser" button (`_buildRedGifsLogin` in booru_edit_page).
  - **UNTESTED end-to-end** (no real accounts here) — ask user to verify both,
    esp. that the redgifs WebView auto-closes on login.

## xxxfollow.com support — HANDLER DONE (browsing), UI section PENDING
Site = React SPA + **Laravel** backend, same-origin API `https://www.xxxfollow.com/api/v1`.
Handler: `lib/src/boorus/xxxfollow_handler.dart` (registered; enum `XXXFollow`
added to booru_type.dart; factory pageNum=0 → 1-indexed; booru_edit_page prefill/
onTest/instructions wired). **Fully reverse-engineered + verified live.**

THE one content endpoint:
`GET /api/v1/post/search/tag?query=Q&genders=G&limit=L&page=N`
(headers: `X-Requested-With: XMLHttpRequest`, `Accept: application/json`,
`Referer/Origin https://www.xxxfollow.com`; session cookies auto-handled by
DioNetwork's cookie interceptor after a GET of `/`).
- **query present** → `{ tags:[{id,tag,posts}], users:[creators], search:[posts] }`
  - `users[]` = creators in the tag: `{id, username, display_name,
    public_avatar_url, public_cover_picture_url, gender:'f'|'m', type:'model'}`
  - `tags[]` = similar tags.
- **query empty** → discovery `{ new[10], popular[10], popular_search[15],
    tags_trending[10], contest }` (IGNORES page → handler serves once, locks p2+).
- **post shape** (in search[]/new[]/popular[]): `{ like_count, favorite_count,
  comment_count, post:{ id, slug, text, user_id, media:[{ type:'video'|'picture',
  url(full mp4), sd_url, fhd_url, uhd_url, thumb_url, thumb_webp_url, blur_url,
  start_url, width, height, duration_in_second, has_audio, order }], media_count,
  duration_total } }`. **Media = direct MP4 (downloadable).**
- `genders` param: '' / 'f' / 'm' (exposed as sort chip All/Female/Male; filtering
  effect unverified but harmless).
- No sort param exists in the API (user's "sort like redgifs" ≈ the gender filter).
- Guest = teaser set only (~10 posts/tag, page2 empty) — a SITE restriction.
- Autocomplete: reuses post/search/tag, returns `tags[]` (or `tags_trending`).
- Other real endpoints (unused so far): `user/<username>` (creator profile),
  `user/public/top` (top creators, params {genders}), `post/public/<id>`
  (single post → {post}), `post/<id>/{view,like,favorite,tag-vote}` (POST),
  `user/<id>/follow/public` (POST), `account` (auth user), `site_config` (csrf).
- The handler stashes `lastRelatedTags` + `lastCreators` (List<XXXFollowCreator>)
  from each tag query — **ready for the UI section to consume.**

## PENDING (step 3 of plan) — Tag creators + similar-tags UI with dividers
User: "when you click a tag ... above the videos you have the creators in this
tag + similar tags underneath — implement in the tags section with some dividers."
- Data is already captured on the handler (`lastRelatedTags`, `lastCreators`).
- Need: a header strip / section (with dividers) in the tag/results or preview
  view showing creator chips (avatar + display_name → tap loads that creator)
  and similar-tag chips (→ tap searches that tag). Tapping a creator should load
  their feed — options: search `query=<username>` on xxxfollow, or add a
  `creator:` route via `user/<username>`. Mirror the sectioned look of the
  floating video preview window / tag_view chip sections.
- This is xxxfollow-specific UI but could generalise (redgifs also has creators).

## Key architecture notes
- BooruHandler: makeURL/fetchSearch/parseListFromResponse/parseItemFromResponse,
  availableMetaTags (SortMetaTag), hasTagSuggestions/getTagSuggestions,
  translateOrSyntax, validateTags, getHeaders, searchSetup (base handles
  signIn flow when `hasSignInSupport` + `canSignIn` = userID&apiKey nonempty).
- New booru type: add to `booru_type.dart` enum + getters + detectable/alias,
  register in `booru_handler_factory.dart`, add editor cases in `booru_edit_page.dart`.
- Virtual boorus already added this project: Collections, ForYou (+ Favourites/
  Downloads). InterestsHandler (behavior tracker), TagAliasResolver (cross-booru
  tag unification), FloatingPreviewHandler (route-tied floating preview window).
- WebView infra: `lib/src/widgets/webview/webview_page.dart` (InAppWebviewView,
  onLoadStop callback exposes controller for evaluateJavascript).
