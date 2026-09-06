# alist-railway

Deployment image for [AList](https://github.com/AlistGo/alist) on
[Railway](https://railway.com), built for the published Railway template.

One layer over the upstream `xhofe/alist:latest` image. AList itself is fully
configurable from environment variables — database, port, site URL, admin
password, logging — so this repo exists for exactly one thing the environment
cannot express: AList stores its **search index backend** in a settings row, not
in a config file, so a Meilisearch service wired up by variables alone would
never actually be used.

`railway-entrypoint.sh` therefore:

- creates `/opt/alist/data` before AList looks for `config.json` there, and
- once, in the background after the server is answering, signs in with the
  deployment's admin credentials and switches `search_index` to `meilisearch`.

That step is guarded three ways so it can never revert a choice an operator has
made: it runs only while the setting still holds AList's shipped default
(`none`), only while no marker file exists on the volume, and only when
`MEILISEARCH_HOST` is set. It then `exec`s the image's own `/entrypoint.sh`, so
the upstream umask, chown and privilege handling are untouched.

## Railway configuration

| | |
|---|---|
| Port | `5244` (`PORT` and `HTTP_PORT`) |
| Volume | `/opt/alist/data` |
| Health check | `/ping` |
| Database | `DB_TYPE=postgres` plus the discrete `DB_HOST`/`DB_PORT`/`DB_USER`/`DB_PASS`/`DB_NAME`/`DB_SSL_MODE` variables |
| Search | `MEILISEARCH_HOST`, `MEILISEARCH_API_KEY` |
| First admin | `ALIST_ADMIN_PASSWORD`, read only while AList's user table is empty |
| Logging | `LOG_ENABLE=false`, which keeps AList's log on stdout instead of a file on the volume |

AList's own entrypoint runs `alist server --no-prefix`, so its configuration
environment variables carry **no** `ALIST_` prefix (`HTTP_PORT`, `DB_TYPE`,
`SITE_URL`, …). `ALIST_ADMIN_PASSWORD` is the exception: AList reads that one
directly, under that exact name, whatever the prefix setting.

The image is the plain `latest` variant deliberately, not `-aria2` or `-aio`:
those bundle an aria2 daemon with BitTorrent support, which Railway's fair use
policy does not allow.

## Licence

AList is AGPL-3.0. This repository carries only the deployment wrapper.
