# WeiBei Homebrew Cask

The release build generates a checksum-pinned `weibei.rb` from the exact final DMG:

```bash
./script/build_release_dmg.sh
```

Generated output:

```text
dist/release/homebrew-tap/Casks/weibei.rb
```

Publish that file unchanged to `taekchef/homebrew-tap/Casks/weibei.rb` only after the matching GitHub Release contains the exact same DMG. Keeping the Cask in the separate Tap avoids a circular build in which changing the Cask would change the app's Git-derived build number and therefore the DMG checksum.

The Cask installs the same `魏碑.app` from the branded DMG. It verifies SHA-256 but does not bypass Gatekeeper or substitute for Apple notarization.
