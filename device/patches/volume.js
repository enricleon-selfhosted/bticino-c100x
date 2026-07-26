// GET /volume [?level=20|60|100] -> { "level": n }
const openwebnet = require('../openwebnet')

module.exports = class Api {

    path() {
        return "/volume"
    }

    description() {
        return "Reads or sets the ringer volume (10-100)"
    }

    handle(request, response, url, q) {
        const answer = (code, body) => {
            if (!response.headersSent) {
                response.writeHead(code, { "Content-Type": "application/json" })
            }
            response.end(JSON.stringify(body))
        }
        const read = (frame) => {
            const match = String(frame).match(/^\*#8\*\*41\*(\d+)[*#]/)
            return match ? Number(match[1]) : undefined
        }
        const withDeadline = (promise) => Promise.race([
            promise,
            new Promise((resolve, reject) =>
                setTimeout(() => reject(new Error('the intercom did not answer in time')), 10000))
        ])
        const describe = (error) => {
            if (error && error.message) return error.message
            if (error === undefined || error === null) return "the intercom refused the command"
            return String(error)
        }

        if (q.level !== undefined) {
            const asked = Number(q.level)
            if (!Number.isFinite(asked)) {
                answer(400, { error: "level must be a number between 10 and 100" })
                return true
            }
            const level = Math.min(100, Math.max(10, Math.round(asked / 10) * 10))
            withDeadline(openwebnet.run("ringerVolume", level)).then(
                (frame) => answer(200, { level: read(frame) !== undefined ? read(frame) : level, asked: asked }),
                (error) => answer(502, { error: describe(error) })
            )
            return true
        }

        withDeadline(openwebnet.run("ringerVolumeStatus")).then(
            (frame) => {
                const level = read(frame)
                if (level === undefined) {
                    answer(502, { error: "unexpected answer from the intercom", frame: String(frame) })
                } else {
                    answer(200, { level: level })
                }
            },
            (error) => answer(502, { error: describe(error) })
        )
        return true
    }
}
