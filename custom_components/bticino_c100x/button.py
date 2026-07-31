"""A button for the street door, for people who would rather have one sitting there."""

from __future__ import annotations

from homeassistant.components.button import ButtonEntity
from homeassistant.components.persistent_notification import async_create
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntitiesCallback

from .const import DOMAIN
from .entity import IntercomEntity

async def async_setup_entry(
    hass: HomeAssistant, entry: ConfigEntry, add_entities: AddEntitiesCallback
) -> None:
    add_entities([OpenStreetDoor(hass.data[DOMAIN][entry.entry_id])])

class OpenStreetDoor(IntercomEntity, ButtonEntity):
    _attr_name = "Open the street door"
    _attr_icon = "mdi:door-open"

    def __init__(self, hub) -> None:
        super().__init__(hub, "open_street_door")

    async def async_press(self) -> None:
        await self.hub.async_open_door()
        async_create(
            self.hass, "The street door was opened from Home Assistant.", title="Intercom"
        )
