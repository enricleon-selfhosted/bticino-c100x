"""The one place that knows what the intercom is doing."""

from __future__ import annotations

import asyncio
import logging
from typing import Any, Callable

import aiohttp

from homeassistant.components import mqtt, persistent_notification
from homeassistant.components.mqtt.models import ReceiveMessage
from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers.aiohttp_client import async_get_clientsession
from homeassistant.helpers.event import async_call_later
from homeassistant.util.json import json_loads_object

from .const import (
    BUS_IDLE,
    BUS_RING_STATES,
    BUS_STAIRCASE_LIGHT,
    EVENT_RING,
    MEDIA_DIRNAME,
    PHOTO_FILENAME,
    PHOTO_MAX_BYTES,
    PHOTO_MIN_BYTES,
    PORT_CONTROLLER,
    PORT_GO2RTC,
    STATUS_TIMEOUT,
    STREAM_PHOTO,
    VIEW_DOOR,
    VIEW_OFF,
    VOLUME_LEVELS,
    VOLUME_SILENT,
)

_LOGGER = logging.getLogger(__name__)

class IntercomHub:
    """Holds the state of one intercom, and does the talking to it."""

    def __init__(self, hass: HomeAssistant, host: str, topic: str) -> None:
        self.hass = hass
        self.host = host
        self.topic = topic

        self.bus_state: str | None = None
        self.last_bus_message: str | None = None
        self.uptime: int | None = None
        self.signal: int | None = None
        self.temperature: float | None = None

        self.ringing = False
        self.picked_up = False
        self.connecting = False
        self.hanging_up = False
        self.video_on_screen = False
        self.silenced = False
        self.view = VIEW_OFF
        self.volume = "Medium"
        self.microphone = ""
        self.photo: bytes | None = None

        self._status_alive = False
        self._expiry: Callable[[], None] | None = None
        self._unsubscribe: list[Callable[[], None]] = []
        self._listeners: list[Callable[[], None]] = []
        self._refreshing = False

    @callback
    def add_listener(self, update: Callable[[], None]) -> Callable[[], None]:
        """Register something that wants to hear about changes."""
        self._listeners.append(update)

        def remove() -> None:
            self._listeners.remove(update)

        return remove

    @callback
    def _changed(self) -> None:
        for update in list(self._listeners):
            update()

    async def async_start(self) -> None:
        """Start listening to the intercom."""
        self._unsubscribe = [
            await mqtt.async_subscribe(self.hass, f"{self.topic}/state", self._on_state),
            await mqtt.async_subscribe(self.hass, f"{self.topic}/status", self._on_status),
            await mqtt.async_subscribe(self.hass, f"{self.topic}/all_events", self._on_event),
            await mqtt.async_subscribe(self.hass, f"{self.topic}/doorbell", self._on_doorbell),
            await mqtt.async_subscribe(self.hass, f"{self.topic}/lock/+", self._on_lock),
        ]

    @callback
    def async_stop(self) -> None:
        for unsubscribe in self._unsubscribe:
            unsubscribe()
        self._unsubscribe = []
        if self._expiry:
            self._expiry()
            self._expiry = None

    @callback
    def _on_state(self, message: ReceiveMessage) -> None:
        was_in_call = self.call_in_progress
        self.bus_state = message.payload.strip()

        if self.bus_state in BUS_RING_STATES:
            self._ring_started()
        if was_in_call and not self.call_in_progress:
            self._call_ended()
        self._changed()

    @callback
    def _on_status(self, message: ReceiveMessage) -> None:
        try:
            report = json_loads_object(message.payload)
        except ValueError:
            _LOGGER.debug("health report was not readable: %s", message.payload)
            return

        was = self.uptime
        uptime = report.get("uptime_seconds")
        self.uptime = round(float(uptime)) if uptime is not None else None
        self.signal = report.get("signal_dbm")
        temperature = report.get("temperature")
        if isinstance(temperature, str):
            temperature = temperature.replace("°C", "").replace("C", "").strip()
        self.temperature = float(temperature) if temperature not in (None, "") else None

        if was is not None and self.uptime is not None and 0 <= self.uptime < was:
            persistent_notification.async_create(
                self.hass,
                f"The intercom restarted. It had been on for {round(was / 60)} minutes.",
                title="Intercom restarted",
            )

        self._status_alive = True
        if self._expiry:
            self._expiry()
        self._expiry = async_call_later(self.hass, STATUS_TIMEOUT, self._status_expired)
        self._changed()

    @callback
    def _status_expired(self, _now: Any) -> None:
        """Three missed health reports: stop believing anything derived from them."""
        self._expiry = None
        was_in_call = self.call_in_progress
        self._status_alive = False
        if was_in_call:
            self._call_ended()
        self._changed()

    @callback
    def _on_event(self, message: ReceiveMessage) -> None:
        self.last_bus_message = message.payload.strip()

        if self.last_bus_message == BUS_STAIRCASE_LIGHT:
            persistent_notification.async_create(
                self.hass, "The staircase light was switched on.", title="Intercom"
            )
        self._changed()

    @callback
    def _on_doorbell(self, message: ReceiveMessage) -> None:
        """The controller decodes the bus; a ring arrives here already named."""
        if message.payload == "pressed":
            self._ring_started()

    @callback
    def _on_lock(self, message: ReceiveMessage) -> None:
        """The controller decodes the lock traffic; this only hears the verdict."""
        if message.payload == "unlocked":
            persistent_notification.async_create(
                self.hass, "The street door was opened.", title="Intercom"
            )

    @callback
    def _ring_started(self) -> None:
        """Somebody is at the door."""
        if self.ringing:
            return
        self.ringing = True
        self.hass.bus.async_fire(EVENT_RING, {"host": self.host})
        self.hass.async_create_task(self._show_the_door())
        self.hass.async_create_task(self._photo_of_the_ring())

    async def _photo_of_the_ring(self) -> None:
        """Take the photo once there is something to photograph."""
        for _ in range(40):
            if self.video_on_screen:
                break
            await asyncio.sleep(0.1)
        await self.async_capture_photo()

    async def _show_the_door(self) -> None:
        if self._refreshing:
            return
        self._refreshing = True
        try:
            if self.view == VIEW_DOOR:
                self.view = VIEW_OFF
                self._changed()
                await asyncio.sleep(0.7)
            self.view = VIEW_DOOR
            self._changed()
        finally:
            self._refreshing = False

    @callback
    def _call_ended(self) -> None:
        """The intercom says the call is over, so everything hanging off it lets go."""
        self.ringing = False
        self.picked_up = False
        self.video_on_screen = False
        self.hanging_up = False
        self.connecting = False
        self.view = VIEW_OFF

    @property
    def available(self) -> bool:
        """Whether the intercom is still reporting for duty."""
        return self._status_alive

    @property
    def call_in_progress(self) -> bool:
        """A real call, as the intercom itself reports it."""
        return (
            self.bus_state not in (None, "", BUS_IDLE)
            and self._status_alive
        )

    @property
    def idle(self) -> bool:
        return self.bus_state in (None, "", BUS_IDLE)

    @property
    def ready_to_answer(self) -> bool:
        """Flashing green: there is a call and nobody has picked up."""
        return self.video_on_screen and not self.picked_up

    @property
    def green_colour(self) -> bool:
        """Green once there is a picture, not when the bus says there is one."""
        return self.video_on_screen

    @property
    def connect_video(self) -> bool:
        """The single answer the card follows."""
        return (self.view == VIEW_DOOR or self.picked_up) and not self.hanging_up

    @property
    def show_door_camera(self) -> bool:
        """Follows what was asked for, and never "because there is a call"."""
        return self.view == VIEW_DOOR or self.picked_up or self.ringing

    @callback
    def set_view(self, view: str) -> None:
        self.view = view
        self._changed()

    @callback
    def set_video_on_screen(self, on_screen: bool) -> None:
        """The card reporting that the first frame has arrived."""
        self.video_on_screen = on_screen
        if on_screen:
            self.connecting = False
        self._changed()

    @callback
    def set_microphone(self, state: str) -> None:
        self.microphone = state
        self._changed()

    async def async_pick_up(self) -> None:
        self.picked_up = True
        self.view = VIEW_DOOR
        self._changed()

    async def async_hang_up(self) -> None:
        """Hanging up means disconnecting whoever is watching: the video is the call."""
        self.hanging_up = True
        self.picked_up = False
        self.view = VIEW_OFF
        self._changed()

    async def async_look(self) -> None:
        """Turn the door camera on, or off again."""
        self.view = VIEW_OFF if self.view != VIEW_OFF else VIEW_DOOR
        self._changed()

    async def async_open_door(self) -> None:
        await self._command("/unlock", id="default")

    async def async_set_silenced(self, silenced: bool) -> None:
        self.silenced = silenced
        self._changed()
        await self._command("/mute", enable="true" if silenced else "false")

    async def async_set_volume(self, position: str) -> None:
        """Set the ringer volume on the bus, which takes effect at once."""
        self.volume = position
        self._changed()
        if position == VOLUME_SILENT:
            await self.async_set_silenced(True)
            return
        await self._command("/volume", level=VOLUME_LEVELS[position])
        await self.async_set_silenced(False)

    async def _command(self, path: str, **params: Any) -> None:
        """Ask the controller to do something."""
        session = async_get_clientsession(self.hass)
        url = f"http://{self.host}:{PORT_CONTROLLER}{path}"
        try:
            await session.get(
                url,
                params={**params, "raw": "true"},
                timeout=aiohttp.ClientTimeout(total=5),
            )
        except (aiohttp.ClientError, asyncio.TimeoutError) as err:
            _LOGGER.debug("%s answered as it usually does: %s", path, err)

    async def async_capture_photo(self) -> bytes | None:
        """Ask go2rtc for one frame of the door."""
        frame = await self._frame()
        if frame is not None and len(frame) > PHOTO_MAX_BYTES:
            _LOGGER.debug("the frame looks like noise (%d bytes), trying once more", len(frame))
            await asyncio.sleep(3)
            frame = await self._frame()

        if frame is None or not PHOTO_MIN_BYTES < len(frame) <= PHOTO_MAX_BYTES:
            _LOGGER.debug("no usable frame, keeping the previous photo")
            return None

        self.photo = frame
        await self.hass.async_add_executor_job(self._write_photo, frame)
        self._changed()
        return frame

    async def _frame(self) -> bytes | None:
        session = async_get_clientsession(self.hass)
        url = f"http://{self.host}:{PORT_GO2RTC}/api/frame.jpeg"
        try:
            async with session.get(
                url, params={"src": STREAM_PHOTO}, timeout=aiohttp.ClientTimeout(total=25)
            ) as response:
                if response.status != 200:
                    return None
                return await response.read()
        except (aiohttp.ClientError, asyncio.TimeoutError) as err:
            _LOGGER.debug("could not get a frame: %s", err)
            return None

    def _write_photo(self, frame: bytes) -> None:
        """Also leave it where a phone can fetch it, at the address in PHOTO_URL."""
        import os

        directory = self.hass.config.path(MEDIA_DIRNAME)
        os.makedirs(directory, exist_ok=True)
        final = os.path.join(directory, PHOTO_FILENAME)
        partial = f"{final}.part"
        with open(partial, "wb") as handle:
            handle.write(frame)
        os.replace(partial, final)
