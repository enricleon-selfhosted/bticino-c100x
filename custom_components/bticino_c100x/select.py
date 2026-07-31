"""What is on screen, and how loud it rings."""

from __future__ import annotations

from homeassistant.components.select import SelectEntity
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntitiesCallback

from .const import DOMAIN, VIEWS, VOLUMES
from .entity import IntercomEntity

async def async_setup_entry(
    hass: HomeAssistant, entry: ConfigEntry, add_entities: AddEntitiesCallback
) -> None:
    hub = hass.data[DOMAIN][entry.entry_id]
    add_entities([ViewSelect(hub), RingerVolumeSelect(hub)])

class ViewSelect(IntercomEntity, SelectEntity):
    """What the card should be showing."""

    _attr_name = "View"
    _attr_icon = "mdi:eye"
    _attr_options = VIEWS

    def __init__(self, hub) -> None:
        super().__init__(hub, "view")

    @property
    def current_option(self) -> str:
        return self.hub.view

    async def async_select_option(self, option: str) -> None:
        self.hub.set_view(option)

class RingerVolumeSelect(IntercomEntity, SelectEntity):
    """How loud the intercom rings."""

    _attr_name = "Ringer volume"
    _attr_icon = "mdi:volume-high"
    _attr_options = VOLUMES

    def __init__(self, hub) -> None:
        super().__init__(hub, "ringer_volume")

    @property
    def current_option(self) -> str:
        return self.hub.volume

    async def async_select_option(self, option: str) -> None:
        await self.hub.async_set_volume(option)
