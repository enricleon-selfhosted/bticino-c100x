"""Asking where the intercom is."""

from __future__ import annotations

import asyncio
from typing import Any

import voluptuous as vol

from homeassistant.config_entries import ConfigFlow, ConfigFlowResult
from homeassistant.const import CONF_HOST

from .const import CONF_TOPIC, DEFAULT_TOPIC, DOMAIN, PORT_CONTROLLER

async def _reachable(host: str) -> bool:
    """Is something answering where the controller should be?."""
    try:
        async with asyncio.timeout(5):
            reader, writer = await asyncio.open_connection(host, PORT_CONTROLLER)
            writer.close()
            await writer.wait_closed()
            return True
    except (OSError, asyncio.TimeoutError):
        return False

class BticinoConfigFlow(ConfigFlow, domain=DOMAIN):
    """Set the intercom up from the interface."""

    VERSION = 1

    async def async_step_user(
        self, user_input: dict[str, Any] | None = None
    ) -> ConfigFlowResult:
        errors: dict[str, str] = {}

        if user_input is not None:
            host = user_input[CONF_HOST].strip()
            await self.async_set_unique_id(host)
            self._abort_if_unique_id_configured()

            if await _reachable(host):
                return self.async_create_entry(
                    title=f"Intercom ({host})",
                    data={CONF_HOST: host, CONF_TOPIC: user_input[CONF_TOPIC].strip()},
                )
            errors["base"] = "cannot_connect"

        return self.async_show_form(
            step_id="user",
            data_schema=vol.Schema(
                {
                    vol.Required(CONF_HOST, default=user_input[CONF_HOST] if user_input else ""): str,
                    vol.Required(CONF_TOPIC, default=DEFAULT_TOPIC): str,
                }
            ),
            errors=errors,
        )
