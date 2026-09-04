# Release

Releases are tag-driven and use tags in the form `vMAJOR.MINOR.PATCH`.

## Preconditions

1. `VERSION` must contain the same semantic version as the tag without the `v` prefix.
2. The normal CI workflow must be green on the commit being tagged.
3. Configuration files and deployment state are not committed as release artifacts.

## Release flow

Create an annotated tag from the verified `main` commit, for example `v0.2.0`. GitHub Actions then:

- verifies the tag/version match;
- runs shell syntax validation;
- builds the non-root `Containerfile` with a fresh base image;
- pushes the versioned and `latest` images to GHCR;
- records the pushed image digest in the GitHub release;
- creates release notes from the tag history.

The immutable deployment reference is the published image digest, not `latest`.

## Deployment policy

Production should pin a release tag or image digest. `latest` is intended for development/convenience only.

For host installs, use `upgrade.sh` from the matching source tree. For rootless installs, use `upgrade-user.sh`. Both preserve the existing configuration and validate the upgraded tree before restoring a previously active service.

## Rollback

Rollback means redeploying the previous release tag or image digest. Existing configuration is retained separately from the release payload.
