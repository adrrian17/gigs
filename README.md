# Gigs

![Gigs in the menu bar](Assets/hero.png)

Gigs keeps your Mac's free disk space in the menu bar, so you notice it's running low before macOS tells you.

- The number is the gigabytes available on your startup disk. The ring around it fills with the share of the disk that's still free.
- The icon turns red when less than 20 GB are left, and Gigs offers to clean up.
- Clean Up… deletes caches and logs with the cleanup script from [Mole](https://github.com/tw93/mole), bundled in `Mole/`.
- Click it to see available and total space, for example "186 GB available of 494 GB".
- It updates every minute. Press ⌘R in the menu to refresh right away.
- The number matches Finder: space macOS can purge on its own counts as free.
- No Dock icon, no window. It opens at login and stays out of the way.

Requires macOS 14 and Swift 6.

## Install

```sh
./install.sh
```

Builds the app, replaces `/Applications/Gigs.app`, and launches it. Gigs adds itself to Login Items on first launch.

## Distribute

```sh
./package.sh
```

Builds a universal (Apple Silicon and Intel) `.build/Gigs.dmg`. Open it and drag Gigs to Applications.

Pushing a `v*` tag (`git tag v1.0.0 && git push origin v1.0.0`) builds the DMG on GitHub Actions and attaches it to a new release.

The app is signed ad hoc, not with a Developer ID, so macOS blocks the first launch on other Macs. Open System Settings › Privacy & Security and click Open Anyway.

## Run without installing

```sh
swift run
```

## License

GPL-3.0. See [LICENSE](LICENSE). Includes code from [Mole](https://github.com/tw93/mole), also GPL-3.0.
