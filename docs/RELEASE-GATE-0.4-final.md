# proxy-agent 0.4.0 Release Gate

Release candidate baseline: `0.4.x`.

Final verified commit before mainline synchronization: `84f62ed8e06b5e8f9274cfb783988f203ec45775`.

## Automated gates

- CI: PASS
- Lifecycle Gate: PASS
- Upgrade Transaction Gate: PASS
- `real-backends`: manual-only; not counted as automated PASS

## Version boundary

`VERSION` is `0.4.0`. The release tag must be exactly `v0.4.0`.

The release workflow validates the tag against `VERSION`, performs shell syntax checks, builds the non-root container, publishes the versioned and `latest` images, records the image digest, and creates the GitHub Release.

## Finalization order

1. Synchronize the verified `0.4.x` snapshot with `main` ancestry.
2. Create immutable tag `v0.4.0` on the verified release commit.
3. Let the tag-triggered Release workflow build and publish the release artifacts.
4. Record the published image digest as the immutable deployment reference.
5. Keep `0.4.x` as the 0.4 maintenance line after release; future development moves to the next version line.
