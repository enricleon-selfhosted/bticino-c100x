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

Then Settings → Devices and services → Add integration → **Bticino Classe 100X**. It asks
for the intercom's address, and for the MQTT topic, which is already filled in.

That brings in the sensors, the buttons, the doorbell photo, the three dashboard cards and
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

The cards arrive with the integration and register themselves as a dashboard resource.
Dashboards managed in YAML need it added by hand:

```yaml
lovelace:
  resources:
    - url: /bticino_c100x/bticino-c100x-cards.js
      type: module
```

Add them to any dashboard:

```yaml
type: custom:intercom-video
connect_entity: binary_sensor.intercom_connect_video
talk_entity: binary_sensor.intercom_picked_up
```

`connect_entity` tells the card when to open the video, and `talk_entity` when to add your
microphone. Without `connect_entity` the card connects whenever it is on screen, which
keeps the intercom in a call.

A button per action. `tap_action` takes any of the integration's services:

```yaml
type: custom:intercom-button
name: Answer
icon: mdi:phone-in-talk
color: green
entity: binary_sensor.intercom_green_colour
blink_entity: binary_sensor.intercom_ready_to_answer
enabled_entity: binary_sensor.intercom_ready_to_answer
done_on: binary_sensor.intercom_picked_up
tap_action:
  service: bticino_c100x.pick_up
```

```yaml
type: custom:intercom-button
name: Open
icon: mdi:door-open
color: white
tap_action:
  service: bticino_c100x.open_door
```

`entity` colours it, `blink_entity` makes it pulse, `enabled_entity` greys it out when the
action makes no sense, and `done_on` / `done_off` end the pressed state when the intercom
confirms. The services are `open_door`, `pick_up`, `hang_up`, `look` and `capture_photo`.

The third card is the call history, like a phone's:

```yaml
type: custom:intercom-call-log
```

Every ring becomes an entry with its photo, answered or missed, and whether the door was
opened; tapping one shows the photo full size. `limit` (default 10) is optional. The
last 50 calls are kept, and a heading is yours to add like on any other card. The
card speaks English; translating is the dashboard's job, by overriding any of its
keys — dates already follow the instance's language:

```yaml
type: custom:intercom-call-log
labels:
  answered: Contestada
  missed: Perduda
  opened: Porta oberta
  not_opened: Porta sense obrir
  today: Avui
  yesterday: Ahir
  empty: Encara no hi ha trucades
```

## 7. Make the notification

The integration fires nothing at your phone by itself, because only you know which phone.
Two automations do it: one that buzzes immediately, and one that follows with the photo.

The photo is taken a few seconds into the ring, so attaching it to the first notification
would send the previous ring's picture. Instead both notifications carry the same `tag`,
and the second replaces the first on the screen.

```yaml
- alias: Doorbell notification
  triggers:
  - trigger: state
    entity_id: binary_sensor.intercom_ringing
    to: 'on'
  actions:
  - action: notify.mobile_app_your_phone
    data:
      title: "Front door"
      message: "Someone is at the door"
      data:
        tag: doorbell
        url: /lovelace/home#call
        clickAction: /lovelace/home#call
        actions:
        - action: OPEN_DOOR
          title: Open the door

- alias: Doorbell photo
  triggers:
  - trigger: state
    entity_id: binary_sensor.intercom_ringing
    to: 'on'
  actions:
  - wait_for_trigger:
    - trigger: state
      entity_id: image.intercom_doorbell_photo
    timeout: '00:00:20'
    continue_on_timeout: true
  - action: notify.mobile_app_your_phone
    data:
      title: "Front door"
      message: "Someone is at the door"
      data:
        tag: doorbell
        url: /lovelace/home#call
        clickAction: /lovelace/home#call
        image: "/bticino_c100x/media/doorbell_last.jpg"
        attachment:
          url: "/bticino_c100x/media/doorbell_last.jpg"
          content-type: jpeg
        actions:
        - action: OPEN_DOOR
          title: Open the door
```

An iPhone reads `attachment`, an Android phone `image`; each ignores the other. Keep the
path bare: the photo is served with caching disabled, so a cache-buster adds nothing —
and the iOS app percent-encodes `?` in relative attachment paths, turning the query into
a filename that 404s. Tapping **Open the door** opens it: the integration listens for
the `OPEN_DOOR` action itself. `url` (iOS) and `clickAction` (Android) point at the
dashboard that holds the call-log card; the `#call` at the end makes the card open the
latest call's detail on arrival.

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
