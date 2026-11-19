# Clinical public information

`sites/clinical-information/dist/` is the source of truth for the plain HTML and
CSS site. Review edits alongside app changes and keep privacy text consistent
with the app's data use.

## Preview

From the repository root, run:

```sh
python3 -m http.server 8000 --bind 127.0.0.1 --directory sites/clinical-information/dist
```

Open [the home page](http://127.0.0.1:8000/) and
[the privacy policy](http://127.0.0.1:8000/privacy/).

## Deploy to another host

Publish `sites/clinical-information/dist/` as the static root at a domain or
subdomain root. Links are root-relative, so hosting under a path prefix requires
link changes. No build step, backend, or provider config is needed inside `dist/`.

If the public URLs change, update the home and privacy URLs in Google OAuth
Branding. Use a domain you control to keep those URLs when changing hosts.

## Current hosting

The Google OAuth Branding pages are hosted with Sites
(`appgprj_6aca8b695b188191b6242c61c4b2d6c5`):

- [Home](https://clinical-app-information.palesky8.chatgpt.site/)
- [Privacy](https://clinical-app-information.palesky8.chatgpt.site/privacy/)

Sites publishes from its own repository: copy the tracked `dist/` files into a
separate ignored publishing checkout and publish from there. Do not maintain a
second editable source in that checkout.

Files under `sites/` are excluded from the iOS backup release source fingerprint,
so website-only edits do not invalidate an existing app archive.
