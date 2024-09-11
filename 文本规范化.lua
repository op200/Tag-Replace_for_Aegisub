local gt=aegisub.gettext

script_name = gt"文本规范化"
script_description = gt"按自定义标准规范化文本"
script_author = "op200"
script_version = "0.1"
-- https://github.com/op200/Tag-Replace_for_Aegisub


local function debug(text)
	aegisub.dialog.display({{class="label",label=tostring(text):gsub("&", "&&")}})
end


local replace_table={
	{"吗%?$","吗"},{"吧%?$","吧"},{"呢%?$","呢"},{"吗？$","吗"},{"吧？$","吧"},{"呢？$","呢"},
	{"吗%?","吗 "},{"吧%?","吧 "},{"呢%?","呢 "},{"吗？","吗 "},{"吧？","吧 "},{"呢？","呢 "},
	{"“([^“”]*)”","\"".."%1".."\""},{"“([^“”]*)“","\"".."%1".."\""},
	{"”([^“”]*)”","\"".."%1".."\""},{"”([^“”]*)“","\"".."%1".."\""},
	{"帐号","账户"},{"锻链","锻炼"}
}

local warning_table={
	"!","%-","—","`","%.%.",
	"[%(%)]","（","）"
}


local function find_event(sub)
	for i=1,#sub do
		if sub[i].section=="[Events]" then
			return i
		end
	end
end


local function mark(sub, line_num)
	local new = sub[line_num]
	new.actor = new.actor.."[文本规范化 WARNING]"
	sub[line_num] = new
end


local function unmark(sub, line_num)
	local new = sub[line_num]
	new.actor = new.actor:gsub("%[文本规范化 WARNING%]","")
	sub[line_num] = new
end


local function initialize(sub,begin)
	for i = begin,#sub do
		unmark(sub,i)
	end
end


local function replace(sub, line_num)
	local new = sub[line_num]
	local text = new.text
	for _,compare in ipairs(replace_table) do
		text = text:gsub(compare[1],compare[2])
	end
	new.text = text
	sub[line_num] = new
end


local function warning(sub, line_num)
	local new = sub[line_num]
	local text = new.text
	for _,compare in ipairs(warning_table) do
		if text:gsub("{[^}]-}",""):find(compare) then
			mark(sub, line_num)
			return
		end
	end
end



local function do_macro(sub)
	local begin = find_event(sub)
	initialize(sub,begin)
	for i = begin,#sub do
		if not sub[i].comment and not sub[i].style:find("[oO][pP]") and not sub[i].style:find("[eE][dD]") then
			replace(sub,i)
			warning(sub,i)
		end
	end
end


local function macro_processing_function(subtitles)
	do_macro(subtitles)
end


local function macro_processing_function_initialize(subtitles)
	initialize(subtitles,find_event(subtitles))
end


aegisub.register_macro(script_name, script_description, macro_processing_function)
aegisub.register_macro(gt"清除文本规范化标记", gt"清除文本规范化标记", macro_processing_function_initialize)