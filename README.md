# FOSShowcase

![Run unit tests](https://github.com/foscomputerservices/FOSShowcase/actions/workflows/ci.yml/badge.svg) ![Swift Package Manager](https://img.shields.io/badge/spm-compatible-brightgreen.svg?style=flat) [![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Ffoscomputerservices%2FFOSShowcase%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/foscomputerservices/FOSShowcase) [![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Ffoscomputerservices%2FFOSShowcase%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/foscomputerservices/FOSShowcase)

FOSShowcase contains a number of applications that showcase the Open Source technologies developed by [David Hunt](www.linkedin.com/in/davidhun) of [FOS Comoputer Services, LLC](https://www.linkedin.com/company/fos-computer-services).  It demonstrates how to use [Swift](https://swift.org) to build an M-V-VM full-stack suite of applications:

- [Vapor](https://vapor.codes/)-based [Backend Web Server](https://www.focomputerservices.com) deployed on [AWS](https://aws.amazon.com/)
- [Ignite](https://github.com/twostraws/Ignite)-based [Web Front End](https://www.focomputerservices.com)
- [iOS Application]()
- [iPadOS Application]()
- [macOS Application]()
- [watchOS Application]()
- [tvOS Application]()
- [visionOS Application]()
- [Skip](https://skip.tools)-based [Android Application]()

## Documentation

For guides, articles, and API documentation see the 
[library's documentation on the Web][docs] or in Xcode.

[docs]: https://swiftpackageindex.com/foscomputerservices/FOSShowcase/documentation/fosshowcaseserver

## Alpha Stability Warning

Please note that these libraries are currently a work in progress.  The APIs are rapidly evolving and while the overall architecture is set, breaking changes will occur until 1.0 is released.  The documentation is evolving, but the 'Getting Started' guidance is incomplete.  Nonetheless, the implementations are stable and unit tests are in place to ensure proper code coverage and stability of all publicly-facing APIs.  This warning will remain in place until I feel that these limitations are remedied.  Please log any issues that you might find or suggestions for improvements.

## FOSShowcaseWebServer

FOSShowcaseWebServer is the web service backend that supports the various front end applications.

For guides, articles, and API documentation see the 
[library's documentation on the Web][docs] or in Xcode.

## FOSShowcaseWebApp

FOSShowcaseWebApp is an [Ignite](https://github.com/twostraws/Ignite)-based web application that presents an HTTP version of the application to the public at [http://www.foscomputerservices.com](http://www.foscomputerservices.com).

## FOSShowcaseiOSApp

FOSShowcaseiOSApp is a cross-platform [SwiftUI](https://developer.apple.com/xcode/swiftui)-based application that runs on:

- [iOS](https://www.apple.com/ios) - [Install]()
- [iPadOS](https://www.apple.com/ipados) - [Install]()
- [watchOS](https://www.apple.com/watchos) - [Install]()
- [tvOS](https://en.wikipedia.org/wiki/TvOS) - [Install]()
- [visionOS](https://developer.apple.com/visionos) - [Install]()

## Deploying

The public web service (Vapor backend + Ignite web app, behind nginx) runs as a
Docker Compose stack on an **isolated Tart Linux VM** (`fos-showcase`, `10.1.3.10`)
on the `fos-openclaw` host, on the UniFi "Public Servers" VLAN-3 DMZ. The repo is
the source of truth and the VM is disposable. Full architecture, network rules, and
the rebuild procedure are in [`docs/runbook-pi-to-vm.md`](docs/runbook-pi-to-vm.md).

### Routine deploy (code / config change)

Run from a machine that has the canonical secrets at `~/.foscs/fosshowcase/{.env,ssl/}`:

```bash
git commit ...        # commit your change first
./deploy/deploy.sh
```

`deploy/deploy.sh` ProxyJumps through the `fos-openclaw` host (the VM's DMZ VLAN is
reachable only via the host), then:

1. rsyncs the repo to `/opt/fosshowcase` on the VM,
2. delivers `.env` + `ssl/` (mode 600), and
3. runs `docker compose up -d --build` and prints `docker compose ps`.

Notes:

- A deploy **rebuilds both Swift apps** (~20–40 min) — the Dockerfiles `COPY` the
  whole repo, so any change invalidates the shared build cache.
- Secrets and TLS certs are **not** in git; they live at `~/.foscs/fosshowcase/` and
  are pushed at deploy time. `deploy/env.example` documents the required variables.
- Override targets via env: `VM_HOST`, `JUMP_HOST` (set `JUMP_HOST=""` to deploy
  directly when already on the internal network), `SRC_SECRETS`.

### Full VM rebuild (disposable VM)

If the VM is lost, rebuild from the runbook:

1. `deploy/provision-vm.sh` — create the Tart VM on VLAN 3 (`VLAN_IFACE=vlan1`),
2. in-guest provisioning (static IP, Docker, NTP, `deploy/nic-offload-off.service`, SSH hardening),
3. install the host LaunchAgents (`deploy/com.foscs.tart-fos-showcase*.plist`) for
   auto-start on reboot + daily checkpoints, then
4. `deploy/deploy.sh`.

Network and database authorization (UDM port-forward + firewall, Postgres `pg_hba`)
is permanent and managed in the `openclaw-config` repo — it does not need redoing
per deploy.

## Maintainers

This project is maintained by [David Hunt](https://www.linkedin.com/in/davidhun/) owner of [FOS Computer Services, LLC](https://www.linkedin.com/company/fos-computer-services).

## License

FOSShowcase is under the Apache License.  See the [LICENSE](https://github.com/foscomputerservices/FOSShowcase/blob/main/LICENSE) file for more information.
