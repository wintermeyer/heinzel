# History

## 2026-03-22 — Add CI/CD deployment user rule

Added `rules/deployment.md` to enforce creating a
dedicated deploy user with minimal privileges for
automated deployments. Triggered by a deployment
workflow that incorrectly used the root account.

## 2026-03-22 — Fix supportoer 502 Bad Gateway

Fixed supportoer.wintermeyer-consulting.de on
bremen3 returning 502. The Docker image
(ghcr.io/frankjmueller/oer-prototype:latest) had
two bugs: `dotenv` listed as devDependency but
imported at runtime, and five `src/` directories
missing from Dockerfile COPY. Applied workaround
via compose command override and volume mounts.

## 2026-03-22 — Migrate vutuv.de to bremen2

Moved vutuv.de (Phoenix/Elixir, ~60K users) from
frankfurt2.wintermeyer.de to bremen2.wintermeyer.de
with "legacy-" prefix on all resources. Using
pre-compiled OTP release with bundled ERTS 9.3.3.3
(Erlang 20 cannot build from source on Debian 13).
Set up DKIM, SPF, DMARC for outgoing email. App will
be rewritten — this is a legacy deployment.

## 2026-03-22 — Install upterm 0.22.0 on bremen3

Installed upterm 0.22.0 from the GitHub .deb release
on bremen3.wintermeyer.de. Binary at `/usr/bin/upterm`,
accessible to all users for secure terminal sharing.

## 2026-03-19 — Upgrade Ollama to 0.18.2 on all bremen servers

Upgraded Ollama 0.17.7 → 0.18.2 on bremen1, bremen2,
and bremen3 (one at a time). All custom systemd
drop-in overrides (OLLAMA_HOST=0.0.0.0) survived the
install script. Bremen3's three-instance setup
(GPU0/GPU1/CPU) verified intact with all 18 models.

## 2026-03-19 — Install headless Chromium on bremen3

Installed Chromium 146.0.7680.80 from Debian repos on
bremen3.wintermeyer.de. Headless mode verified working,
binary accessible to all users.
