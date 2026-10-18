# Clinical public information

The website source of truth is `clinical-information/dist/` in this repository.
It contains plain HTML and CSS. It needs no build step, package installation,
ChatGPT account, or Sites service to run. Edit these files here and review them
with the app changes. Keep the privacy text consistent with the app's data use.

## Preview

From the repository root, run:

```sh
python3 -m http.server 8000 --bind 127.0.0.1 --directory sites/clinical-information/dist
```

Open [the home page](http://127.0.0.1:8000/) and
[the privacy policy](http://127.0.0.1:8000/privacy/).

## Deploy to another host

Publish the contents of `clinical-information/dist/` as the static website root:

- `index.html` serves `/`.
- `privacy/index.html` serves `/privacy/`.
- `style.css` serves `/style.css`.

The links start at the website root. Serve these files at a domain or subdomain
root. Hosting under a path prefix requires a separate link change. No backend,
provider SDK, or environment variables are required. Keep provider-specific
configuration outside `dist/` so the deployable files stay portable.

If the public URLs change, update the home and privacy URLs in Google OAuth
Branding. Use a domain you control to keep those URLs when changing hosts.

## Current hosting

The existing Google OAuth Branding pages remain hosted with Sites:

- [Home](https://clinical-app-information.palesky8.chatgpt.site/)
- [Privacy](https://clinical-app-information.palesky8.chatgpt.site/privacy/)

Sites project: `appgprj_6aca8b695b188191b6242c61c4b2d6c5`.

Sites uses its own repository for publication. When publishing there, copy the
tracked `dist/` files into a separate ignored publishing checkout, then use the
Sites publishing workflow. Do not maintain a second editable source there; this
repository is authoritative. Other hosts can use the tracked files directly.

Website files under `sites/` are excluded from the iOS backup release source
fingerprint. Website-only edits do not invalidate an existing app archive.
