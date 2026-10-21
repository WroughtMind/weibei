# WeiBei Homebrew Cask

The release workflow generates a checksum-pinned `weibei.rb` after both native DMGs have passed verification. It is included in the `release-ready` artifact:

```text
dist/publish/weibei.rb
```

Publish that file unchanged to `taekchef/homebrew-tap/Casks/weibei.rb` only after the matching GitHub Release contains the exact same DMG. Keeping the Cask in the separate Tap avoids a circular build in which changing the Cask would change the app's Git-derived build number and therefore the DMG checksum.

The authorized `python3 script/release.py --publish` flow performs this synchronization and checks both native installation receipts. See the [release runbook](../Docs/releases/dual-architecture.md).

The Cask installs the same `魏碑.app` from the branded DMG. It verifies SHA-256 but does not bypass Gatekeeper or substitute for Apple notarization.
