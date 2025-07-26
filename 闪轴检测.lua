local tr=aegisub.gettext

script_name = tr"闪轴检测"
script_description = tr"标记出所有闪轴行"
script_author = "op200"
script_version = "0.1.1"
-- https://github.com/op200/Tag-Replace_for_Aegisub



local function initialize(sub,begin)
	local findline=begin
	while findline <= #sub do
		if sub[findline].actor:find("mayFlash$") then
			local new_line=sub[findline]
			new_line.actor = new_line.actor:sub(1,-9)
			sub[findline] = new_line
		end
		findline = findline+1
	end
end


local function find_event(sub)
	for i=1,#sub do
		if sub[i].section=="[Events]" then
			return i
		end
	end
end


local function do_macro(sub)
	local line_num=find_event(sub)
	initialize(sub,line_num)
	repeat
		line_num=line_num+1

		local difference = sub[line_num].start_time - sub[line_num-1].end_time
		if difference ~= 0 and difference < 350 and difference > -50 then
			local new_line=sub[line_num-1]
			new_line.actor = new_line.actor.."mayFlash"
			sub[line_num-1] = new_line
		end

	until line_num==#sub
end


local function macro_processing_function(subtitles)--Execute Macro. 执行宏
	do_macro(subtitles)
end



local function macro_processing_function_initialize(subtitles)--初始化
	initialize(subtitles,find_event(subtitles))
end


aegisub.register_macro(tr"检测闪轴", tr"标记出可能为闪轴的行", macro_processing_function)
aegisub.register_macro(tr"清除闪轴标记", tr"清除闪轴标记", macro_processing_function_initialize)