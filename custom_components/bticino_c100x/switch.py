"""The intercom's own ringer, silenced or restored from Home Assistant."""

from __future__ import annotations

from typing import Any

from homeassistant.components.switch import SwitchEntity
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntitiesCallback

from .const import DOMAIN
from .entity import IntercomEntity

async def async_setup_entry(
    hass: HomeAssistant, entry: ConfigEntry, add_entities: AddEntitiesCallback
) -> None:
    add_entities([DoorbellRinger(hass.data[DOMAIN][entry.entry_id])])

class DoorbellRinger(IntercomEntity, SwitchEntity):
    """On means the doorbell rings downstairs, off means it is silenced."""

    _attr_name = "Doorbell ringer"
    _attr_icon = "mdi:bell-ring"

    def __init__(self, hub) -> None:
        super().__init__(hub, "doorbell_ringer")

    @property
    def is_on(self) -> bool:
        return not self.hub.silenced

    async def async_turn_on(self, **kwargs: Any) -> None:
        await self.hub.async_set_silenced(False)

    async def async_turn_off(self, **kwargs: Any) -> None:
        await self.hub.async_set_silenced(True)
