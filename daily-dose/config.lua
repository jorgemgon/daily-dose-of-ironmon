-- Central constants for the Daily Dose of Ironmon extension.
-- Loadable without the tracker: no globals are touched at load time.

local Config = {}

Config.EXTENSION_KEY = "DailyDoseIronmon"
Config.EXTENSION_NAME = "Daily Dose of Ironmon"
Config.VERSION = "0.1.0"

-- Set at deploy time. Requests are refused while the host still ends in `.example.workers.dev`.
Config.DEFAULT_API_BASE = "http://127.0.0.1:8787"
Config.API_TIMEOUT_SECONDS = 20
Config.API_MIN_INTERVAL_SECONDS = 10
Config.API_MAX_RETRIES = 5

-- GBA runs at 59.7275 frames per second; in-game time is derived from emulated frames.
Config.GBA_FPS = 59.7275
Config.DAY_SECONDS = 86400
Config.GRACE_SECONDS = 6 * 3600
-- A start intent that is never confirmed releases the day after this long.
Config.INTENT_TTL_SECONDS = 2 * 3600

Config.MODE = "kaizo"
Config.RULE_SET = "kaizo"

-- FireRed (U) 1.1, the only supported base game in v1.
Config.SUPPORTED_BASE_SHA1 = "dd5945db9b930750cb39d00c84da8571feebf417"
Config.BASE_ROM_SIZE = 16777216
Config.BASE_ROM_NAME = "vanilla.gba"
Config.IPS_NAME = "faster-firered-1.2.ips"
-- Official Faster FireRed 1.2 release asset; downloaded on first use and hash-pinned.
Config.IPS_URL = "https://github.com/DrMaple/Faster-FireRed/releases/download/1.2/Faster.FireRed.1.2.ips"
Config.IPS_SHA256 = "c23fca99d6f0ab0ad107f0d8a7ceee7e8b2cde0c7bcf54ccbdca66ead77035c9"

Config.WEIGHTS_PRESET = "daily-v1"
Config.LOG_FORMAT = "zx"

-- Extension folder names (relative to <tracker>/extensions/).
Config.FOLDER = "daily-dose"
Config.ASSETS = "assets"
Config.JARS = "jars"
Config.STATE = "state"
Config.BASE = "base"
Config.ROMS = "roms"

-- Tracker interaction limits: never block the emulator in a per-frame hook.
Config.UPLOAD_INTERVAL_FRAMES = 600 -- 10 s at 60 fps
Config.TICK_INTERVAL_FRAMES = 30
Config.PERSIST_INTERVAL_FRAMES = 600

Config.HOTKEY_DEFAULT = "D"
Config.SCREEN_NAME = "Daily Dose"

return Config
