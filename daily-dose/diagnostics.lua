-- Determinism diagnostics. Reports contain hashes and environment details only — never ROM data.

local Diagnostics = {}

---@param deps table
---@return table report
function Diagnostics.build(deps)
	return {
		date = deps.date,
		mode = deps.mode or "kaizo",
		expected_sha1 = deps.expectedSha1,
		actual_sha1 = deps.actualSha1,
		stage = deps.stage,
		base_sha1 = deps.baseSha1,
		ips_sha256 = deps.ipsSha,
		settings_sha256 = deps.settingsSha,
		jar_sha256 = deps.jarSha,
		java = deps.javaVersion,
		os = deps.os,
		extension_version = deps.extensionVersion,
		note = deps.note,
	}
end

---@param report table
---@return string
function Diagnostics.format(report)
	local lines = {
		"Daily Dose of Ironmon — determinism report",
		"date: " .. tostring(report.date),
		"expected ROM SHA-1: " .. tostring(report.expected_sha1),
		"actual ROM SHA-1:   " .. tostring(report.actual_sha1),
		"diverging stage:    " .. tostring(report.stage or "final ROM hash"),
		"base SHA-1:         " .. tostring(report.base_sha1),
		"IPS SHA-256:        " .. tostring(report.ips_sha256),
		"settings SHA-256:   " .. tostring(report.settings_sha256),
		"jar SHA-256:        " .. tostring(report.jar_sha256),
		"java:               " .. tostring(report.java),
		"os:                 " .. tostring(report.os),
		"extension:          " .. tostring(report.extension_version),
	}
	if report.note then
		lines[#lines + 1] = "note: " .. tostring(report.note)
	end
	return table.concat(lines, "\n")
end

---@param api table
---@param report table
---@return table response
function Diagnostics.send(api, report)
	return api:diagnostics(report)
end

return Diagnostics
