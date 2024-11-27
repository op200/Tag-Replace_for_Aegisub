local gt=aegisub.gettext

script_name = gt"Video Time Match"
script_description = gt"According to frame difference from two videos to match time. (Aegisub must load this video, the FPS of both videos must be the same and must be CFR)"
script_author = "op200"
script_version = "0.2"
-- https://github.com/op200/Tag-Replace_for_Aegisub

local function debug(text, to_exit)
	local button = aegisub.dialog.display({{class='label', label=tostring(text):gsub("&", "&&")}})
	if not button or to_exit then aegisub.cancel() end
end

local function find_event(sub)
	for i=1,#sub do
		if sub[i].section=="[Events]" then
			return i
		end
	end
end

local time_table = {}

local function get_time_table()
	local button, input = aegisub.dialog.display({
		{name='entry', height=4, width=5, class='textbox', hint=gt"Enter manually here"},
		{name='select', y=4, width=5, class='dropdown', items={gt"Manual entry", gt"Auto run VideoMatch"}, value=gt"Manual entry", hint=gt"If manual entry, use the textbox's content, else then run VideoMatch.exe"},
		{name='video1', y=5, width=5, class='edit', hint=gt"Enter video path 1 here"},
		{name='video2', y=6, width=5, class='edit', hint=gt"Enter video path 2 here"},
		{name='option', y=7, width=5, class='edit', text="-scale 4", hint=gt"Enter additional options here"}
	})
	if not button then aegisub.cancel() end

	local frame_result
	if input.select=="Manual entry" then
		frame_result = input.entry
	else
		local handle = io.popen('videomatch -i1 "'..input.video1:gsub('"','')..'" -i2 "'..input.video2:gsub('"','')..'" '..input.option.." & pause")
		frame_result = handle:read("*a")
		handle:close()
	end

	for line in frame_result:gmatch("[^\n]+") do
		local a,b = line:match("(%d+)%->([%d-]+)")
		if not a then break end
		a, b = tonumber(a), tonumber(b)
		if b==-1 then b = a end
		time_table[a] = b
	end
end

local function match_time(sub)
	local begin = find_event(sub)

	for i = begin,#sub do
		local line = sub[i]
		line.start_time, line.end_time = aegisub.ms_from_frame(aegisub.frame_from_ms(line.start_time)), aegisub.ms_from_frame(aegisub.frame_from_ms(line.end_time))
		sub[i] = line
	end

	for i = begin,#sub do
		local line = sub[i]

		local frame_1, frame_2 = aegisub.frame_from_ms(line.start_time), aegisub.frame_from_ms(line.end_time)
		local frame_1_new, frame_2_new = time_table[frame_1] or frame_1, time_table[frame_2] or frame_2

		if frame_1~=frame_1_new or frame_2~=frame_2_new then
			line.actor = line.actor.."[VTM]"
		end

		line.start_time, line.end_time = aegisub.ms_from_frame(frame_1_new), aegisub.ms_from_frame(frame_2_new)

		sub[i] = line
	end

	aegisub.set_undo_point("Match time and mark [VTM]")

	for i = begin,#sub do
		local line = sub[i]

		line.actor = line.actor:sub(1, -6)

		sub[i] = line
	end

	aegisub.set_undo_point("Clear [VTM]")
end

local function macro_processing_function(sub)
	if not os.execute("videomatch -v") then
		debug("This script need VideoMatch.exe", true)
	end

	get_time_table()

	match_time(sub)
end

aegisub.register_macro(script_name, script_description, macro_processing_function)