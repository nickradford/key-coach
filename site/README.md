# keycoach.nickradford.dev

The Shortcut Coach site: one static Astro page with a try-it demo of the miss flash, the hold
guide and the fading flash. It builds to plain files in `dist/` and runs on Cloudflare Workers
static assets, with no Worker script.

## Develop

Needs Node 22.23.4 or later (`.nvmrc` pins 24).

    npm install
    npm run dev       # http://localhost:4321
    npm run build     # writes dist/
    npm run preview   # serves dist/
    npm test          # the fluency port in src/lib/fluency.ts

The motion values, the island shape and the fluency stages are ports of
`Sources/ShortcutCoach/Motion.swift`, `Island.swift`, `Flash.swift`, `Guide.swift` and
`Sources/CoachCore/Fluency.swift`. Change them there first, then here.

## Deploy to Cloudflare

`wrangler.jsonc` names the Worker `keycoach` and serves `./dist`. Not deployed yet. Either:

- **Workers Builds (deploys on push).** In the Cloudflare dashboard, Workers & Pages > Create >
  Import a repository, pick `nickradford/key-coach`, and set the root directory to `site`, the
  build command to `npm run build` and the deploy command to `npx wrangler deploy`.
- **From this machine.** `npm run build && npx wrangler deploy` (logs in on first use).

Then add the domain: in the `keycoach` Worker, Settings > Domains & Routes > Add > Custom
domain, `keycoach.nickradford.dev`. `nickradford.dev` is already on Cloudflare DNS, so the
record and certificate are created for you.
