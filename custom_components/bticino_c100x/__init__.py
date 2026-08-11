"""Bticino Classe 100X, controlled from your own network."""

from __future__ import annotations

import logging
import os
from functools import partial

import voluptuous as vol

from homeassistant.config_entries import ConfigEntry
from homeassistant.const import CONF_HOST, Platform
from homeassistant.core import HomeAssistant, ServiceCall
from homeassistant.helpers import config_validation as cv

from .const import CONF_TOPIC, DEFAULT_TOPIC, DOMAIN, MEDIA_DIRNAME, MEDIA_URL
from .coordinator import IntercomHub
from .webrtc import WebRTCSignallingView

_LOGGER = logging.getLogger(__name__)

PLATFORMS: list[Platform] = [
    Platform.BINARY_SENSOR,
    Platform.BUTTON,
    Platform.IMAGE,
    Platform.SELECT,
    Platform.SENSOR,
    Platform.SWITCH,
]

CARD_FILENAME = "bticino-c100x-cards.js"
CARD_URL = f"/{DOMAIN}/{CARD_FILENAME}"
REGISTERED = f"{DOMAIN}_registered"

REPORT_SCHEMA = vol.Schema({vol.Required("value"): cv.boolean})
MICROPHONE_SCHEMA = vol.Schema({vol.Required("value"): cv.string})

async def async_setup_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    """Set up one intercom."""
    hub = IntercomHub(
        hass, entry.data[CONF_HOST], entry.data.get(CONF_TOPIC, DEFAULT_TOPIC)
    )
    await hub.async_start()

    hass.data.setdefault(DOMAIN, {})[entry.entry_id] = hub
    await hass.config_entries.async_forward_entry_setups(entry, PLATFORMS)

    if not hass.data.get(REGISTERED):
        hass.data[REGISTERED] = True
        try:
            await _async_register_once(hass)
        except Exception:
            hass.data[REGISTERED] = False
            raise

    _register_services(hass)
    return True

async def async_unload_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    """Take one intercom away again."""
    unloaded = await hass.config_entries.async_unload_platforms(entry, PLATFORMS)
    if unloaded:
        hub: IntercomHub = hass.data[DOMAIN].pop(entry.entry_id)
        hub.async_stop()
    return unloaded

async def _async_register_once(hass: HomeAssistant) -> None:
    """Register the cards and the signalling endpoint."""
    hass.http.register_view(WebRTCSignallingView)

    media = hass.config.path(MEDIA_DIRNAME)
    await hass.async_add_executor_job(partial(os.makedirs, media, exist_ok=True))

    here = os.path.dirname(__file__)
    source = os.path.join(here, "www")
    if not os.path.isdir(source):
        return

    # The card URL is versioned so it can be cached; the media dir holds the
    # doorbell photo, which is overwritten in place and must not be.
    paths = [(f"/{DOMAIN}", source, True), (MEDIA_URL, media, False)]
    try:
        from homeassistant.components.http import StaticPathConfig

        await hass.http.async_register_static_paths(
            [StaticPathConfig(url, path, cache) for url, path, cache in paths]
        )
    except ImportError:
        for url, path, cache in paths:
            hass.http.register_static_path(url, path, cache)

    # A Lovelace resource is awaited before cards are built; add_extra_js_url
    # is a fire-and-forget import the dashboard does not wait for, so it is
    # only the fallback when resources cannot be written (YAML mode, old HA).
    if not await _async_register_card_resource(hass):
        from homeassistant.components.frontend import add_extra_js_url

        add_extra_js_url(hass, CARD_URL)

async def _async_register_card_resource(hass: HomeAssistant) -> bool:
    """Put the card in Lovelace's resource list. True when it is there."""
    try:
        from homeassistant.components.lovelace.const import LOVELACE_DATA
        from homeassistant.loader import async_get_integration

        resources = getattr(hass.data.get(LOVELACE_DATA), "resources", None)
        if resources is None or not hasattr(resources, "async_create_item"):
            return False
        if not resources.loaded:
            await resources.async_load()
            resources.loaded = True

        version = (await async_get_integration(hass, DOMAIN)).version
        url = f"{CARD_URL}?v={version}"
        for item in resources.async_items():
            if item["url"].split("?")[0] == CARD_URL:
                if item["url"] != url:
                    await resources.async_update_item(item["id"], {"url": url})
                return True
        await resources.async_create_item({"res_type": "module", "url": url})
        return True
    except Exception:
        _LOGGER.warning("Could not add the card to the dashboard resources", exc_info=True)
        return False

def _register_services(hass: HomeAssistant) -> None:
    """The things you can ask the intercom to do."""
    if hass.services.has_service(DOMAIN, "open_door"):
        return

    def hubs() -> list[IntercomHub]:
        return list(hass.data[DOMAIN].values())

    async def open_door(_call: ServiceCall) -> None:
        for hub in hubs():
            await hub.async_open_door()

    async def pick_up(_call: ServiceCall) -> None:
        for hub in hubs():
            await hub.async_pick_up()

    async def hang_up(_call: ServiceCall) -> None:
        for hub in hubs():
            await hub.async_hang_up()

    async def look(_call: ServiceCall) -> None:
        for hub in hubs():
            await hub.async_look()

    async def capture_photo(_call: ServiceCall) -> None:
        for hub in hubs():
            await hub.async_capture_photo()

    async def video_on_screen(call: ServiceCall) -> None:
        for hub in hubs():
            hub.set_video_on_screen(call.data["value"])

    async def microphone_state(call: ServiceCall) -> None:
        for hub in hubs():
            hub.set_microphone(call.data["value"])

    hass.services.async_register(DOMAIN, "open_door", open_door)
    hass.services.async_register(DOMAIN, "pick_up", pick_up)
    hass.services.async_register(DOMAIN, "hang_up", hang_up)
    hass.services.async_register(DOMAIN, "look", look)
    hass.services.async_register(DOMAIN, "capture_photo", capture_photo)
    hass.services.async_register(DOMAIN, "video_on_screen", video_on_screen, REPORT_SCHEMA)
    hass.services.async_register(DOMAIN, "microphone_state", microphone_state, MICROPHONE_SCHEMA)

    async def from_notification(event) -> None:
        if event.data.get("action") == "OPEN_DOOR":
            for hub in hubs():
                await hub.async_open_door()

    hass.bus.async_listen("mobile_app_notification_action", from_notification)
