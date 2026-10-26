# drel-baidu-verify route Worker

Cloudflare Pages strips `.html` from Baidu's exact verification URL and answers
`308`, which Baidu rejects. This narrow Worker owns only:

```text
www.drel.app/baidu_verify*
```

It returns the verification token with HTTP 200. The canonical file stays in
`docs/site/baidu_verify_codeva-BIoaP2kijY.html` so the site remains correct if
the Worker or route is removed. Keep the file and Worker together.

Deploy after any token or route change:

```bash
npx wrangler deploy worker.js \
  --name drel-baidu-verify \
  --compatibility-date 2026-08-25 \
  --routes 'www.drel.app/baidu_verify*'
```

Verify:

```bash
curl -fsS https://www.drel.app/baidu_verify_codeva-BIoaP2kijY.html
```

The checked-in `wrangler.toml` is the downloaded Pages project metadata retained
for provenance; deployment uses the explicit command above.
