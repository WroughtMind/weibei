# WeiBei licensing guide

WeiBei uses a mixed licensing model: the software and custom English fonts are
open source, while the project's identity and third-party material keep their
own terms.

## Software

Unless a file or directory says otherwise, source code and developer
documentation authored for WeiBei are licensed under the MIT License. The
complete license text is in [`LICENSE`](LICENSE).

MIT permits use, modification, distribution, sublicensing, and commercial use,
including as part of proprietary software, provided the copyright and license
notice are preserved. It does not require modified versions or hosted services
to publish their source code.

## WeiBei custom fonts

`WeiBeiStele` and `WeiBeiSteleMono` are licensed under the SIL Open Font License
1.1 (`OFL-1.1`). This applies to the matching font files in:

- `Sources/WeiBei/Resources/Fonts/`;
- `DesignSystem/assets/fonts/`;
- `website/assets/fonts/`.

The full license travels with each distribution copy as `OFL.txt` or
`OFL-WeiBei.txt`. `WeiBeiStele` and `WeiBeiSteleMono` are Reserved Font Names:
modified versions must use different names unless the copyright holder gives
written permission.

The complete glyph sources and build pipeline are maintained in
[`taekchef/weibei-english-font`](https://github.com/taekchef/weibei-english-font).

## Brand and project media

The MIT and OFL licenses do not grant permission to use the following material
to suggest that a fork or modified product is the official WeiBei project:

- the WeiBei / 魏碑 names, logos, product identity, and trade dress;
- `Docs/brand/`;
- `DesignReferences/`;
- WeiBei-authored brand media under `website/assets/brand/`;
- WeiBei-authored screenshots under `website/assets/screens/`;
- WeiBei-authored screenshots, videos, and release evidence under
  `Docs/release-evidence/`;
- `Attachments/pasted-image.png` and `Attachments/pasted-image-2.png`.

Copyright in those project media remains reserved. You may keep them while
cloning, building, and privately evaluating the repository. Remove or replace
them before publicly distributing a fork unless you have separate permission.

The open font license still permits normal use, embedding, modification, and
redistribution of the font files. It does not grant endorsement or trademark
rights. See [`TRADEMARKS.md`](TRADEMARKS.md) for the project identity policy.

## Third-party software

Third-party components keep their original licenses:

- JavaScript dependencies are recorded in the root and prototype
  `package-lock.json` files. Generated bundles retain embedded upstream notices.
- Noto Sans CJK and Noto Serif CJK web fonts under `website/assets/fonts/` are
  licensed under the SIL Open Font License 1.1 included in that directory.
- Apple system frameworks are used under the terms supplied by Apple and are
  not part of this repository's MIT grant.

See [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) for the distribution
notice and source locations.

## Reference and verification material

Third-party and public-domain reference assets are not relicensed under MIT:

- `Attachments/RichAnswerVerificationAssets/` is governed by its
  `manifest.json` and `ATTRIBUTION.md`.
- `Sources/WeiBei/Resources/RichAnswerVerificationAssets/` is governed by its
  `ATTRIBUTION.md`.
- `Sources/WeiBei/Resources/Inspiration/` records the source and rights basis in
  `SOURCES.md` and in the associated catalog.

Preserve all required attribution and usage restrictions when using those
materials. A repository-wide license never overrides an upstream copyright,
public-domain statement, or attribution requirement.

## User content and official services

WeiBei does not license or claim ownership of course files, notes, credentials,
or other content imported by a user. Those files remain under the control and
rights of their respective owners.

The MIT and OFL licenses apply to distributed software and font files. They do
not require the project to provide hosted accounts, synchronization, storage,
model usage, subscriptions, domains, signing certificates, or other official
services free of charge.
