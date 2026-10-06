# Count Me In

Pick a plan with your friends without the 40-message group chat. Start a plan,
add ideas and times, send one link to your group, and everyone taps what works.
The winner becomes the plan.

**Open the app:** https://armstead22.github.io/Count-me-im/

## What's here

| File | What it is |
|---|---|
| `index.html` | The whole app. This is the only file the website needs. |
| `supabase-setup.sql` | The one-time database setup that was run in Supabase. |

The app is a single static page served by GitHub Pages. Plans are stored in a
Supabase database and reached only through three database functions, so the
public key in `index.html` cannot read or list plans directly.

## Good to know

- **The link is the key.** Anyone who has a plan's link can add names, vote,
  remove things and lock the plan. Don't post a plan link somewhere public.
- **No accounts, so names are on trust.**
- **Limits.** A plan holds up to 30 people, 30 ideas and 20 times.
- **No payments yet.** Nothing in the app is paid or locked.
