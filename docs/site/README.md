# Drel website

Static Cloudflare Pages site for `drel.app`. The public strong-offline fixture
is generated into a staging directory so its byte digests always match the
published resource and Web App manifests.

## Local preview

```bash
python3 -m http.server 8788 --directory docs/site
```

Open `http://127.0.0.1:8788`.

To preview the complete site including the generated offline test package:

```bash
bash tools/build-drel-site.sh
python3 -m http.server 8788 --directory build/drel-site-staging
```

## Cloudflare Pages

- Production branch: `main`
- Build command: leave empty
- Direct-upload output directory: `build/drel-site-staging`
- Custom domains: `drel.app`, then `www.drel.app`

Build, deploy and verify the public fixture with:

```bash
bash tools/build-drel-site.sh
npx wrangler pages deploy build/drel-site-staging --project-name=drel --branch=main
bash tools/verify-drel-offline-demo-public.sh
```

Build the companion offline-network demonstration (which keeps the base fixture
in the same Pages deployment) with:

```bash
bash tools/build-drel-offline-network-demo-site.sh
bash tools/verify-drel-offline-network-demo.sh
```

The generated `test/offline-network/gateway-manifest.json` is deliberately an
operator input: it must be signed by the gateway before `appId + route` push
opening is trusted by Drel.

## Desktop entry

`/launch/` is the public generic Home Screen entry. For a trusted HTML app it
accepts `app_id`, `name`, and an optional `/`-rooted `route`; for an ordinary
web page it accepts an HTTPS `url`, `name`, and optional HTTPS `icon`. After the
user adds the page to the Home Screen, its standalone load attempts to
hand off to Drel through a script-dispatched anchor using the custom URL scheme,
with a visible manual-open and copy fallback if the handoff does not succeed.
On iOS 18.3.1, reopening a Home Screen web app can resume its existing page
without rerunning its load script. The page therefore retries the handoff when
it becomes visible again. First and second Home Screen taps opened the target
page in Drel on the simulator after this change. Returning to the web app with
the system's back control can also retrigger the handoff, because web content
has no distinct Home Screen icon activation signal. Keep the manual fallback and
verify this behavior on the signed phone build before release. The ordinary-page
route opens inside Drel's normal browser without trusted-app bridge privileges.
Safari install mode keeps the install instructions visible.

Add each domain through **Workers & Pages → project → Custom domains**. Do not
create a manual Pages CNAME before associating the custom domain in Pages.

Before launch, configure Cloudflare Email Routing for `support@drel.app`,
`privacy@drel.app`, and `security@drel.app`, or replace those addresses with
verified inboxes.

## Links and public distribution

- App Store: https://apps.apple.com/cn/app/drel/id6802806992 (verified product
  page; regionless links redirected to the storefront homepage during the audit).
- App and services: https://github.com/dyyz1993/Drel (private, access required).
- SDK: https://github.com/dyyz1993/WebBridgeKit-Framework (private, access required).
- Public skill installation intentionally remains
  `npx skills add dyyz1993/WebBridgeKit --skill drel-app-development`.
  This is legacy distribution, not the current product source. Do not redirect
  public users to a private repository for installation.
- Public support stays at https://drel.app/support/ and support@drel.app;
  GitHub issue links in the app require repository access.

## Search and release checks

The English and Chinese Bark migration guides use documented compatibility
claims and link to Bark's official sources. Keep their reciprocal `hreflang`
links, canonical URLs and sitemap entries aligned. Do not add unrelated brand
lists, hidden keywords, fabricated reviews or claims of full API parity.

`robots.txt` advertises the sitemap. Product and documentation pages are listed;
test fixtures, skill artifacts and the 404 page are excluded. Their `noindex`
headers must be applied by the hosting platform, not just a local HTTP server.
Search Console submission and actual indexing/ranking require separate verification.

Use `build-drel-site.sh` for a full deployment. Individual demo builders reset
staging and can otherwise omit the skill ZIP, data-template or action demo.
Check desktop/mobile rendering, copy-command behavior, internal links and the
App Store destination before publishing. Do not publish unreleased feature claims.
