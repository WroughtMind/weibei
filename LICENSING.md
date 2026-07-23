# WeiBei licensing guide

WeiBei uses a mixed licensing model so the software can remain open source
without giving away the project's identity or misrepresenting third-party
material.

## Software

Unless a file or directory says otherwise, source code and developer
documentation authored for WeiBei are licensed under the GNU Affero General
Public License version 3 only (`AGPL-3.0-only`). The complete license text is in
[`LICENSE`](LICENSE).

The AGPL permits commercial use. If you distribute a modified version, you must
provide its corresponding source under the AGPL. If your modified version
supports remote network interaction, it must offer those remote users the
corresponding source as required by section 13.

The copyright holder may also offer separate commercial terms. A commercial
license does not revoke or weaken rights already granted under the AGPL.

## Brand and project media

The following are not licensed under the AGPL:

- the WeiBei / 魏碑 names, logos, product identity, and trade dress;
- `Sources/WeiBei/Resources/Fonts/`;
- `Docs/brand/`;
- `DesignReferences/`;
- WeiBei-authored brand media under `website/assets/brand/`;
- WeiBei-authored screenshots under `website/assets/screens/`;
- `website/assets/fonts/WeiBeiStele.ttf` and
  `website/assets/fonts/WeiBeiSteleMono.ttf`;
- WeiBei-authored screenshots, videos, and release evidence under
  `Docs/release-evidence/`;
- `Attachments/pasted-image.png` and `Attachments/pasted-image-2.png`.

Copyright in those materials is reserved. You may keep the font files and
project media while cloning, forking, building, and privately evaluating this
repository. You may not redistribute those files, use them to brand another
product, or offer them as standalone assets without prior permission. Remove or
replace them before distributing a fork.

See [`TRADEMARKS.md`](TRADEMARKS.md) for the project identity policy.

## Third-party software

Third-party components keep their original licenses:

- `Vendor/PiRuntime/` is licensed under the MIT License documented in that
  directory.
- JavaScript dependencies are recorded in the root and prototype
  `package-lock.json` files. Generated bundles retain embedded upstream notices.
- Noto Sans CJK and Noto Serif CJK web fonts under `website/assets/fonts/` are
  licensed under the SIL Open Font License 1.1 included in that directory.
- Apple system frameworks are used under the terms supplied by Apple and are
  not part of this repository's AGPL grant.

See [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) for the distribution
notice and source locations.

## Reference and verification material

Third-party and public-domain reference assets are not relicensed under the
AGPL:

- `Attachments/RichAnswerVerificationAssets/` is governed by its
  `manifest.json` and `ATTRIBUTION.md`.
- `Sources/WeiBei/Resources/RichAnswerVerificationAssets/` is governed by its
  `ATTRIBUTION.md`.
- `Sources/WeiBei/Resources/Inspiration/` records the source and rights basis in
  `SOURCES.md` and in the associated catalog.

Preserve all required attribution and usage restrictions when using those
materials. A repository-wide license never overrides an upstream copyright,
public-domain statement, or attribution requirement.

## No private course content

WeiBei does not license or claim ownership of course files, notes, credentials,
or other content imported by a user. Those files remain under the control and
rights of their respective owners.
