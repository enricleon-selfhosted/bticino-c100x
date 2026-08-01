"""Getting the live video into a browser."""

from __future__ import annotations

import asyncio
import logging

from aiohttp import ClientError, WSMsgType, web

from homeassistant.components.http import HomeAssistantView
from homeassistant.helpers.aiohttp_client import async_get_clientsession

from .const import DOMAIN, PORT_GO2RTC, STREAM_LIVE

_LOGGER = logging.getLogger(__name__)

class WebRTCSignallingView(HomeAssistantView):
    """Passes the handshake between a browser and the intercom."""

    url = f"/api/{DOMAIN}/ws"
    name = f"api:{DOMAIN}:ws"
    requires_auth = False

    async def get(self, request: web.Request) -> web.StreamResponse:
        if not request.get("hass_user"):
            return web.Response(status=401)

        hass = request.app["hass"]
        hubs = list(hass.data.get(DOMAIN, {}).values())
        if not hubs:
            return web.Response(status=404, text="no intercom is set up")

        hub = hubs[0]
        entry_id = request.query.get("entry")
        if entry_id and entry_id in hass.data[DOMAIN]:
            hub = hass.data[DOMAIN][entry_id]

        source = request.query.get("src", STREAM_LIVE)
        browser = web.WebSocketResponse(heartbeat=30)
        await browser.prepare(request)

        session = async_get_clientsession(hass)
        url = f"http://{hub.host}:{PORT_GO2RTC}/api/ws"
        try:
            async with session.ws_connect(url, params={"src": source}) as intercom:
                await _introduce(browser, intercom)
        except (ClientError, asyncio.TimeoutError) as err:
            _LOGGER.error("could not reach the intercom's video service: %s", err)
            await browser.close()

        return browser

async def _introduce(browser: web.WebSocketResponse, intercom) -> None:
    """Carry messages both ways until either side hangs up."""
    both = [
        asyncio.create_task(_relay(browser, intercom)),
        asyncio.create_task(_relay(intercom, browser)),
    ]
    try:
        await asyncio.wait(both, return_when=asyncio.FIRST_COMPLETED)
    finally:
        for task in both:
            task.cancel()
        await asyncio.gather(*both, return_exceptions=True)

async def _relay(source, target) -> None:
    async for message in source:
        if message.type == WSMsgType.TEXT:
            await target.send_str(message.data)
        elif message.type == WSMsgType.BINARY:
            await target.send_bytes(message.data)
        else:
            break
