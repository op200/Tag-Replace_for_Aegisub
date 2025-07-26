local tr=aegisub.gettext

script_name = tr"重设帧率"
script_description = tr"重设帧率"
script_author = "op200"
script_version = "0.1"
-- https://github.com/op200/Tag-Replace_for_Aegisub


function debug(text, to_exit)
   local button = aegisub.dialog.display({{class="label",label=tostring(text):gsub("&", "&&")}})
   if not button or to_exit then aegisub.cancel() end
end


local function find_event(sub)
	for i = 1, #sub do
		if sub[i].section == "[Events]" then
			return i
		end
	end
end


local function macro_processing_function(subtitles)
   local dialog = {
      {class="label", label="原帧率分子", x=0, y=0},
      {class="intedit", name="org_fps_n", value=24, min=0, x=0, y=1},

      {class="label", label="原帧率分母", x=0, y=2},
      {class="intedit", name="org_fps_d", value=1, min=1, x=0, y=3},

      {class="label", label="目标帧率分子", x=1, y=0},
      {class="intedit", name="target_fps_n", value=24000, min=0, x=1, y=1},

      {class="label", label="目标帧率分母", x=1, y=2},
      {class="intedit", name="target_fps_d", value=1001, min=1, x=1, y=3}
   }

	local ret, res = aegisub.dialog.display(dialog)
   if not ret then
      aegisub.cancel()
   end

   local org_fps_n, org_fps_d, target_fps_n, target_fps_d
      = res["org_fps_n"], res["org_fps_d"], res["target_fps_n"], res["target_fps_d"]
   local factor = org_fps_d * target_fps_n / target_fps_d / org_fps_n
   
   for i = find_event(subtitles), #subtitles do
      local line = subtitles[i]

      line.start_time = line.start_time * factor
      line.end_time = line.end_time * factor

      subtitles[i] = line
   end
end





aegisub.register_macro(tr"重设帧率", tr"重设帧率", macro_processing_function)