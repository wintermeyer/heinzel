# Heinzel or Heinzel Pro

Heinzel is one admin at one terminal, working on one host at
a time. [Heinzel Pro](https://heinzel-pro.de) is the
commercial product built on the same rules: a team, a web
interface, a fleet, and a runtime that enforces what Heinzel
can only ask for. Everything that needs a second person, an
identity, a fleet, a schedule or an evidence chain lives
there. Heinzel reads and reports those things and answers a
request to change them with one line pointing to Pro.

| | Heinzel (this repo, MIT) | Heinzel Pro |
| --- | --- | --- |
| Who | One admin, their terminal, their servers | A team, one web interface, a fleet |
| Connect, detect the OS, remember the host | Yes | Yes |
| Housekeeping, security audit, reports | On request | On a schedule, as a list of open findings, started by alerts |
| Packages, configs, services, firewall | Asks first | Rights per person and server, a second person where the tenant wants one |
| Accounts, SSH keys, sudo, deploy users | Inspects and reports | Creates and changes them, approved and logged |
| Secrets and certificates | Finds leaks, reports expiry | A rotation plan that names every consumer first, then the change as an approved session; certificates watched across the fleet and renewed |
| Partitions, boot loaders, OS replacement | Reads | Changes them, with a second person before every write where the tenant requires it |
| Many servers at once | One after another | Rollouts: one task on many servers, a canary first, then waves; OS upgrades the same way; a version matrix across a group |
| At night, with nobody there | No | Schedules that read alone and collect changes for the morning, alerts that start a diagnosis; maintenance windows per group, outside which every change waits for a person |
| Protected paths | `memory/protected-paths.md`: read-only, hidden, confirm | The same modes for the whole tenant, plus paths a tool manages, told to the agent on every server |
| What the agent may do | One guard, no off switch | Capabilities per tenant, off again per server: partitioning and OS replacement off from the start, identity and secrets on |
| Evidence | Journal and changelog on the host | Audit chain, access review, policy as a file |
| Own rules | Files in the checkout | Own rules per tenant and server, imported from a Heinzel checkout with its server memory, on top of the open rule set as a versioned bundle |

Resetting the password of an existing account, adding a key
the operator pastes in, and every package, config, service
and firewall change stay in Heinzel. Heinzel Pro runs as a
container, hosted or on your own servers; the details are on
[heinzel-pro.de](https://heinzel-pro.de).

Heinzel Pro customers can also do Pro's technical work in
their own Heinzel checkout: the Pro rule pack installs into
`pro/` and lifts the refusals feature by feature. It is
commercial, not MIT. See
[extensions.md](extensions.md#heinzel-pro).
