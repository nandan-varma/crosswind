# Crosswind site

The homepage and documentation at https://crosswind.nandan.fyi, built with [Astro](https://astro.build).

- `src/content/docs/` holds the user guides (Markdown).
- `scripts/sync-docs.mjs` copies the repository's own `docs/` (development, security, roadmap, compatibility matrix) into the site at build time, so those pages are written once. The copies are gitignored.
- The site is static and served by Cloudflare Workers static assets (`wrangler.jsonc`), on the custom domain `crosswind.nandan.fyi`.

```sh
npm install
npm run dev      # sync docs and start the dev server
npm run build    # static site in dist/
npm run deploy   # build and publish with Wrangler (needs `wrangler login`)
```
