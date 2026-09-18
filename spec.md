# unifi_client — Specification

`unifi_client` is an Elixir client for Ubiquiti UniFi. It targets the two
UniFi OS applications that share a console login — **Network** and
**Protect** — plus the hosted **Site Manager** cloud API and the Network
real-time event WebSocket.

This document is the source of truth for what the library does and what it
is committed to doing. Each section is marked either **implemented** (the
code in `lib/` does this today; the section is a description of that code)
or **planned** (accepted proposal, not yet merged; the section cites the
proposal). A planned section becomes implemented when its work item merges,
and the merge that does so updates the marker.

Sections:

1. [Conventions](#1-conventions)
2. [Local console client](#2-local-console-client) — `Client`, `Auth`, `CookieJar`, `API`, `Response`, `Error`
3. [Network API](#3-network-api) — `API.Sites`, `API.Devices`, `API.Clients`, `API.Networks`, `API.Firewall`, `API.Statistics`
4. [Network event WebSocket](#4-network-event-websocket) — `WebSocket.Client`, `WebSocket.Event`
5. [Site Manager cloud API](#5-site-manager-cloud-api) — `Cloud.Client`, `Cloud.API`, `Cloud.Sites`, `Cloud.Devices`, `Cloud.Clients`
6. [Protect](#6-protect) — planned: core seams (#1), REST API (#2), event WebSocket (#3)
7. [Examples and packaging](#7-examples-and-packaging)

---

## 1. Conventions

**Status: implemented.** These are the rules the code follows; new modules
follow them too.

### 1.1 Return shapes

- Every function that performs I/O returns `{:ok, value} | {:error, %UnifiClient.Error{}}`.
  Command-style functions (device restart, client block, …) return
  `:ok | {:error, %UnifiClient.Error{}}`.
- Values are **raw maps and lists as decoded from JSON**, with string keys
  exactly as the console returns them. The library defines no structs for
  API resources. Callers read `device["mac"]`, not `device.mac`.
- Binary bodies (images, video — §6) are returned as Elixir binaries or
  written to a path; they are never decoded.
- `UnifiClient.Error` is a `defexception` so it can be raised by callers who
  want to, but the library itself never raises it. The only functions that
  raise are the `new!/1` constructors, which raise `ArgumentError` on invalid
  configuration.

### 1.2 Error handling

- No `try`/`rescue`/`catch` anywhere in `lib/`. Failure is a value.
- Transport failures from Req (`{:error, exception}`) become
  `Error.connection_error(exception)`.
- HTTP status is inspected before body shape: 401 → `:authentication_failed`,
  404 → `:not_found`, other non-2xx → `:http_error` carrying `%{status:, body:}`.
- A 2xx body is then parsed by envelope (§2.5); an envelope that reports
  failure becomes `{:error, _}` even though the HTTP status was 200.

### 1.3 Requests

- All HTTP goes through `Req`. Each client struct carries a prebuilt
  `Req.Request` (`client.req`) with base URL, timeout, SSL options and — for
  the local console — cookie/CSRF steps attached.
- API functions accept an `opts` keyword list where useful; **unknown keys
  are passed straight through to `Req.request/2`**, so a caller can set
  `receive_timeout:`, `retry:`, `into:` etc. per call.
- MAC addresses are normalised before use (`String.downcase`, `-` → `:`).
- Times passed to the console are epoch **milliseconds** unless a function
  documents otherwise.

### 1.4 Module layout

```
UnifiClient                 version/0 and the top-level moduledoc
UnifiClient.Client          local console connection struct
UnifiClient.Auth            login / logout / self / authenticated?
UnifiClient.CookieJar       session cookie + CSRF agent (internal)
UnifiClient.API             HTTP verbs for the local console (internal-ish)
UnifiClient.API.*           Network endpoints, one module per area
UnifiClient.Response        Network envelope parsing (internal)
UnifiClient.Error           the error struct and constructors
UnifiClient.WebSocket.*     Network event stream
UnifiClient.Cloud.*         Site Manager (api.ui.com)
UnifiClient.Protect         bootstrap / nvr (§6.2)
UnifiClient.Protect.API     Protect request helpers (internal)
UnifiClient.Protect.Time    DateTime ⇄ epoch-ms
UnifiClient.Protect.*       Cameras (§6.2); Events, Video, WebSocket planned
```

A "site" argument is the Network site *name* (`"default"`), not its `_id`
or description. Protect has no sites.

### 1.5 Testing

- Unit tests use `ExUnit`; HTTP is stubbed with `Req.Test` by passing
  `plug: {Req.Test, Stub}` through a function's `opts` (which `API` forwards
  to Req), so no test reaches a real console. `plug` is a test-only dep.
- Integration behaviour is exercised manually with the scripts in
  `examples/` (§7). A work item that changes console-facing behaviour states
  in its completion note which console and application version it was
  verified against.

---

## 2. Local console client

**Status: implemented.**

### 2.1 `UnifiClient.Client`

The connection descriptor for a local console. It is a plain struct; nothing
is connected until `Auth.login/2`.

```elixir
%UnifiClient.Client{
  host: String.t(),                    # required
  port: pos_integer(),                 # 443 (:udm_pro) | 8443 (:controller)
  username: String.t() | nil,
  password: String.t() | nil,
  type: :udm_pro | :controller,        # default :udm_pro
  verify_ssl: boolean(),               # default false
  timeout: pos_integer(),              # default 30_000 ms, Req receive_timeout
  req: Req.Request.t(),                # built by new/1
  cookie_jar: pid(),                   # CookieJar agent, started by new/1
  csrf_token: String.t() | nil,
  logged_in: boolean()
}
```

Controller types:

| `type`        | Port | Network prefix   | Login              | Logout              | Protect |
|---------------|------|------------------|--------------------|---------------------|---------|
| `:udm_pro`    | 443  | `/proxy/network` | `/api/auth/login`  | `/api/auth/logout`  | yes (§6)|
| `:controller` | 8443 | *(none)*         | `/api/login`       | `/api/logout`       | no      |

`:udm_pro` means any UniFi OS console (UDM, UDM Pro/SE, UDR, UCG, UNVR,
Cloud Key Gen2+). `:controller` is the self-hosted Network application.

| Function | Behaviour |
|---|---|
| `new(opts)` | Validates `host` (required, non-empty binary), `type` (one of the two atoms, default `:udm_pro`), `port` (positive integer, defaults by type). Starts a `CookieJar`. Builds `req` with `base_url`, `receive_timeout: timeout`, `connect_options: [transport_opts: [verify: :verify_none]]` unless `verify_ssl: true`, and the CookieJar steps attached. Returns `{:ok, client}` or `{:error, :host_required \| :invalid_host \| :invalid_type \| :invalid_port}`. |
| `new!(opts)` | `new/1` or raise `ArgumentError`. |
| `base_url(client)` | `"https://#{host}:#{port}"`. |
| `api_prefix(client)` | `app_prefix(client, :network)`. |
| `app_prefix(client, app)` | `:udm_pro`: `"/proxy/network"` / `"/proxy/protect"`; `:controller`: `""` for `:network`, no clause for `:protect` (`FunctionClauseError`). |
| `app_available?(client, app)` | Whether the controller type hosts `app`: `:controller` hosts only `:network`. |
| `login_endpoint(client)` / `logout_endpoint(client)` | Per the table above. |
| `api_url(client, path)` | `app_url(client, :network, path)`. |
| `app_url(client, app, path)` | `app_prefix(client, app) <> path`. |
| `site_url(client, site, path)` | `api_url(client, "/api/s/#{site}#{path}")`. |
| `put_csrf_token(client, token)` / `mark_logged_in(client)` / `mark_logged_out(client)` | Struct updates used by `Auth`. `mark_logged_out` also clears `csrf_token`. |

### 2.2 `UnifiClient.Auth`

| Function | Behaviour |
|---|---|
| `login(client, opts \\ [])` | Requires `username` and `password` on the struct (else `{:error, %Error{code: :authentication_failed}}` without a request). POSTs `%{"username", "password", "remember"}` (`remember:` opt, default `true`) to `login_endpoint`. On 200 the cookies and `x-csrf-token` are already captured by the CookieJar response step; the CSRF token is copied onto the struct and `logged_in` set. Returns `{:ok, client}` — **the returned struct must be used for subsequent calls.** 401/403 → `:authentication_failed` with the console's message (`errors[0]`, `error`, or `meta.msg`) or a default; other status → `:http_error`. |
| `logout(client)` | No-op `:ok` if not logged in. POSTs `{}` to `logout_endpoint`; 200 or 302 clears the jar and returns `:ok`. |
| `self(client)` | GET `api_url("/api/self")` → `{:ok, user_map}` (first element of `data`). |
| `authenticated?(client)` | `false` if `logged_in` is false; otherwise `self/1` succeeds. Makes a request. |

### 2.3 `UnifiClient.CookieJar`

An `Agent` holding `%{cookies: [String.t()], csrf_token: String.t() | nil}`.
Internal, but public functions exist for the WebSocket client and tests.

| Function | Behaviour |
|---|---|
| `start_link(opts \\ [])` | Starts the agent. |
| `get_cookies(jar)` / `put_cookies(jar, [set_cookie_header])` | Stored as the raw `Set-Cookie` header strings. |
| `get_csrf_token(jar)` / `put_csrf_token(jar, token)` | |
| `clear(jar)` | Drops cookies and token. |
| `attach(req, jar)` | Prepends request step `unifi_add_cookies` and appends response step `unifi_save_cookies`. |

Request step: sends `cookie: name=value; name=value` built from the stored
headers (everything after the first `;` of each stored string is dropped),
and sends `x-csrf-token` on **POST, PUT, DELETE and PATCH** when a token is
held. Response step: stores every `set-cookie` header and the
`x-csrf-token` header if present.

### 2.4 `UnifiClient.API`

The HTTP verbs used by every Network module; also usable directly for
endpoints the library does not wrap.

| Function | Behaviour |
|---|---|
| `get(client, path, opts \\ [])` | GET. |
| `post(client, path, body \\ %{}, opts \\ [])` | POST with `json: body`. |
| `put(client, path, body \\ %{}, opts \\ [])` | PUT with `json: body`. |
| `patch(client, path, body \\ %{}, opts \\ [])` | PATCH with `json: body`. |
| `delete(client, path, opts \\ [])` | DELETE. |
| `download(client, path, dest, opts \\ [])` | GET streamed to `dest` (a path) → `{:ok, dest}`, or `dest: :memory` → `{:ok, binary}`. See §6.1. |
| `get_list(client, path, opts \\ [])` | `get/3`, wrapping a map result in a list → always `{:ok, [map()]}`. |
| `get_one(client, path, opts \\ [])` | `get/3`, taking the first list element; `[]` → `{:error, %Error{code: :not_found}}`. |
| `command(client, path, body \\ %{})` | `post/4` discarding the body → `:ok`. |

Every function takes `app: :network | :protect` in `opts` (default
`:network`); the key is consumed, not forwarded to Req. If
`Client.app_available?/2` is false for the client's type the function returns
`{:error, %Error{code: :app_unavailable}}` **before any I/O**.

URL rule (`build_url`): a path beginning with `/` gets the selected app's
prefix prepended **unless it already starts with that prefix**; any other
path is used verbatim. Every result goes through `Response.parse/1`.

### 2.5 `UnifiClient.Response`

Parses `%Req.Response{}` for the local console.

0. A body shaped `%{"error" => binary, "name" => _, "statusCode" => integer}`
   (the Protect error format) → `{:error, Error.api_error(body)}` on **any**
   status, checked before everything else.
1. Status 401 → `Error.authentication_error(msg)`; 404 → `Error.not_found()`;
   other non-2xx → `Error.http_error(status, body)`.
2. 2xx body, by shape:
   - `%{"meta" => %{"rc" => "ok"}, "data" => data}` → `{:ok, data}` (the Network envelope).
   - `%{"meta" => %{"rc" => "ok"}}` without `data` → `{:ok, body_without_meta}`.
   - `%{"meta" => %{"rc" => "error"}}` or any other `meta` → `{:error, Error.api_error(body)}`.
   - a map or list without `meta` → `{:ok, body}` (bare JSON; this is what Protect success bodies are).
   - a binary that decodes as JSON → recurse; a binary that does not → `{:ok, binary}`.
   - `nil` → `{:ok, nil}`.

`parse_one/1` and `parse_empty/1` wrap `parse/1` for single-item and
no-body cases.

### 2.6 `UnifiClient.Error`

```elixir
%UnifiClient.Error{message: String.t(), code: atom() | nil, reason: term()}
```

| Constructor | `code` | Notes |
|---|---|---|
| `new(message, code \\ nil, reason \\ nil)` | as given | |
| `authentication_error(msg \\ "Authentication failed")` | `:authentication_failed` | |
| `not_found(resource \\ "Resource")` | `:not_found` | message `"#{resource} not found"` |
| `connection_error(%Req.TransportError{reason: :timeout})` | `:timeout` | |
| `connection_error(reason)` | `:connection_error` | `reason` is the Req exception |
| `app_unavailable(app)` | `:app_unavailable` | `reason` is the app atom |
| `api_error(%{"meta" => %{"rc" => rc, "msg" => msg}})` | `String.to_atom(rc)` | Network envelope error |
| `api_error(%{"error" => msg, "name" => name, "statusCode" => n})` | 401/403 → `:authentication_failed`, 404 → `:not_found`, else `:http_error` | Protect error; `reason` is `%{status:, name:}` |
| `api_error(other)` | `:unknown` | `reason` is the body |
| `http_error(status, body \\ nil)` | `:http_error` | `reason` is `%{status:, body:}`; message mapped for 400/401/403/404/500/502/503 |

`UnifiClient.NotLoggedInError` is defined but not currently raised by any
code path.

---

## 3. Network API

**Status: implemented.** All functions take an authenticated `Client` and a
site name, build `Client.site_url(client, site, path)`, and go through
`UnifiClient.API`. `params` maps are sent as-is (string or atom keys — Jason
encodes both); the console's field names are not translated.

### 3.1 `UnifiClient.API.Sites`

| Function | Request | Returns |
|---|---|---|
| `list(client)` | GET `/api/self/sites` | `{:ok, [site]}` |
| `get(client, site)` | `list/1` filtered by `"name"` | `{:ok, site}` or `:not_found` |
| `health(client, site)` | GET `…/stat/health` | `{:ok, [subsystem]}` |
| `sysinfo(client, site)` | GET `…/stat/sysinfo` | `{:ok, map}` |
| `events(client, site, opts)` | GET `…/stat/event?_limit=&_start=` — `limit:` (100), `start:` (0) | `{:ok, [event]}` |
| `alarms(client, site)` | GET `…/stat/alarm` | `{:ok, [alarm]}` |
| `archive_alarms(client, site)` | POST `…/cmd/evtmgr` `archive-all-alarms` | `:ok` |
| `settings(client, site)` | GET `…/rest/setting` | `{:ok, [setting_section]}` |

### 3.2 `UnifiClient.API.Devices`

| Function | Request | Returns |
|---|---|---|
| `list(client, site)` | GET `…/stat/device` | `{:ok, [device]}` |
| `list_basic(client, site)` | GET `…/stat/device-basic` | `{:ok, [device]}` |
| `get(client, site, mac)` | `list/2` filtered by `"mac"` (normalised) | `{:ok, device}` or `:not_found` |
| `restart(client, site, mac)` | POST `…/cmd/devmgr` `restart` | `:ok` |
| `adopt(client, site, mac)` | POST `…/cmd/devmgr` `adopt` | `:ok` |
| `force_provision(client, site, mac)` | POST `…/cmd/devmgr` `force-provision` | `:ok` |
| `upgrade(client, site, mac)` | POST `…/cmd/devmgr` `upgrade` | `:ok` |
| `upgrade_external(client, site, mac, url)` | POST `…/cmd/devmgr` `upgrade-external` | `:ok` |
| `locate(client, site, mac, enabled)` | POST `…/cmd/devmgr` `set-locate` / `unset-locate` | `:ok` |
| `forget(client, site, mac)` | POST `…/cmd/sitemgr` `delete-device` | `:ok` |
| `set_name(client, site, device_id, name)` | PUT `…/rest/device/:id` `%{"name"}` | `{:ok, [device]}` |
| `set_port_enabled(client, site, device_id, port_idx, enabled)` | read–modify–write of `port_overrides` (below) setting `"port_poe_enabled"` | `{:ok, [device]}` |
| `set_poe_mode(client, site, device_id, [port_idx], mode)` | same, setting `"poe_mode"` (`"auto"`, `"off"`, `"pasv24"`, `"passthrough"`) | `{:ok, [device]}` |
| `power_cycle_port(client, site, mac, port_idx)` | POST `…/cmd/devmgr` `power-cycle` | `:ok` |

`device_id` is the device's `_id`; `mac` functions take the MAC. Port
overrides: GET `…/rest/device/:id`, merge the new keys into the existing
override for each listed `port_idx` (creating one if absent), keep every
other override untouched, PUT the full `port_overrides` list back. This is
what makes the two setters preserve VLAN/speed settings.

### 3.3 `UnifiClient.API.Clients`

| Function | Request | Returns |
|---|---|---|
| `list_active(client, site)` | GET `…/stat/sta` | `{:ok, [client]}` |
| `list_known(client, site)` | GET `…/stat/alluser` | `{:ok, [client]}` |
| `get(client, site, mac)` | GET `…/stat/user/:mac` | `{:ok, client}` |
| `block(client, site, mac)` / `unblock/3` | POST `…/cmd/stamgr` `block-sta` / `unblock-sta` | `:ok` |
| `reconnect(client, site, mac)`, alias `kick/3` | POST `…/cmd/stamgr` `kick-sta` | `:ok` |
| `authorize_guest(client, site, mac, opts)` | POST `…/cmd/stamgr` `authorize-guest` — `minutes:` (60), `up_bandwidth:`, `down_bandwidth:`, `bytes_quota:`, `ap_mac:` | `:ok` |
| `unauthorize_guest(client, site, mac)` | POST `…/cmd/stamgr` `unauthorize-guest` | `:ok` |
| `extend_guest(client, site, mac)` | POST `…/cmd/hotspot` `extend` | `:ok` |
| `set_name(client, site, user_id, name)` | PUT `…/rest/user/:id` `%{"name"}` | `{:ok, [user]}` |
| `set_fixed_ip(client, site, user_id, ip, opts)` | PUT `…/rest/user/:id` `%{"use_fixedip" => true, "fixed_ip"}` + `network_id:` | `{:ok, [user]}` |
| `remove_fixed_ip(client, site, user_id)` | PUT `…/rest/user/:id` `%{"use_fixedip" => false}` | `{:ok, [user]}` |
| `forget(client, site, mac_or_macs)` | POST `…/cmd/stamgr` `forget-sta` with `macs` list | `:ok` |
| `history(client, site, mac, opts)` | POST `…/stat/session` — `start:`, `end:` (epoch s) | `{:ok, [session]}` |

`user_id` is the client's `_id` from `list_known/2`.

### 3.4 `UnifiClient.API.Networks`

| Function | Request | Returns |
|---|---|---|
| `list_wlans(client, site)` | GET `…/rest/wlanconf` | `{:ok, [wlan]}` |
| `get_wlan(client, site, id)` | GET `…/rest/wlanconf/:id` | `{:ok, wlan}` |
| `create_wlan(client, site, params)` | POST `…/rest/wlanconf` | `{:ok, wlan}` (first element) |
| `update_wlan(client, site, id, params)` | PUT `…/rest/wlanconf/:id` | `{:ok, [wlan]}` |
| `enable_wlan/3`, `disable_wlan/3` | `update_wlan` with `enabled` | |
| `set_wlan_passphrase(client, site, id, passphrase)` | `update_wlan` with `x_passphrase` | |
| `delete_wlan(client, site, id)` | DELETE `…/rest/wlanconf/:id` | `:ok` |
| `list_networks(client, site)` | GET `…/rest/networkconf` | `{:ok, [network]}` |
| `get_network(client, site, id)` | GET `…/rest/networkconf/:id` | `{:ok, network}` |
| `create_network(client, site, params)` | POST `…/rest/networkconf` | `{:ok, network}` |
| `update_network(client, site, id, params)` | PUT `…/rest/networkconf/:id` | `{:ok, [network]}` |
| `delete_network(client, site, id)` | DELETE `…/rest/networkconf/:id` | `:ok` |
| `list_wlan_groups(client, site)` | GET `…/rest/wlangroup` | `{:ok, [group]}` |
| `list_user_groups(client, site)` | GET `…/rest/usergroup` | `{:ok, [group]}` |
| `create_user_group(client, site, params)` | POST `…/rest/usergroup` | `{:ok, group}` |
| `update_user_group(client, site, id, params)` | PUT `…/rest/usergroup/:id` | `{:ok, [group]}` |
| `delete_user_group(client, site, id)` | DELETE `…/rest/usergroup/:id` | `:ok` |

### 3.5 `UnifiClient.API.Firewall`

Same pattern over three resources; `create_*` returns the first element,
`update_*` the raw list, `delete_*` → `:ok`; `enable_*`/`disable_*` are
`update_*` with `enabled`.

| Resource | Path | Functions |
|---|---|---|
| Firewall rules | `…/rest/firewallrule` | `list_rules/2`, `get_rule/3`, `create_rule/3`, `update_rule/4`, `enable_rule/3`, `disable_rule/3`, `delete_rule/3` |
| Port forwards | `…/rest/portforward` | `list_port_forwards/2`, `get_port_forward/3`, `create_port_forward/3`, `update_port_forward/4`, `enable_port_forward/3`, `disable_port_forward/3`, `delete_port_forward/3` |
| Firewall groups | `…/rest/firewallgroup` | `list_groups/2`, `create_group/3`, `update_group/4`, `delete_group/3` |

### 3.6 `UnifiClient.API.Statistics`

Report functions POST a body with `attrs` (the console's default attribute
list for that report) plus `start:`/`end:` from `opts` (epoch ms) when given.

| Function | Request | Returns |
|---|---|---|
| `hourly_site/3`, `daily_site/3`, `monthly_site/3` | POST `…/stat/report/{hourly,daily,monthly}.site` | `{:ok, [bucket]}` |
| `hourly_ap/3`, `daily_ap/3` | POST `…/stat/report/{hourly,daily}.ap` — plus `mac:` (normalised) | `{:ok, [bucket]}` |
| `hourly_user/3`, `daily_user/3` | POST `…/stat/report/{hourly,daily}.user` — plus `mac:`, `attrs:` | `{:ok, [bucket]}` |
| `dpi(client, site)` | GET `…/stat/dpi` | `{:ok, [entry]}` |
| `dpi_stats(client, site, type \\ "by_cat", opts)` | POST `…/stat/sitedpi` `%{"type"}` + `start:`, `end:`, `limit:` | `{:ok, [entry]}` |
| `speedtest_results(client, site)` | GET `…/stat/speedtest-results` | `{:ok, [result]}` |
| `ips_events(client, site, opts)` | POST `…/stat/ips/event` + `start:`, `end:`, `limit:` | `{:ok, [event]}` |
| `routing(client, site)` | GET `…/stat/routing` | `{:ok, [route]}` |
| `dashboard(client, site)` | GET `…/stat/dashboard` | `{:ok, map}` |

---

## 4. Network event WebSocket

**Status: implemented.**

### 4.1 `UnifiClient.WebSocket.Client`

A `WebSockex` process connected to
`wss://#{host}:#{port}#{api_prefix}/wss/s/#{site}/events`, authenticated by
sending the CookieJar's cookies as a `Cookie` header on the upgrade request.
SSL verification follows the client's `verify_ssl`.

| Function | Behaviour |
|---|---|
| `start_link(client:, site:, subscriber: \\ self(), name: nil)` | Connects; the subscriber list starts as `[subscriber]`. |
| `subscribe(ws, pid)` / `unsubscribe(ws, pid)` | Subscribers are monitored and dropped on `:DOWN`. |
| `stop(ws)` | Closes the socket. |

Frame handling: `{:text, json}` is decoded and the raw map is sent to every
subscriber as `{:unifi_event, map}`; undecodable text is logged at
`warning`; `:ping` is answered with `:pong`; any other frame is logged at
`debug` and ignored. Disconnects reconnect after 5 s, up to 10 attempts,
then the process gives up (stays alive, no further reconnects).

Event maps are the console's envelope: `%{"meta" => %{"message" => ...},
"data" => [event, ...]}`.

### 4.2 `UnifiClient.WebSocket.Event`

Pure helpers over the raw maps.

| Function | Behaviour |
|---|---|
| `parse(raw)` | `%{"data" => [..]}` → list of parsed events; `%{"data" => map}` or a bare event map → one parsed event. Parsed shape: `%{type:, key:, message:, time: DateTime \| nil, data: rest, raw:}`. |
| `type(event)` | Classifies `"key"` into `:client_connected \| :client_disconnected \| :client_roam \| :device_connected \| :device_disconnected \| :device_restarted \| :device_upgraded \| :wan_transition \| :admin_login \| :admin_logout \| :sync \| :unknown` (mapping table in the module). |
| `client_event?/1`, `device_event?/1` | Predicates over `type` or `"key"` prefix. |
| `extract_mac/1` | First of `"user"`, `"mac"`, `"client"`, `"ap"`, `"sw"`, `"gw"`. |
| `extract_time/1` | `"time"` (epoch ms) or `"datetime"` (ISO 8601) → `DateTime`. |

---

## 5. Site Manager cloud API

**Status: implemented.** The hosted API at `https://api.ui.com`, keyed by a
per-account API key. Independent of the local console client.

### 5.1 `UnifiClient.Cloud.Client`

```elixir
%UnifiClient.Cloud.Client{api_key: String.t(), base_url: String.t(), timeout: pos_integer(), req: Req.Request.t()}
```

`new(api_key:, base_url: \\ "https://api.ui.com", timeout: \\ 30_000)` →
`{:ok, client}` or `{:error, :api_key_required | :invalid_api_key}`;
`new!/1` raises. The Req carries headers `x-api-key`, `accept: application/json`,
`content-type: application/json`.

### 5.2 `UnifiClient.Cloud.API`

`get/3`, `post/4`, `put/4`, `delete/3` as in §2.4, with the cloud response
rules: 401 → `:authentication_failed` ("Invalid API key"), 403 →
`:authentication_failed` ("Access denied"), 404 → `:not_found`, other
non-2xx → `:http_error`; a 2xx body `%{"data" => data}` → `{:ok, data}`,
otherwise the body itself.

### 5.3 Resources

| Module.function | Request | Returns |
|---|---|---|
| `Cloud.Sites.list_hosts(client)` | GET `/ea/hosts` | `{:ok, [host]}` |
| `Cloud.Sites.get_host(client, host_id)` | GET `/ea/hosts/:id` | `{:ok, host}` |
| `Cloud.Sites.list_sites(client, host_id)` | GET `/ea/hosts/:id/sites` | `{:ok, [site]}` |
| `Cloud.Sites.get_site(client, host_id, site_name)` | GET `/ea/hosts/:id/sites/:name` | `{:ok, site}` |
| `Cloud.Sites.site_health(client, host_id, site_name)` | GET `/ea/hosts/:id/sites/:name/health` | `{:ok, map}` |
| `Cloud.Devices.list(client, host_id, site_name)` | GET `…/devices` | `{:ok, [device]}` |
| `Cloud.Devices.get(client, host_id, site_name, mac)` | GET `…/devices/:mac` | `{:ok, device}` |
| `Cloud.Clients.list(client, host_id, site_name)` | GET `…/clients` | `{:ok, [client]}` |
| `Cloud.Clients.get(client, host_id, site_name, mac)` | GET `…/clients/:mac` | `{:ok, client}` |

`/ea/` is Ubiquiti's early-access path family; the library tracks it as
shipped and revises when Ubiquiti stabilises it.

---

## 6. Protect

UniFi Protect runs on the same UniFi OS console as Network and is reached
with the same login session under the `/proxy/protect` prefix. Protect
exists only on UniFi OS (`type: :udm_pro`); a `:controller` client has no
Protect application.

Protect's API shape differs from Network's in three ways the library must
absorb: success bodies are bare JSON (no `meta`/`data` envelope), error
bodies are `%{"error" => msg, "name" => name, "statusCode" => n}`, and
several endpoints return binary media (JPEG, MP4).

### 6.1 Core seams

**Status: implemented** (proposal #1, work item #6).

- `Client.app_prefix(client, :network | :protect)` → `/proxy/network` /
  `/proxy/protect` on `:udm_pro`; `:network` → `""` on `:controller`;
  `Client.app_available?/2` says whether a type hosts an app. `api_prefix/1`
  is `app_prefix(client, :network)`; `app_url/3` is the app-aware `api_url/2`.
- `API.get/post/put/patch/delete/download` accept `app: :network | :protect`
  (default `:network`). `build_url` prefixes with the selected app's prefix
  and does not double-prefix a path that already carries it. Any request
  with `app: :protect` on a `:controller` client returns
  `{:error, %Error{code: :app_unavailable}}` before any I/O.
- `Response.parse` recognises the Protect error body on any status and
  returns `{:error, Error.api_error(body)}` carrying the message, the
  `statusCode` and the error `name`; the code is mapped from the status so
  callers match `:authentication_failed` / `:not_found` for either app.
- `API.download(client, path, dest, opts)` streams a binary body with Req's
  collectable `into:` (`File.stream!(dest)`). Req collects into the
  collectable **only for status 200**; any other status is collected into a
  binary, decoded, and handed to `Response.parse`, so the caller receives the
  ordinary `{:error, _}` and **the file is never created**. A transport
  failure mid-stream returns `{:error, _}` and removes the partial file, so
  `dest` exists iff the result is `{:ok, dest}`. `dest: :memory` returns
  `{:ok, binary}`. Honours `app:` and `receive_timeout:`.
- `Error` gains `:app_unavailable` and `:timeout` (a Req transport timeout
  maps to `:timeout` rather than a generic `:connection_error`).

### 6.2 REST API

**Status: partially implemented — proposal #2.** `Protect`, `Protect.API`,
`Protect.Time` and `Protect.Cameras` are implemented (work item #8);
`Protect.Events` (#9) and `Protect.Video` (#10) are planned.

Namespace `UnifiClient.Protect`, base path `/proxy/protect/api`. Same
conventions as §1: raw maps, `{:ok, _} | {:error, %Error{}}`. Every function
takes a trailing `opts` keyword list; the keys it documents are consumed and
the rest go to `Req.request/2`. Time arguments accept `DateTime.t()` or an
integer of epoch milliseconds, normalised by `Protect.Time.to_ms/1`.

`UnifiClient.Protect.API` (internal, `@moduledoc false`) is the one place
that sets `app: :protect`: `get/3`, `post/4`, `patch/4`, `download/4`, and
`with_query/2`, which appends only the non-`nil` params and omits the `?`
when none remain.

| Module.function | Status | Request | Returns |
|---|---|---|---|
| `Protect.bootstrap(client, opts)` | implemented | GET `/api/bootstrap` | `{:ok, map}` — `nvr`, `cameras`, `users`, `lastUpdateId`, … |
| `Protect.nvr(client, opts)` | implemented | GET `/api/nvr` | `{:ok, map}` |
| `Protect.Time.to_ms(dt_or_ms)` / `to_ms_or_nil/1` | implemented | — | epoch ms; negative integers are a `FunctionClauseError` |
| `Protect.Cameras.list(client, opts)` | implemented | GET `/api/cameras` | `{:ok, [camera]}` |
| `Protect.Cameras.get(client, id, opts)` | implemented | GET `/api/cameras/:id` | `{:ok, camera}` |
| `Protect.Cameras.update(client, id, params, opts)` | implemented | PATCH `/api/cameras/:id` with `params` verbatim | `{:ok, camera}` |
| `Protect.Cameras.snapshot(client, id, opts)` | implemented | GET `/api/cameras/:id/snapshot?ts=&w=&h=` — `ts:`, `w:`, `h:` sent only when given; `dest:` (default `:memory`) | `{:ok, jpeg_binary}` or `{:ok, path}` |
| `Protect.Events.list(client, opts)` | planned #9 | GET `/api/events?start=&end=&types=&limit=` — `start:`, `end:`, `types:` (list, joined with commas: `"motion"`, `"smartDetectZone"`, `"ring"`, …), `limit:` | `{:ok, [event]}` |
| `Protect.Events.thumbnail(client, event_id, opts)` | planned #9 | GET `/api/events/:id/thumbnail` | `{:ok, jpeg_binary}` or path |
| `Protect.Events.heatmap(client, event_id, opts)` | planned #9 | GET `/api/events/:id/heatmap` | `{:ok, png_binary}` or path |
| `Protect.Video.export(client, camera_id, start, end_, dest, opts \\ [])` | planned #10 | GET `/api/video/export?camera=&start=&end=&type=&filename=` streamed to `dest` via `API.download/4` — `type:` `:rotating` (default) or `:timelapse`, `timeout:` | `{:ok, dest}` |

`export` timeout: the console transcodes on demand, so the wait scales with
clip length. The default is derived — `max(client.timeout, clip_seconds ×
factor)` with `factor` a documented module attribute — and `timeout:` is an
explicit override. A timeout surfaces as `{:error, %Error{code: :timeout}}`.

Examples: `examples/protect_cameras.exs` (list, `--snapshot ID --out FILE
[--width PX]`; implemented) and `examples/protect_export.exs` (`--camera
--start --end --out`; planned #10).

### 6.3 Event WebSocket

**Status: planned — proposal #3.**

`UnifiClient.Protect.WebSocket` connects to
`wss://#{host}:#{port}/proxy/protect/ws/updates?lastUpdateId=#{id}` with the
same cookie/SSL handling as §4.1. `lastUpdateId` comes from
`Protect.bootstrap/1` unless `last_update_id:` is given.

Frames are **binary**. `UnifiClient.Protect.Frame.decode/1` parses one
packet:

```
<<type::8, format::8, deflated::8, _::8, size::32-big, payload::binary-size(size), rest::binary>>
```

`format` 1 = JSON (decoded), 2 = UTF-8 string, 3 = raw buffer; `deflated == 1`
means the payload is zlib-compressed and is inflated first. `decode/1`
returns `{:ok, term, rest} | {:error, reason}` and is total over binaries —
malformed input is an error value, never an exception.

Each Protect message is two packets, an **action** (`%{"action" => "add" |
"update" | "remove", "modelKey" => _, "id" => _, "newUpdateId" => _}`)
followed by its **data**. The client pairs them and sends subscribers
`{:unifi_protect_event, %{action: action, data: data}}`. `newUpdateId` is
tracked so a reconnect resumes from the last delivered update instead of
replaying. Subscribe/unsubscribe/stop and reconnect policy mirror §4.1.

Example: `examples/protect_events.exs`.

### 6.4 Not in scope (yet)

The official Protect/Network *Integration* APIs (`/proxy/*/integration/v1`,
`X-API-KEY` auth) are tracked as research issue #4. Nothing in this
specification depends on them.

---

## 7. Examples and packaging

**Status: implemented** (Network examples); Protect examples arrive with §6.

### 7.1 Examples

Scripts in `examples/` are runnable with `elixir examples/<name>.exs`. Each:

- reads `UNIFI_HOST`, `UNIFI_USER`, `UNIFI_PASS` from the environment, plus
  `UNIFI_SITE` (default `default`) and `UNIFI_TYPE` (`udm_pro` | `controller`,
  default `udm_pro`);
- accepts `-h` / `--help` and prints a usage message;
- uses `Mix.install` with a `path:` dependency on this checkout, so they run
  without a checkout-wide build.

| Script | Does |
|---|---|
| `list_sites.exs` | `API.Sites.list/1` |
| `device_list.exs` | `API.Devices.list/2` |
| `client_list.exs` | `API.Clients.list_active/2` |
| `device_poe.exs` | `API.Devices.set_poe_mode/5` |
| `protect_cameras.exs` | `Protect.Cameras.list/2`, `snapshot/3` — Protect needs no `UNIFI_SITE`/`UNIFI_TYPE` |

### 7.2 Packaging

- Hex package `unifi_client`, MIT, Elixir `~> 1.15`.
- Runtime deps: `req ~> 0.5`, `jason ~> 1.4`, `websockex ~> 0.4`.
- `UnifiClient.version/0` returns the package version string and must match
  `@version` in `mix.exs`.
- ExDoc `extras` include `README.md` and this `spec.md`.
