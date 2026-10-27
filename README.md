# AlwaysMute

A macOS menu bar app that keeps your Mac muted until you say so. Sound comes on only after two checks from the notch, and it re-mutes when headphones disconnect. No microphone access, no network.

Landing page: https://ericnguyendsg88.github.io/alwaysmute/

## Try it

[Download the Mac preview](https://github.com/ericnguyendsg88/alwaysmute/releases/latest). Unzip and move AlwaysMute.app to Applications. The download requires macOS 13 or later and an Apple silicon Mac.

The preview is ad-hoc signed, not notarized. If macOS blocks it, use System Settings → Privacy & Security → Open Anyway after attempting to open it. Only do this for a download you trust.

To build from source, install Xcode's command line tools (`xcode-select --install`):

```
git clone https://github.com/ericnguyendsg88/alwaysmute.git
cd alwaysmute
./build.sh
open AlwaysMute.app
```

Open the app or its speaker-shield menu bar icon.

## Sound protection

- Starts muted. Untrusted outputs require two confirmations before sound is enabled.
- Sound has no time limit. There are no timed auto-mute controls.
- Manual mute, sleep, screen lock, or quitting restores mute. Closing the window leaves protection running.
- Use **Start at login** to launch after signing in.

## Output settings

Open **Output settings…** in the main window or menu bar. Select an active output or a previously saved output.

**Trust this output:** off by default. After an explicit warning, this remembers permission to allow audio when that output is selected again. Setting trust never enables sound immediately. Launch and wake stay muted. Trust is not reapplied during the short settling period after a protection reset. Removing trust from an allowed output restores mute.

**Starting volume:** choose 1–100%, default 15%. It is saved independently for each output and used on the next confirmed or trusted unmute. Changing it does not change currently playing volume. Pending confirmations are invalidated when settings change. The final unmute confirmation lists the starting volumes.

Preferences use the device's persistent Core Audio identity plus its reported source/jack state, rather than the device name. Saved disconnected devices remain editable. Devices without a stable identity cannot be trusted. Devices without software volume control cannot be automatically enabled.

## Headphone protection

The app monitors default media/system outputs and reported source/jack changes, with a 100 ms fallback check. If the previous output disappears or audio falls back to built-in speakers, it restores mute even if the destination is trusted. It also handles wired output changes that retain the same device ID when the device reports source/jack state changes.

Trusted media outputs can be allowed while a separate untrusted system-alert output remains muted. A newly selected untrusted output is always muted first.

## Important limits

This is reactive protection, not an audio driver or an audio firewall. A brief sound can escape before macOS reports a change. Devices that do not report route or jack changes accurately can limit protection. Audio routed directly by another app to a non-default device, hardware-controlled HDMI/AirPlay outputs, boot sounds, and audio before login are outside guaranteed coverage. Unsupported outputs show a warning. No microphone access or network connection is used.

## Verified

- Build and local signature verification passed.
- State tests: locked startup, untimed permission, stale/duplicate confirmations, and manual lock.
- Simulated route-policy tests: external-device loss, external-to-speaker fallback, wired jack/source changes, trusted connection eligibility, missing identity, and unsupported controls.
- Preference tests: persistence, distinct device identities, default untrusted state, and volume bounds.
- Real MacBook Pro speaker test: remained muted and reset a volume disturbance to zero.
- Settings UI inspected; changing starting volume to 23% updated correctly, then restored to 15%.
- Physical Bluetooth/USB/wired headphone disconnection, audible trusted reconnect, and sleep/wake end-to-end behavior still need hardware validation.

## Build

Run `./build.sh`. Source files are in `Source/`.

Read-only checks:

```
AlwaysMute.app/Contents/MacOS/AlwaysMute --self-test
AlwaysMute.app/Contents/MacOS/AlwaysMute --diagnose
```

`--smoke-test` changes the current output to mute and tests volume restoration while hardware mute remains asserted. Run with the main app closed. It leaves the output muted.
