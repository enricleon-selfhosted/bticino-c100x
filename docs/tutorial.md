# Walkthrough

The whole installation in order. Allow an afternoon the first time; most of it is waiting.

## Before you start

- A Bticino Classe 100X, firmware 1.5.8
- Home Assistant, with an MQTT broker reachable from your network
- A Windows machine with MyHomeSuite, for the flashing step
- An RSA or ECDSA ssh key. The intercom runs Dropbear 2017, which does not know ed25519:

```sh
ssh-keygen -t rsa -b 4096
```

Replacing the firmware leaves the intercom unusable until the flash finishes, so pick a day
when being without a doorbell is fine.

## 1. Build the firmware

On any machine:

```sh
curl -fsSL https://raw.githubusercontent.com/enricleon-selfhosted/bticino-c100x/main/install.sh | sh
```

It asks about a dozen things; enter takes the suggestion. The ones worth attention:

- **Your MQTT broker.** Usually the machine running Home Assistant. Username and password
  can be empty if your broker allows it.
- **Your ssh key.** Paste the contents of `~/.ssh/id_rsa.pub`.
- **The fallback password.** Leave it empty and the installer makes one up, different for
  every install, and prints it at the end.
- **Bticino's cloud.** **off** patches the intercom's answering machine so its SIP server
  starts without a certificate from Bticino, and points Bticino's Azure endpoint at the
  intercom itself. **on** does neither and leaves the firmware as it came. Everything else
  this project installs is the same either way.

It ends with a path and a checksum:

```
== Done
   firmware/build/C100X-1.5.8-local.fwz
   d76cc2fbbfd17935fc6635b44a2901a2
```

Copy that file, about 140 MB, to the Windows machine.

## 2. Flash it

1. Connect the intercom to your network with a cable
2. Open MyHomeSuite, find the intercom, choose to update its firmware
3. Point it at the `.fwz` file
4. Wait. It takes several minutes and the unit restarts on its own

The intercom comes back behaving as before — everything added is invisible until Home
Assistant is set up.

If the unit has not been paired with the Door Entry app, do that now, exactly as the
manual says: pairing is what gives it the SIP domain everything else is built on, and the
setup on the intercom stops and waits until it is there.

## 3. Get in over ssh

```sh
ssh root2@<the intercom's address>
```

Your router's device list shows the address; the name starts with `BTICINO`. Because the
intercom's ssh server predates the signature format OpenSSH now expects, put this in
`~/.ssh/config` once:

```
Host intercom
    HostName <the intercom's address>
    User root2
    IdentityFile ~/.ssh/id_rsa
    IdentitiesOnly yes
    HostKeyAlgorithms +ssh-rsa
    PubkeyAcceptedAlgorithms +ssh-rsa
    PubkeyAcceptedKeyTypes +ssh-rsa
```

Then `ssh intercom` is enough. The controller is already running:

```sh
ps -ef | grep [b]undle.js
```

## 4. Add it to Home Assistant

Install this repository through HACS: three dots, Custom repositories, this repository's
address, category **Integration**. Restart Home Assistant.

Then Settings → Devices and services → Add integration → **Bticino Classe 100X**, and give
it the intercom's address.

That brings in the sensors, the buttons, the doorbell photo, the two dashboard cards and
the live video together. In **Developer tools → States** these exist:

```
sensor.intercom_bus_state
binary_sensor.intercom_ringing
sensor.intercom_temperature
```

`sensor.intercom_bus_state` is a number from 0 to 6 describing what the door system is
doing. At rest it is `0`.

## 5. Ring the bell

Press the button downstairs:

1. `binary_sensor.intercom_ringing` turns on within about a second
2. `sensor.intercom_bus_state` goes `1`, `2`, `4`, `6`, then back to `0`
3. `image.intercom_doorbell_photo` shows whoever is at the door

## 6. Place the cards

The cards arrive with the integration. Add them to any dashboard:

```yaml
type: custom:intercom-video
```

```yaml
type: custom:intercom-button
name: Open
icon: mdi:door-open
color: green
tap_action:
  service: bticino_c100x.open_door
```

## 7. Make the notification

Settings → Automations → Create automation:

- **When:** `binary_sensor.intercom_ringing` turns on
- **Then:** send a notification to your phone

For the photo, add `image: /bticino_c100x/media/doorbell_last.jpg` to the notification data
on Android, or on iPhone:

```yaml
attachment:
  url: /bticino_c100x/media/doorbell_last.jpg
  content-type: jpeg
```

To open the door from the notification, give it an action named `OPEN_DOOR`.

## What cutting the cloud does

`cloud.mode: off` does two things, and `on` does neither:

- **Patches `bt_answering_machine`.** Four jumps, eleven bytes, so its SIP server starts
  without a certificate from Bticino. The original is kept on the intercom, and the patch
  is derived again if a firmware update changes the binary underneath.
- **Points `eliot-iotHub.azure-devices.net` at `127.0.0.1`,** so the cloud agent cannot
  reach Bticino. It keeps running; it just gets nowhere.

Answering yes to blocking firmware updates adds `eliotdmstrg.blob.core.windows.net` as
well, which stops the unit downloading a firmware that would replace everything here.

Both hosts entries are written on every boot, because that file lives in memory and is
empty again after a restart. To change your mind later, build and flash again with the
other answer.
