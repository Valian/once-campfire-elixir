# Architecture

Phoenix 1.8, controllers + HEEx function components (no LiveView), on the Rails app's SQLite
database and Active Storage directory, unchanged. `docs/SPEC.md` is the contract; this is the map.

## Modules

| Module | Role |
|---|---|
| `Campfire.Repo` | the only writer (pool of 1, `BEGIN IMMEDIATE`). All inserts/updates/deletes |
| `Campfire.Repo.Replica` | read-only pool, one connection per scheduler. **All reads** that needn't see an open transaction |
| `Campfire.Repo.Setup` | boot: loads `priv/repo/structure.sql` into an empty DB, adds missing indexes, resets presence |
| `Campfire.Schema` / `.Timestamp` | `use Campfire.Schema` in schemas: `created_at`/`updated_at` as Rails text datetimes |
| `Campfire.Accounts` (+ `Account`, `User`, `Session`, `Ban`, `SessionCache`) | account singleton (persistent_term), sign-in, sessions (ETS-cached) |
| `Campfire.Rooms` (+ `Room`, `Membership`) | `Room.type` is `:open/:closed/:direct`; `class_name/1`, `param_key/1`, `route_key/1` give the STI strings |
| `Campfire.Messages.{Message, RichText, Boost}`, `Campfire.Storage.{Blob, Attachment, VariantRecord}`, `Campfire.Searches.Search`, `Campfire.Push.Subscription` | schemas only; contexts are yours to add |
| `Campfire.Signing` | Rails MessageVerifier: `signed_id/2`, `signed_stream_name/1`, `gid_param/2`, `sgid/2`, plus `envelope/3` + `sign/4` + `verify/4` for Active Storage |
| `CampfireWeb.Endpoint` | `/up` (before everything), `/assets` (Plug.Static, `.gz` siblings, immutable), parsers, cookie session `_campfire_session` |
| `CampfireWeb.Router` | `:browser` pipeline (+ `:authenticated`) |
| `CampfireWeb.UserAuth` | `fetch_current_user` / `require_authenticated_user` plugs, `log_in_user`, `log_out_user`, `disconnect_cable/1` |
| `CampfireWeb.Plugs` | `authenticity_token` → CSRF, `X-Version`/`X-Rev`, banned-IP 429, `@turbo_frame` |
| `CampfireWeb.Layouts` | `<Layouts.app>`: full page or Turbo frame layout, slots `head nav footer sidebar` |
| `CampfireWeb.Components` | `<.image src="x.svg">`, `<.avatar user>`, `avatar_path/1`, `<.local_datetime>`, `epoch_ms/1`, `<.csrf_input>`, `<.sidebar_frame>`, `<.translation_button>`, `<.account_logo>` |
| `CampfireWeb.Assets` | compile-time Propshaft manifest: `path/1`, Rails-identical stylesheet + importmap tags |
| `CampfireWeb.RateLimiter` | ETS fixed-window counters (`hit/3`) |
| `CampfireWeb.Cable` | Action Cable: `broadcast(stream, html_iodata \| map)` (encode once, local PubSub fan-out) and stream-name helpers (`room_messages_stream/1`, `user_rooms_stream/1`, `unreads_stream/1`, `reads_stream/1`) |
| `CampfireWeb.Cable.{Upgrade, Socket, Channels, Pinger}` | `/cable` plug (origin, subprotocol, cookie auth) → one WebSock process per connection; channel authorization/actions; one 3 s ping ticker |
| `Campfire.Rooms.Presence` | `Membership::Connectable` as atomic `UPDATE`s; `cutoff/0` = "connected" threshold for unread marking |

## Database

WAL; writer + reader pools on the same file (`DATABASE_PATH`, prod default
`/rails/storage/db/production.sqlite3`); `synchronous=NORMAL`, `busy_timeout=5000`, `foreign_keys`,
8 MB page cache per connection + 128 MB mmap. No Ecto migrations: the schema is Rails'. Additive
indexes go in `Campfire.Repo.Setup` (`CREATE INDEX IF NOT EXISTS`). Every datetime written or
bound **must** go through `Campfire.Schema.Timestamp` (schema field type, or `Timestamp.format/1`
for raw SQL): comparisons are on TEXT. In tests the Replica reads through `Campfire.Repo` (sandbox).

## Adding a page

1. Route in `CampfireWeb.Router` under `pipe_through [:browser, :authenticated]`.
2. `FooController` + `FooHTML` (`embed_templates "foo_html/*"`), Phoenix 1.8 style.
3. Template: `<Layouts.app flash={@flash} current_user={@current_user} turbo_frame={@turbo_frame} title="…" body_class="…">`; fill `<:head>`, `<:nav>`, `<:footer>`, `<:sidebar>` as the ERB's `content_for`.
4. Assets by logical name only (`<.image src="add.svg" size="20" />`, `CampfireWeb.Assets.path/1`).
5. Forms: `<.csrf_input />`; Turbo also sends `X-CSRF-Token`; either is accepted.
6. Turbo stream responses: `put_resp_content_type(conn, "text/vnd.turbo-stream.html")` and `send_resp`/render; the pipeline accepts `html` only, so don't add formats.

## Conventions

- Markup is a contract (SPEC T9): keep Rails' attribute order on the loadgen-scraped tags.
- Reads on `Replica`, writes on `Repo`; preload explicitly; no N+1 in partials.
- Anything that updates a `users` row calls `Campfire.Accounts.SessionCache.forget_user/1`;
  changing the account calls `Accounts.reload_account/0`.
- Cable: broadcast after commit with `CampfireWeb.Cable.broadcast/2` (render the HTML once; never
  per recipient). To drop a user's sockets (sign-out, membership removal) call
  `UserAuth.disconnect_cable/1`: every socket follows `"user_connections:#{user_id}"`.
- Responses are gzipped by Bandit (`Accept-Encoding`). For already-compressed bodies (webp, png)
  set `content-encoding`/`cache-control: no-transform` or use `send_file` (not compressed).
- Signed values (avatar tokens, stream names) via `Campfire.Signing`, keyed from `SECRET_KEY_BASE`.
- `bin/extract-assets` regenerates `priv/static` from `campfire-reference:app`; never re-digest.
- Tests copy `bench/seed` (or `SEED_DIR`) to `tmp/test.sqlite3` before boot; use `label/1` for seed ids.
  Phoenix.ConnTest skips CSRF: use `csrf_conn/0` when testing it.
- Run `docker build -t campfire-phoenix:app .`, then `bench/run --apps ours` (see `bench/README.md`).
