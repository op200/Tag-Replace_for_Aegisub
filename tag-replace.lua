local util = require("aegisub.util")
require("karaskel")

local tr=aegisub.gettext

script_name = tr"Tag Replace"
script_description = tr"Replace string such as tag"
script_author = "op200"
script_version = "2.4.1"
-- https://github.com/op200/Tag-Replace_for_Aegisub


local user_var--自定义变量键值表
user_var={
	sub,
	subcache={},
	kdur={0,0},--存储方式为前缀和，从[2]开始计数，方便相对值计算
	begin,
	temp_line,
	bere_line,
	keytext="",
	keyclip="",
	forcefps=false,
	bere_text="",
	cuttime={
		frame_model=true,
		accel=1,
		interpolate=function(current_time, total_time, start_value, end_value, tag)
			local factor = (end_value - start_value) / ((total_time ^ user_var.cuttime.accel) - 1)
			return start_value + factor * ((current_time ^ user_var.cuttime.accel) - 1)
		end
	},
	--功能性
	deepCopy=function(add)
		if add == nil then return nil end
		local copy={}
		for k,v in pairs(add) do
			if type(v) == "table" then
				copy[k] = user_var.deepCopy(v)
			else
				copy[k] = v
			end
		end
		setmetatable(copy, user_var.deepCopy(getmetatable(add)))
		return copy
	end,
	debug=function(text, to_exit)
		local button = aegisub.dialog.display({{class="label",label=tostring(text):gsub("&", "&&")}})
		if not button or to_exit then aegisub.cancel() end
	end,
	--后处理
	postProc=function(line)
	end,
	classmixProc=function(first, second)
		if not (first and second) then return first or second end
		local new = first
		new.text = new.text..second.text
		local effect_table = {new.effect:match("([^@]*@[^#]*)(.*)")}
		new.effect = effect_table[1]..';'..second.effect:match("@([^#]*)")..effect_table[2]
		return new
	end,
	--处理
	colorGradient=function(line_info, rgba, step_set, tags, control_points, pos)
		-- 计算组合数
		math.comb = function(n, k)
			if k > n then return 0 end
			if k == 0 or k == n then return 1 end
			k = math.min(k, n - k) -- 对称性
			local c = 1
			for i = 1, k do
				c = c * (n - i + 1) / i
			end
			return c
		end

		-- 计算贝塞尔曲线插值
		local function bezier_interpolate(t, control_points_list)
			local n = #control_points_list - 1
			local interpolated_color = {0, 0, 0, 0}
			for i = 0, n do
				local binomial_coeff = math.comb(n, i)
				local u = (1 - t) ^ (n - i)
				local tt = t ^ i
				for j = 1, 4 do
					interpolated_color[j] = interpolated_color[j] + binomial_coeff * u * tt * control_points_list[i + 1][j]
				end
			end
			return interpolated_color
		end

		-- 计算双线性插值
		local function bilinear_interpolate(x, y, color00, color01, color10, color11)
			local r = color00[1] * (1 - x) * (1 - y) + color01[1] * x * (1 - y) + color10[1] * (1 - x) * y + color11[1] * x * y
			local g = color00[2] * (1 - x) * (1 - y) + color01[2] * x * (1 - y) + color10[2] * (1 - x) * y + color11[2] * x * y
			local b = color00[3] * (1 - x) * (1 - y) + color01[3] * x * (1 - y) + color10[3] * (1 - x) * y + color11[3] * x * y
			local a = color00[4] * (1 - x) * (1 - y) + color01[4] * x * (1 - y) + color10[4] * (1 - x) * y + color11[4] * x * y
			return {r, g, b, a}
		end

		local meta, styles = karaskel.collect_head(user_var.sub)
		local pos_line, line_num
	
		if type(line_info) == "table" then
			x1, y1, x2, y2 = line_info[1], line_info[2], line_info[3], line_info[4]
			line_num = line_info[5] or user_var.bere_line
	
			pos_line = user_var.sub[line_num]
			karaskel.preproc_line_pos(meta, styles, pos_line)
		else
			line_num = line_info

			pos_line = user_var.sub[line_num]
			karaskel.preproc_line_pos(meta, styles, pos_line)

			local expand = step_set[3] or 0
			if type(expand)=="number" then expand={expand,expand,expand,expand} end
			x1, y1, x2, y2 = pos_line.left - expand[1], pos_line.top - expand[2], pos_line.right + expand[3], pos_line.bottom + expand[4]
		end

		pos = pos or {nil,nil}
		local pos_x, pos_y = pos[1] or pos_line.x, pos[2] or pos_line.y
		x1, y1, x2, y2 = x1+pos_x-pos_line.x, y1+pos_y-pos_line.y, x2+pos_x-pos_line.x, y2+pos_y-pos_line.y

		local color1, color2, color3, color4 = rgba[1], rgba[2], rgba[3], rgba[4]
		if type(color1) == "string" then color1 = {util.extract_color(color1)} end
		if type(color2) == "string" then color2 = {util.extract_color(color2)} end
		if type(color3) == "string" then color3 = {util.extract_color(color3)} end
		if type(color4) == "string" then color4 = {util.extract_color(color4)} end

		-- 计算矩形的宽度和高度
		local rect_width = x2 - x1
		local rect_height = y2 - y1

		step_set = step_set or {nil, nil}
		step_set[1] = step_set[1] or rect_width + 1
		step_set[2] = step_set[2] or rect_height + 1

		tags = tags or {nil, nil}
		color_tag = tags[1] or "c"
		transparent_tag = tags[2] or "1a"

		control_points = control_points or {color1, color2, color3, color4}
		for i = 1, #control_points do
			if type(control_points[i]) == "string" then
				control_points[i] = {util.extract_color(control_points[i])}
			end
		end

		-- 检测 control_points 的数量并选择插值方法
		local use_bilinear = #control_points == 4
		local use_bezier = #control_points >= 6

		-- 遍历矩形中的每个点
		for x = x1, x2, step_set[1] do
			for y = y1, y2, step_set[2] do
				-- 计算点(x, y)在矩形中的相对位置
				local dx = (x - x1) / rect_width
				local dy = (y - y1) / rect_height

				local interpolated_color
				if use_bilinear then
					-- 使用双线性插值计算RGBA值
					local color00 = control_points[1]
					local color01 = control_points[2]
					local color10 = control_points[3]
					local color11 = control_points[4]
					interpolated_color = bilinear_interpolate(dx, dy, color00, color01, color10, color11)
				elseif use_bezier then
					-- 使用贝塞尔曲线插值计算RGBA值
					local bezier_top = bezier_interpolate(dx, {color1, control_points[1], control_points[2], color2})
					local bezier_bottom = bezier_interpolate(dx, {color3, control_points[3], control_points[4], color4})
					interpolated_color = bezier_interpolate(dy, {bezier_top, control_points[5], control_points[6], bezier_bottom})
				else
					-- 默认情况下使用贝塞尔曲线插值
					local bezier_top = bezier_interpolate(dx, {color1, control_points[1], control_points[2], color2})
					local bezier_bottom = bezier_interpolate(dx, {color3, control_points[3], control_points[4], color4})
					interpolated_color = bezier_interpolate(dy, {bezier_top, control_points[5], control_points[6], bezier_bottom})
				end

				-- 确保 interpolated_color 是四个有效的整数值
				local r, g, b, a = math.floor(interpolated_color[1] + 0.5), math.floor(interpolated_color[2] + 0.5), math.floor(interpolated_color[3] + 0.5), math.floor(interpolated_color[4] + 0.5)
				if r and g and b and a then
					local subline = user_var.sub[line_num]
					subline.text = string.format("{\\clip(%.2f,%.2f,%.2f,%.2f)\\%s%s\\%s%s\\pos(%s,%s)}%s",
						x, y, x + step_set[1], y + step_set[2],
						color_tag, util.ass_color(interpolated_color[1], interpolated_color[2], interpolated_color[3]),
						transparent_tag, util.ass_alpha(interpolated_color[4]),
						pos_x, pos_y,
						subline.text)
					table.insert(user_var.subcache, subline)
				else
					user_var.debug("Error: interpolated_color does not contain 4 valid elements: " .. r .. ", " .. g .. ", " .. b .. ", " .. a, true)
				end
			end
		end
	end,
	getTagCut=function(text)
		local result = {}
		local text_pos = 1
		local pos_1, pos_2, last_pos_2 = 1, 1, 0
		local text_num, tag_num = 1, 1

		while true do
			pos_1, pos_2 = text:find("{.-}", pos_2)
			if not pos_1 then break end

			local t = text:sub(text_pos, pos_1-1)
			if t~="" then
				table.insert(result, {t, false, text_num})
				text_num = text_num+1
			end
			table.insert(result, {text:sub(pos_1, pos_2), true, tag_num})
			tag_num = tag_num+1

			text_pos = pos_2+1
			last_pos_2 = pos_2
		end
		local t = text:sub(last_pos_2+1, -1)
		if t~="" then
			table.insert(result, {t, false, text_num})
		end

		return result
	end,
	--外部
	cmdCode=function(cmd, popen)
		if popen then
			local handle = io.popen(cmd)
			local output = handle:read("*a")
			handle:close()
			return output
		else
			return os.execute(cmd)
		end
	end,
	pyCode=function(cmd, popen)
		return user_var.cmdCode([[python -c "]]..cmd..'"', popen)
	end
}
local org_user_var = user_var.deepCopy(user_var)

local function initialize(sub,begin)
	user_var = org_user_var.deepCopy(org_user_var)

	local findline=begin
	aegisub.progress.title(tr"Tag Replace - Initializing")
	while findline<=#sub do
		if aegisub.progress.is_cancelled() then aegisub.cancel() end
		aegisub.progress.set(100*findline/#sub)

		if sub[findline].effect:find("^beretag!") then--删除beretag!行
			sub.delete(findline)
		elseif sub[findline].effect:find("^:beretag@") then--还原:beretag@行
			local new_line=sub[findline]
			new_line.comment=false
			new_line.effect=new_line.effect:sub(2)
			sub[findline]=new_line
			findline=findline+1
		else
			findline=findline+1
		end
	end
end

local function get_class(effect,is_temp)
	local class={}
	if is_temp then
		for word in effect:match("@([^#]*)#"):gmatch("[^;]+") do
			table.insert(class,word)
		end
	else
		if effect:find("^beretag[@!]") then
			for word in effect:match("[@!]([^#]*)$"):gmatch("[^;]+") do
				table.insert(class,word)
			end
		end
	end
	return class
end

local function cmp_class(temp_effct,bere_effct)
	local temp_class=get_class(temp_effct,true)

	local bere_class=get_class(bere_effct,false)

	for i,j in ipairs(temp_class) do
		for p,k in ipairs(bere_class) do
			if j==k then return true end
		end
	end
	return false
end

local function get_mode(effect)--return table
	local modestring = effect:match("#(.*)$")
	local mode={
		recache=false,
		cuttag=false,
		strictstyle=false,
		strictactor=false,
		findtext=false,
		append=false,
		keyframe=false,
		uninsert=false,
		cuttime=false,
		classmix=false,
		onlyfind=false
	}
	if modestring:len()==0 then
		return mode
	end

	for word in modestring:gmatch("[^;]+") do
		if mode[word]~=nil then
			mode[word]=true
		end
	end
	return mode
end

local function var_expansion(text, re_num, sub)--input文本和replace次数，通过re_num映射karaok变量至变量表
	--扩展表达式中的$部分
	local pos1, pos2 = 1, 1
	while true do
		local pos3, pos4 = text:find("!.-!", pos2)
		if not pos3 then break end
		local sub_str = text:sub(pos3+1,pos4-1)
		while true do
			local pos5, pos6 = sub_str:find("%$[%w_]+")
			if not pos5 then break end
			local var = sub_str:sub(pos5+1,pos6)
			if var~="" then--扩展预留关键词
				if var=="kdur" then
					sub_str = sub_str:sub(1,pos5-1)..(user_var.kdur[re_num]-user_var.kdur[re_num-1])..sub_str:sub(pos6+1)
				elseif var=="start" then
					sub_str = sub_str:sub(1,pos5-1)..(user_var.kdur[re_num-1]*10)..sub_str:sub(pos6+1)
				elseif var=="end" then
					sub_str = sub_str:sub(1,pos5-1)..(user_var.kdur[re_num]*10)..sub_str:sub(pos6+1)
				elseif var=="mid" then
					sub_str = sub_str:sub(1,pos5-1)..math.floor((user_var.kdur[re_num-1] + user_var.kdur[re_num]) * 5)..sub_str:sub(pos6+1)
				else
					sub_str = sub_str:sub(1,pos5-1).."user_var."..var..sub_str:sub(pos6+1)
				end
			end
		end
		text = text:sub(1,pos3)..sub_str..text:sub(pos4)

		pos1, pos2 = text:find("!.-!", pos2)
		pos2 = pos2+1
	end
	--扩展变量
	while true do
		pos1, pos2 = text:find("%$[%w_]+")
		if not pos1 then break end
		local var = text:sub(pos1+1,pos2)
		if var~="" then--扩展预留关键词
			if var=="kdur" then
				text = text:sub(1,pos1-1)..(user_var.kdur[re_num]-user_var.kdur[re_num-1])..text:sub(pos2+1)
			elseif var=="start" then
				text = text:sub(1,pos1-1)..(user_var.kdur[re_num-1]*10)..text:sub(pos2+1)
			elseif var=="end" then
				text = text:sub(1,pos1-1)..(user_var.kdur[re_num]*10)..text:sub(pos2+1)
			elseif var=="mid" then
				text = text:sub(1,pos1-1)..math.floor((user_var.kdur[re_num-1] + user_var.kdur[re_num]) * 5)..text:sub(pos2+1)
			else
				--扩展用户变量(这里必须给text赋值，否则扩展表达式无变量使用)
				if user_var[var]~=nil then
					text = text:sub(1,pos1-1)..user_var[var]..text:sub(pos2+1)
				else
					text = text:sub(1,pos1-1).."user_var."..var..text:sub(pos2+1)
				end
			end
		end
	end
	--扩展表达式
	while true do
		pos1, pos2 = text:find("!.-!")
		if not pos1 then break end
		local load_fun, err = load("return function(sub,user_var) "..text:sub(pos1+1,pos2-1).." end")
		if not load_fun then
			user_var.debug(tr"[var_expansion] Error in template line "..(user_var.temp_line-user_var.begin+1)..": "..err)
			aegisub.cancel()
		end
		local return_str = load_fun()(sub,user_var)
		if not return_str then return_str="" end
		text = text:sub(1,pos1-1)..return_str..text:sub(pos2+1)
	end
	return text
end

local append_num

local function do_replace(sub, bere, mode, begin)--return int
	if sub[bere].comment or not sub[bere].effect:find("^beretag") then return 1 end--若该行被注释或为非beretag行，则跳过
	if not cmp_class(sub[user_var.temp_line].effect,sub[bere].effect) then return 1 end--判断该行class是否与模板行class有交集
	--准备replace
	local insert_line, insert_table=sub[bere], {}
	local find_pos, kdur_num=1, 2
	while true do--写入kdur表
		local pos1, pos2 = insert_line.text:find("\\k%d*",find_pos)
		if not pos1 then break end
		if pos1+1==pos2 then--防止\k后无值
			user_var.kdur[kdur_num] = user_var.kdur[kdur_num-1]
		else
			user_var.kdur[kdur_num] = user_var.kdur[kdur_num-1] + tonumber(insert_line.text:sub(pos1+2,pos2))
		end
		find_pos, kdur_num = pos2+1, kdur_num+1
	end
	--执行replace
	--根据mode判断替换方式
	local temp_tag, temp_add_tail = sub[user_var.temp_line].text:match("^{(.-)}"), sub[user_var.temp_line].text:match("^{.-}(.*)")
	local temp_re_tag, temp_add_text = temp_add_tail:match("^{(.-)}"), temp_add_tail:match("^{.-}(.*)")

	local find_pos, re_num=1, 2 --re_num从2开始计数
	if mode.cuttag then
		--找到每个temp_tag的位置，将这些位置(除了第一个)前面的{的位置和结尾的位置写入pos_table，根据pos_table写入insert_table，最后替换insert_table的值
		local pos_table={}
		if mode.findtext then
			while true do--写入pos_table
				local pos1, pos2 = insert_line.text:find(var_expansion(temp_tag,re_num,sub), find_pos)--记录找到的temp_tag位置
				if not pos1 then break end
				table.insert(pos_table,pos1)
				find_pos, re_num = pos2+1, re_num+1
			end

			pos_table[1], re_num=1, 2
			table.insert(pos_table,insert_line.text:len()+1)
			for i=1,#pos_table-1 do
				local new_text = insert_line.text:sub(pos_table[i],pos_table[i+1]-1)
				local pos1, pos2 = new_text:find(var_expansion(temp_tag,re_num,sub))
				user_var.bere_text = new_text:sub(pos1,pos2)

				new_text = new_text:sub(1,pos1-1) .. var_expansion(temp_re_tag,re_num,sub) .. new_text:sub(pos2+1)
				table.insert(insert_table, new_text)
				re_num = re_num+1
			end
		else
			while true do--写入pos_table
				local pos1, pos2 = insert_line.text:find(var_expansion(temp_tag,re_num,sub), find_pos)--记录找到的temp_tag位置
				if not pos1 then break end
				while pos1>=1 do
					if insert_line.text:byte(pos1)==string.byte("{") then break end
					pos1=pos1-1
				end
				table.insert(pos_table,pos1)
				find_pos, re_num = insert_line.text:find("}",pos2+1)+1, re_num+1
			end

			pos_table[1], re_num=1, 2
			table.insert(pos_table,insert_line.text:len()+1)
			for i=1,#pos_table-1 do
				local new_text = insert_line.text:sub(pos_table[i],pos_table[i+1]-1)
				local pos1, pos2 = new_text:find(var_expansion(temp_tag,re_num,sub))
				user_var.bere_text = new_text:sub(pos1,pos2)
				
				new_text = new_text:sub(1,pos1-1) .. var_expansion(temp_re_tag,re_num,sub) .. new_text:sub(pos2+1)
				table.insert(insert_table, new_text)
				re_num = re_num+1
			end
		end
	elseif mode.cuttime then
		local fps = user_var.forcefps or 23.976

		local end_value_table = {}
		for v in temp_re_tag:gmatch("[^\\]+") do
			local pos=({v:find("^%d*%l+")})[2]
			local head, value = v:sub(1,pos), v:sub(pos+1)
			if value:find("^%(.*%)$") then
				value=value:match("%((.*)%)")
				local val={}
				for i in value:gmatch("[^,]+") do
					table.insert(val,i)
				end
				end_value_table[head]=val
			else
				end_value_table[head]={value}
			end
		end

		local value_table = {}
		for v in temp_tag:gmatch("[^\\]+") do
			local pos=({v:find("^%d*%l+")})[2]
			local head, value = v:sub(1,pos), v:sub(pos+1)
			if value:find("^%(.*%)$") then
				value=value:match("%((.*)%)")
				local val={}
				local i=1
				for p in value:gmatch("[^,]+") do
					table.insert(val,{p,end_value_table[head][i]})
					i=i+1
				end
				table.insert(value_table, {head, val})
			else
				table.insert(value_table, {head, {{value, end_value_table[head][1]}}})
			end
		end

		--判断并转换值类型
		for i=1,#value_table do
			for p=1,#value_table[i][2] do
				if value_table[i][2][p][1]:find("^[%d%.]+$") then--十进制
					value_table[i][3]=10
				elseif value_table[i][2][p][1]:find("^&H%w+&?$") then--ASS颜色格式
					value_table[i][3]="rgb"
					local rgba={{util.extract_color(value_table[i][2][p][1])}, {util.extract_color(value_table[i][2][p][2])}}
					if rgba[1][4]~=0 then value_table[i][3]="a" end
					value_table[i][2][p]=rgba
				elseif value_table[i][2][p][1]:find("^%w+$") then--十六进制
					value_table[i][3]=16
					value_table[i][2][p]={tonumber(value_table[i][2][p][1],16), tonumber(value_table[i][2][p][2],16)}
				else
					user_var.debug(tr"[cuttime] Unsupported format: "..value_table[i][2][p][1])
				end
			end
		end


		local function _typeChange(value, v_type)
			if v_type==10 then
				return math.floor(value*1000+0.5)/1000
			elseif v_type==16 then
				return string.format("%X",value)
			elseif v_type=="rgb" then
				return util.ass_color(value[1],value[2],value[3])
			elseif v_type=="a" then
				util.ass_alpha(value[4])
			end
		end

		local function _valueCalculation(current_time, total_time, value, pos)
			if type(value[3])=="number" then
				return user_var.cuttime.interpolate(current_time, total_time, value[2][pos][1], value[2][pos][2], value[1])
			else
				return {user_var.cuttime.interpolate(current_time, total_time, value[2][pos][1][1], value[2][pos][2][1], value[1]),
						user_var.cuttime.interpolate(current_time, total_time, value[2][pos][1][2], value[2][pos][2][2], value[1]),
						user_var.cuttime.interpolate(current_time, total_time, value[2][pos][1][3], value[2][pos][2][3], value[1]),
						user_var.cuttime.interpolate(current_time, total_time, value[2][pos][1][4], value[2][pos][2][4], value[1])}
			end
		end

		local function _getTag(current_time,total_time,value_table,end_value_table)
			local result=""

			for i=1,#value_table do
				if #value_table[i][2]==1 then
					result = result.."\\"..value_table[i][1].._typeChange(_valueCalculation(current_time, total_time, value_table[i], 1), value_table[i][3])
				else
					local str=""
					for p=1,#value_table[i][2] do
						str=str.._typeChange(_valueCalculation(current_time, total_time, value_table[i], p), value_table[i][3])..","
					end
					result = result.."\\"..value_table[i][1].."("..str:sub(1,-2)..")"
				end
			end

			return "{"..result.."}"
		end
		
		if user_var.cuttime.frame_model and aegisub.video_size() then
			local start_f, end_f = aegisub.frame_from_ms(insert_line.start_time), aegisub.frame_from_ms(insert_line.end_time)
			local total_time = end_f-start_f
			for i=1,total_time do
				local line = user_var.deepCopy(insert_line)
				line.effect = "beretag!"..line.effect:sub(9)
				line.start_time = aegisub.ms_from_frame(start_f+i-1)
				line.end_time = aegisub.ms_from_frame(start_f+i)
				line.text = _getTag(i,total_time,value_table,end_value_table)..line.text
				table.insert(insert_table,line)
			end
		else
			local total_time = math.ceil((insert_line.end_time - insert_line.start_time)*fps/1000)
			local start_time = insert_line.start_time
			if start_time<=0 then start_time = -400/fps end
			local now_time = start_time
			for i=1,total_time do
				local line = user_var.deepCopy(insert_line)
				line.effect = "beretag!"..line.effect:sub(9)
				line.start_time = now_time
				now_time = start_time + i*1000/fps
				if now_time>=insert_line.end_time then
					now_time=insert_line.end_time
				end
				line.end_time = now_time
				line.text = _getTag(i,total_time,value_table,end_value_table)..line.text
				table.insert(insert_table,line)
			end
		end
	else
		--循环找到insert_line里所有的temp_tag
		if temp_tag=="" then--考虑到{}的情况
			temp_tag="none"
			insert_line.text = insert_line.text:gsub("}","none}")
		end
		while true do
			if mode.findtext then
				local pos1, pos2 = insert_line.text:find(var_expansion(temp_tag,re_num,sub), find_pos)--记录找到的temp_tag位置
				if not pos1 then break end
				user_var.bere_text = insert_line.text:sub(pos1,pos2)

				find_pos = pos2 + 1 - insert_line.text:len()--先减原长再加新长，防止出现正则表达式导致的字数不同问题
				insert_line.text = insert_line.text:sub(1,pos1-1)..var_expansion(temp_add_tail,re_num,sub)..insert_line.text:sub(pos2+1)--插入temp_add_tail
				find_pos = find_pos + insert_line.text:len()

				re_num = re_num+1
			else
				local pos1, pos2 = insert_line.text:find(var_expansion(temp_tag,re_num,sub), find_pos)--记录找到的temp_tag位置
				if not pos1 then break end
				user_var.bere_text = insert_line.text:sub(pos1,pos2)
				--先在}后插入temp_add_text，再替换temp_tag为temp_re_tag
				local pos3 = insert_line.text:find("}",pos2+1)--记录temp_tag后的}的位置

				local new_temp_add_text=var_expansion(temp_add_text,re_num,sub)
				insert_line.text = insert_line.text:sub(1,pos3)..new_temp_add_text..insert_line.text:sub(pos3+1)--插入new_temp_add_text
				pos3 = pos3 + new_temp_add_text:len() - insert_line.text:len()--因为temp_tag含有正则表达式，无法直接获取长度，所以pos3先减原长，循环结束时再加新长

				insert_line.text = insert_line.text:sub(1,pos1-1)..var_expansion(temp_re_tag,re_num,sub)..insert_line.text:sub(pos2+1)--插入temp_re_tag
				
				find_pos = insert_line.text:find("{", pos3 + insert_line.text:len() + 1)
				if not find_pos then break end
				
				re_num = re_num+1
			end
		end
	end

	--判断该行类型，第一次替换则注释该行，多次替换则删除该行
	local function _do_insert(pos,insert_content)
		if mode.uninsert then
			return 0 --下文调用该函数时虽然return不同，但这里都返回0
		end

		local postProc = user_var.postProc

		if mode.cuttime then
			local i=1
			if mode.append then
				while i<=#insert_table do
					insert_content = insert_table[i]
					postProc(insert_content)
					sub[0] = insert_content
					i, append_num = i+1, append_num+1
				end
				return 1
			else
				while i<=#insert_table do
					insert_content = insert_table[i]
					postProc(insert_content)
					sub.insert(pos+i-1,insert_content)
					i = i+1
				end
				return i-1
			end
		end

		if mode.cuttag then
			local i=1
			if mode.append then
				while i<=#insert_table do
					insert_content.text = insert_table[i]
					postProc(insert_content)
					sub[0] = insert_content
					i, append_num = i+1, append_num+1
				end
				return 1
			else
				while i<=#insert_table do
					insert_content.text = insert_table[i]
					postProc(insert_content)
					sub.insert(pos+i-1,insert_content)
					i = i+1
				end
				return i-1
			end
		end

		postProc(insert_content)
		if mode.append then
			sub[0] = insert_content
			append_num = append_num+1
			return 0
		else
			sub.insert(pos,insert_content)
			return 1
		end
	end

	if sub[bere].effect:find("^beretag!") then--删除行
		--这里插入和删除的顺序不能更改，否则会导致逆天bug
		local add_line_num = _do_insert(bere+1,insert_line)
		sub.delete(bere)
		if mode.append and bere < user_var.temp_line then
			user_var.temp_line=user_var.temp_line-1
		end
		return add_line_num
	end
	--注释行，并在effect头部加上:
	local tocmt=sub[bere]
	tocmt.comment=true
	tocmt.effect=":"..tocmt.effect
	sub[bere]=tocmt
	--将@改为!
	insert_line.effect="beretag!"..insert_line.effect:sub(9)
	local add_line_num = _do_insert(bere+1,insert_line)
	return add_line_num+1
end

local function find_event(sub)
	for i=1,#sub do
		if sub[i].section=="[Events]" then
			return i
		end
	end
end

local function do_macro(sub)
	local progress_refresh_time=0
	local begin=find_event(sub)
	initialize(sub,begin)--初始化，删除所有beretag!行，并还原:beretag@行
	user_var.temp_line=begin
	user_var.sub=sub
	user_var.begin=begin
	append_num=0--初始化append边界
	aegisub.progress.title(tr"Tag Replace - Replace")
	local progress_total = 0
	for i = begin, #sub do
		if sub[i].effect:find("^template") and sub[i].comment then
			progress_total = progress_total + 1
		end
	end
	while user_var.temp_line<=#sub do
		if aegisub.progress.is_cancelled() then aegisub.cancel() end
		aegisub.progress.set(100*user_var.temp_line/progress_total)

		--Find template lines. 检索模板行
		if sub[user_var.temp_line].comment then
			if sub[user_var.temp_line].effect:find("^template@[^#]-#.*$") then
				local mode = get_mode(sub[user_var.temp_line].effect)
				local bere = begin
				--根据mode判断
				if mode.classmix then
					local first_table,second_table = {},{}
					local to_comment
					if mode.strictstyle then
						if mode.strictactor then
							for bere = begin, #sub - append_num do
								local temp_line,bere_line = sub[user_var.temp_line],sub[bere]
								if temp_line.style == bere_line.style and temp_line.actor == bere_line.actor and cmp_class(temp_line.effect,bere_line.effect) then
									to_comment = false
									local first_class, second_class = temp_line.text:match("^{(.-)}"), temp_line.text:match("^{.-}{(.-)}")
									if cmp_class('@'..first_class..'#',bere_line.effect) then
										table.insert(first_table, user_var.deepCopy(bere_line))
										to_comment = true
									end
									if cmp_class('@'..second_class..'#',bere_line.effect) then
										table.insert(second_table, user_var.deepCopy(bere_line))
										to_comment = true
									end
									if to_comment then
										if bere_line.effect:find("^beretag@") then
											bere_line.effect = ':'..bere_line.effect
										end
										bere_line.comment = true
										sub[bere] = bere_line
									end
								end
							end
						else
							for bere = begin, #sub - append_num do
								local temp_line,bere_line = sub[user_var.temp_line],sub[bere]
								if sub[user_var.temp_line].style == sub[bere].style and cmp_class(temp_line.effect,bere_line.effect) then
									to_comment = false
									local first_class, second_class = temp_line.text:match("^{(.-)}"), temp_line.text:match("^{.-}{(.-)}")
									if cmp_class('@'..first_class..'#',bere_line.effect) then
										table.insert(first_table, user_var.deepCopy(bere_line))
										to_comment = true
									end
									if cmp_class('@'..second_class..'#',bere_line.effect) then
										table.insert(second_table, user_var.deepCopy(bere_line))
										to_comment = true
									end
									if to_comment then
										if bere_line.effect:find("^beretag@") then
											bere_line.effect = ':'..bere_line.effect
										end
										bere_line.comment = true
										sub[bere] = bere_line
									end
								end
							end
						end
					elseif mode.strictactor then
						for bere = begin, #sub - append_num do
							local temp_line,bere_line = sub[user_var.temp_line],sub[bere]
							if sub[user_var.temp_line].actor == sub[bere].actor and cmp_class(temp_line.effect,bere_line.effect) then
								to_comment = false
								local first_class, second_class = temp_line.text:match("^{(.-)}"), temp_line.text:match("^{.-}{(.-)}")
								if cmp_class('@'..first_class..'#',bere_line.effect) then
									table.insert(first_table, user_var.deepCopy(bere_line))
									to_comment = true
								end
								if cmp_class('@'..second_class..'#',bere_line.effect) then
									table.insert(second, user_var.deepCopy(bere_line))
									to_comment = true
								end
								if to_comment then
									if bere_line.effect:find("^beretag@") then
										bere_line.effect = ':'..bere_line.effect
									end
									bere_line.comment = true
									sub[bere] = bere_line
								end
							end
						end
					else
						for bere = begin, #sub - append_num do
							local temp_line,bere_line = sub[user_var.temp_line],sub[bere]
							if cmp_class(temp_line.effect,bere_line.effect) then
								to_comment = false
								local first_class, second_class = temp_line.text:match("^{(.-)}"), temp_line.text:match("^{.-}{(.-)}")
								if cmp_class('@'..first_class..'#',bere_line.effect) then
									table.insert(first_table, user_var.deepCopy(bere_line))
									to_comment = true
								end
								if cmp_class('@'..second_class..'#',bere_line.effect) then
									table.insert(second_table, user_var.deepCopy(bere_line))
									to_comment = true
								end
								if to_comment then
									if bere_line.effect:find("^beretag@") then
										bere_line.effect = ':'..bere_line.effect
									end
									bere_line.comment = true
									sub[bere] = bere_line
								end
							end
						end
					end

					--合并
					local mix_table = {}
					for i = 1,math.max(#first_table,#second_table) do
						local new = user_var.classmixProc(first_table[i],second_table[i])
						new.effect = "beretag!"..new.effect:sub(9)
						table.insert(mix_table, new)
					end

					--插入
					if mode.append then
						for i,v in ipairs(mix_table) do
							sub[0]=v
						end
					else
						for i,v in ipairs(mix_table) do
							sub.insert(user_var.temp_line+i,v)
						end
					end

					--删除多余行
					local i=begin
					while i<=#sub do
						local new=sub[i]
						if new.comment and new.effect:find("^beretag!") then
							sub.delete(i)
						else
							i=i+1
						end
					end
				elseif mode.onlyfind then
					if mode.strictstyle then
						if mode.strictactor then
							while bere <= #sub - append_num do
								if sub[user_var.temp_line].style == sub[bere].style and sub[user_var.temp_line].actor == sub[bere].actor
								   and not sub[bere].comment and sub[bere].effect:find("^beretag")
								   and cmp_class(sub[user_var.temp_line].effect,sub[bere].effect)
								then
									user_var.bere_line = bere
									var_expansion(sub[user_var.temp_line].text, 2, sub)
								end
								bere = bere + 1
							end
						else
							while bere <= #sub - append_num do
								if sub[user_var.temp_line].style == sub[bere].style
								   and not sub[bere].comment and sub[bere].effect:find("^beretag")
								   and cmp_class(sub[user_var.temp_line].effect,sub[bere].effect)
								then
									user_var.bere_line = bere
									var_expansion(sub[user_var.temp_line].text, 2, sub)
								end
								bere = bere + 1
							end
						end
					elseif mode.strictactor then
						while bere <= #sub - append_num do
							if sub[user_var.temp_line].actor == sub[bere].actor
							   and not sub[bere].comment and sub[bere].effect:find("^beretag")
							   and cmp_class(sub[user_var.temp_line].effect,sub[bere].effect)
							then
								user_var.bere_line = bere
								var_expansion(sub[user_var.temp_line].text, 2, sub)
							end
							bere = bere + 1
						end
					else
						while bere <= #sub - append_num do
							if not sub[bere].comment and sub[bere].effect:find("^beretag")
							   and cmp_class(sub[user_var.temp_line].effect,sub[bere].effect)
							then
								user_var.bere_line = bere
								var_expansion(sub[user_var.temp_line].text, 2, sub)
							end
							bere = bere + 1
						end
					end
				else
					--先 (keyframe) 后 替换
					if mode.keyframe then
						local key_text_table = {}
						if user_var.keytext~="" and user_var.keytext then
							for line in user_var.keytext:gsub([[\N]],'\n'):gmatch("[^\n]+") do table.insert(key_text_table,line) end
						end
						local find_end = #sub
						while bere<=find_end do--找到bere行
							if not sub[bere].comment and sub[bere].effect:find("^beretag") and cmp_class(sub[user_var.temp_line].effect,sub[bere].effect) 
								and (not mode.strictactor or sub[user_var.temp_line].actor==sub[bere].actor) and (not mode.strictstyle or sub[user_var.temp_line].style==sub[bere].style) then
	
								if (user_var.keytext=="" or not user_var.keytext) and user_var.keyclip~="" and user_var.keyclip then--只有clip的情况
									--处理keyclip内容
									local key_clip_point_table = {}
									local key_clip_table = {}
									for line in user_var.keyclip:gsub([[\N]],'\n'):gmatch("[^\n]+") do table.insert(key_clip_table,line) end
	
									if key_clip_table[1]=="shake_shape_data 4.0" then
										local height = select(1,karaskel.collect_head(user_var.sub)).res_y
										for _,line in ipairs(key_clip_table) do
											if line:sub(1,11)=="vertex_data" then
												line=line:sub(13)
	
												--坐标转换
												local coords = {}
												for x, y in string.gmatch(line, "([^ ]-) ([^ ]-) ") do
													table.insert(coords, {tonumber(x), tonumber(y)})
												end
												for i, coord in ipairs(coords) do
													coord[2] = height - coord[2]
												end
												line=""
												for _, coord in ipairs(coords) do
													line = line..string.format("%.2f %.2f ", coord[1], coord[2])
												end
	
												local _,pos2=line:find("^[^ ]- [^ ]- ")
												table.insert(key_clip_point_table,
													[[{\clip(m ]]..line:sub(0,pos2).."l"..line:sub(pos2)..")}")
											end
										end
									else
										user_var.debug([["]]..key_clip_table[1]..[[" is not supported]])
									end
	
									local time_start, step_num, time_end = key_line.start_time, 1
									if time_start<=0 then time_start = -400/fps end
									time_end = time_start
									if mode.append then
										for i=1,#key_clip_point_table do
											insert_key_line = key_line
											insert_key_line.text = key_clip_point_table[i] .. insert_key_line.text
	
											insert_key_line.start_time = time_end
											time_end = time_start + step_num*1000/fps
											insert_key_line.end_time = time_end
											step_num = step_num+1
	
											sub[0] = insert_key_line
										end
									else
										local insert_pos = bere+1
										for i=1,#key_clip_point_table do
											insert_key_line = key_line
											insert_key_line.text = key_clip_point_table[i] .. insert_key_line.text
	
											insert_key_line.start_time = time_end
											time_end = time_start + step_num*1000/fps
											insert_key_line.end_time = time_end
											step_num = step_num+1
	
											sub.insert(insert_pos,insert_key_line)
											insert_pos = insert_pos+1
										end
										find_end = find_end + insert_pos - bere - 1
										bere = insert_pos - 1
									end
									
								else
									if sub[bere].text:find([[\pos%([^,]-,[^,]-%)]]) then
										if key_text_table[1]=="Adobe After Effects 6.0 Keyframe Data" then
											--补全tag
											local key_line = sub[bere]
											if not sub[bere].text:find([[\fscx%d]]) then
												local pos = key_line.text:find("}")
												key_line.text = key_line.text:sub(1,pos-1)..[[\fscx100]]..key_line.text:sub(pos)
											end
											if not sub[bere].text:find([[\fscy%d]]) then
												local pos = key_line.text:find("}")
												key_line.text = key_line.text:sub(1,pos-1)..[[\fscy100]]..key_line.text:sub(pos)
											end
											if not sub[bere].text:find([[\frz%-?%d]]) then
												local pos = key_line.text:find("}")
												key_line.text = key_line.text:sub(1,pos-1)..[[\frz0]]..key_line.text:sub(pos)
											end
											if not sub[bere].text:find([[\org%([^,]+,[^,]+%)]]) then
												local pos = key_line.text:find("}")
												key_line.text = key_line.text:sub(1,pos-1)..[[\org]]..key_line.text:match([[\pos(%([^%)]-%))]])..key_line.text:sub(pos)
											end
											key_line.effect = "beretag!"..key_line.effect:sub(9)
											--处理bere行
											if sub[bere].effect:find("^beretag@") then
												local line = sub[bere]
												line.effect = ":"..line.effect
												line.comment = true
												sub[bere] = line
											else
												local line = sub[bere]
												line.comment = true
												sub[bere] = line
											end
											--处理keytext内容
											local fps = user_var.forcefps or key_text_table[2]:match("%d+%.?%d*")
											local time_start, step_num, time_end = key_line.start_time, 1
											if time_start<=0 then time_start = -400/fps end
											local key_text_table_pos = 2
											while key_text_table[key_text_table_pos]~=[[	Frame	X pixels	Y pixels	Z pixels]] do
												key_text_table_pos=key_text_table_pos+1
											end
											key_text_table_pos=key_text_table_pos+1
	
											local key_pos, key_scale, key_rot = {},{},{}
											while key_text_table[key_text_table_pos]~="Scale" do--read Position
												table.insert(key_pos,{key_text_table[key_text_table_pos]:match("^\t[^\t]*\t([^\t]*)\t([^\t]*)")})
												key_text_table_pos=key_text_table_pos+1
											end
											key_text_table_pos=key_text_table_pos+2
											while key_text_table[key_text_table_pos]~="Rotation" do--read Scale
												table.insert(key_scale,{key_text_table[key_text_table_pos]:match("^\t[^\t]*\t([^\t]*)\t([^\t]*)")})
												key_text_table_pos=key_text_table_pos+1
											end
											key_text_table_pos=key_text_table_pos+2
											while key_text_table[key_text_table_pos]~="End of Keyframe Data" do--read Rotation
												table.insert(key_rot,{key_text_table[key_text_table_pos]:match("^\t[^\t]*\t([^\t]*)")})
												key_text_table_pos=key_text_table_pos+1
											end
											--处理keyclip内容
											local key_clip_point_table = {}
											if user_var.keyclip~="" and user_var.keyclip then
												local key_clip_table = {}
												for line in user_var.keyclip:gsub([[\N]],'\n'):gmatch("[^\n]+") do table.insert(key_clip_table,line) end
	
												if key_clip_table[1]=="shake_shape_data 4.0" then
													local height = select(1,karaskel.collect_head(user_var.sub)).res_y
													for _,line in ipairs(key_clip_table) do
														if line:sub(1,11)=="vertex_data" then
															line=line:sub(13)
	
															--坐标转换
															local coords = {}
															for x, y in string.gmatch(line, "([^ ]-) ([^ ]-) ") do
																table.insert(coords, {tonumber(x), tonumber(y)})
															end
															for i, coord in ipairs(coords) do
																coord[2] = height - coord[2]
															end
															line=""
															for _, coord in ipairs(coords) do
																line = line..string.format("%.2f %.2f ", coord[1], coord[2])
															end
	
															local _,pos2=line:find("^[^ ]- [^ ]- ")
															table.insert(key_clip_point_table,
																[[{\clip(m ]]..line:sub(0,pos2).."l"..line:sub(pos2)..")}")
														end
													end
												else
													user_var.debug([["]]..key_clip_table[1]..[[" is not supported]])
												end
											end
											for i=#key_clip_point_table+1,#key_rot do
												key_clip_point_table[i]=""
											end
											--开始插入行
											local x,y,fx,fy,fz,ox,oy
											local pos_table, out_value = {1,#key_line.text}, {}
											
											local pos1,pos2 = key_line.text:find([[\pos%([^,]-,]])
											x = key_line.text:sub(pos1+5,pos2-1)
											table.insert(out_value,{pos1,x,key_pos,1})
											table.insert(pos_table,pos1+4) table.insert(pos_table,pos2)
			
											pos1,pos2 = key_line.text:find([[,[^,]-%)]],pos2)
											y = key_line.text:sub(pos1+1,pos2-1)
											table.insert(out_value,{pos1,y,key_pos,2})
											table.insert(pos_table,pos1) table.insert(pos_table,pos2)
			
											pos1,pos2 = key_line.text:find([[\fscx[%d%.]+]])
											fx = key_line.text:sub(pos1+5,pos2)
											table.insert(out_value,{pos1,fx,key_scale,1})
											table.insert(pos_table,pos1+4) table.insert(pos_table,pos2+1)
			
											pos1,pos2 = key_line.text:find([[\fscy[%d%.]+]])
											fy = key_line.text:sub(pos1+5,pos2)
											table.insert(out_value,{pos1,fy,key_scale,2})
											table.insert(pos_table,pos1+4) table.insert(pos_table,pos2+1)
			
											pos1,pos2 = key_line.text:find([[\frz%-?[%d%.]+]])
											fz = key_line.text:sub(pos1+4,pos2)
											table.insert(out_value,{pos1,fz,key_rot,1})
											table.insert(pos_table,pos1+3) table.insert(pos_table,pos2+1)
											
											pos1,pos2 = key_line.text:find([[\org%([^,]-,]])
											ox = key_line.text:sub(pos1+5,pos2-1)
											table.insert(out_value,{pos1,ox,key_pos,1})
											table.insert(pos_table,pos1+4) table.insert(pos_table,pos2)
			
											pos1,pos2 = key_line.text:find([[,[^,]-%)]],pos2)
											oy = key_line.text:sub(pos1+1,pos2-1)
											table.insert(out_value,{pos1,oy,key_pos,2})
											table.insert(pos_table,pos1) table.insert(pos_table,pos2)
											
	
											table.sort(out_value, function(a,b) return a[1] < b[1] end) table.sort(pos_table)
			
											local insert_key_line_table, insert_key_line = {
												key_line.text:sub(pos_table[1],pos_table[2]),
												key_line.text:sub(pos_table[3],pos_table[4]),
												key_line.text:sub(pos_table[5],pos_table[6]),
												key_line.text:sub(pos_table[7],pos_table[8]),
												key_line.text:sub(pos_table[9],pos_table[10]),
												key_line.text:sub(pos_table[11],pos_table[12]),
												key_line.text:sub(pos_table[13],pos_table[14]),
												key_line.text:sub(pos_table[15],pos_table[16])
											}
											abcasd = 1
											--根据mode插入
											local function key_line_value(num,i)
												-- out_value[num][3][i][out_value[num][4]] 文件中当前行值
												-- out_value[num][3][1][out_value[num][4]] 文件中第一行值
												-- out_value[num][2] 字幕中当前行值
												if insert_key_line_table[num]:sub(-1)=='x' or insert_key_line_table[num]:sub(-1)=='y' then
													return
														insert_key_line_table[num] ..
														math.floor((out_value[num][3][i][out_value[num][4]]/out_value[num][3][1][out_value[num][4]]*out_value[num][2])*100+0.5)/100
												else
													return
														insert_key_line_table[num] ..
														math.floor((out_value[num][3][i][out_value[num][4]]-out_value[num][3][1][out_value[num][4]]+out_value[num][2])*100+0.5)/100
												end
											end
											time_end = time_start
											if mode.append then
												for i=1,#key_rot do
													insert_key_line = key_line
													insert_key_line.text =
														key_clip_point_table[i] ..
														key_line_value(1,i) ..
														key_line_value(2,i) ..
														key_line_value(3,i) ..
														key_line_value(4,i) ..
														key_line_value(5,i) ..
														key_line_value(6,i) ..
														key_line_value(7,i) ..
														insert_key_line_table[8]
			
													insert_key_line.start_time = time_end
													time_end = time_start + step_num*1000/fps
													insert_key_line.end_time = time_end
													step_num = step_num+1
			
													sub[0] = insert_key_line
												end
											else
												local insert_pos = bere+1
												for i=1,#key_rot do
													insert_key_line = key_line
													insert_key_line.text =
														key_clip_point_table[i] ..
														key_line_value(1,i) ..
														key_line_value(2,i) ..
														key_line_value(3,i) ..
														key_line_value(4,i) ..
														key_line_value(5,i) ..
														key_line_value(6,i) ..
														key_line_value(7,i) ..
														insert_key_line_table[8]
			
													insert_key_line.start_time = time_end
													time_end = time_start + step_num*1000/fps
													insert_key_line.end_time = time_end
													step_num = step_num+1
			
													sub.insert(insert_pos,insert_key_line)
													insert_pos = insert_pos+1
												end
												find_end = find_end + insert_pos - bere - 1
												bere = insert_pos - 1
											end
										else
											user_var.debug([["]]..key_text_table[1]..[[" is not supported]])
										end
									else
										user_var.debug(tr[["\pos" not found]])
									end
								end
							end
							--next
							bere = bere+1
						end
						--end
						bere = begin
						while bere <= #sub do
							if sub[bere].effect:find("^beretag!") and sub[bere].comment then
								sub.delete(bere)
							end
							bere = bere+1
						end
						bere = begin
	
						user_var.keytext, user_var.keyclip = "", ""
					end
					--先 keyframe 后 (替换)
					if mode.strictstyle then
						if mode.strictactor then
							while bere <= #sub - append_num do
								if sub[user_var.temp_line].style == sub[bere].style and sub[user_var.temp_line].actor == sub[bere].actor then
									user_var.bere_line = bere
									bere = bere + do_replace(sub, bere, mode, begin)
								else
									bere = bere + 1
								end
							end
						else
							while bere <= #sub - append_num do
								if sub[user_var.temp_line].style == sub[bere].style then
									user_var.bere_line = bere
									bere = bere + do_replace(sub, bere, mode, begin)
								else
									bere = bere + 1
								end
							end
						end
					elseif mode.strictactor then
						while bere <= #sub - append_num do
							if sub[user_var.temp_line].actor == sub[bere].actor then
								user_var.bere_line = bere
								bere = bere + do_replace(sub, bere, mode, begin)
							else
								bere = bere + 1
							end
						end
					else
						while bere <= #sub - append_num do
							user_var.bere_line = bere
							bere = bere + do_replace(sub, bere, mode, begin)
						end
					end
				end
				if mode.recache and #user_var.subcache > 0 then--插入缓存行
					for i=1,#user_var.subcache do
						user_var.subcache[i].effect = "beretag!"..user_var.subcache[i].effect:sub(9)
					end
					if mode.append then
						for i,v in ipairs(user_var.subcache) do
							sub[0]=v
						end
					else
						for i,v in ipairs(user_var.subcache) do
							sub.insert(user_var.temp_line+i,v)
						end
					end
					user_var.subcache={}
				end
			end
		--检索命令行
			if sub[user_var.temp_line].effect:find("^template#") then
				var_expansion(sub[user_var.temp_line].text, 2, sub)
				if #user_var.subcache > 0 then--插入缓存行
					mode = get_mode(sub[user_var.temp_line].effect)
					if mode.recache then
						for i=1,#user_var.subcache do
							user_var.subcache[i].effect = "beretag!"..user_var.subcache[i].effect:sub(9)
						end
						if mode.append then
							for i,v in ipairs(user_var.subcache) do
								sub[0]=v
							end
						else
							for i,v in ipairs(user_var.subcache) do
								sub.insert(user_var.temp_line+i,v)
							end
						end
						user_var.subcache={}
					end
				end
			end
			append_num=0--还原append边界
		end
		user_var.temp_line=user_var.temp_line+1
	end

	--删除所有空的 beretag! 行
	local i=begin
	while i <= #sub do
		if sub[i].effect:find("^beretag!") and not sub[i].comment and sub[i].text=="" then
			sub.delete(i)
		else
			i = i+1
		end
	end
end

local function macro_processing_function(subtitles)--Execute Macro. 执行宏
	do_macro(subtitles)
end

local function comment_template_line(sub,selected_table)
	for i=find_event(sub),#sub do
		if selected_table[tostring(i)]~=true and sub[i].effect:find("^template[@#]") and sub[i].comment then
			local line = sub[i]
			line.effect = ":"..line.effect
			sub[i] = line
		end
	end
end

local function uncomment_template_line(sub)
	for i=find_event(sub),#sub do
		if sub[i].effect:find("^:template") then
			local line = sub[i]
			line.effect = line.effect:sub(2)
			sub[i] = line
		end
	end
end

local function macro_processing_function_selected(subtitles,selected_lines)--Execute Macro in selected lines. 在所选行执行宏
	--搜索所有非所选的template行，对其中注释行头部添加:，执行完后再还原
	local selected_table={}
	for i,v in ipairs(selected_lines) do
		selected_table[tostring(v)]=true
	end
	comment_template_line(subtitles,selected_table)
	do_macro(subtitles)
	uncomment_template_line(subtitles)
end

local function macro_processing_function_initialize(subtitles)--初始化
	initialize(subtitles,find_event(subtitles))
end

aegisub.register_macro(tr"Tag Replace Apply", tr"Replace all strings with your settings", macro_processing_function)
aegisub.register_macro(tr"Tag Replace Apply in selected lines", tr"Replace selected lines' strings with your settings", macro_processing_function_selected)
aegisub.register_macro(tr"Tag Replace Initialize", tr"Only do the initialize function", macro_processing_function_initialize)

local function filter_processing_function(subtitles, old_settings)
	do_macro(subtitles)
	for i = find_event(subtitles), #subtitles do
		if subtitles[i].effect:find("^beretag!") and not subtitles[i].comment then
			local line = subtitles[i]
			line.effect = "beretag!"
			subtitles[i] = line
		end
	end
end

aegisub.register_filter(tr"Tag Replace", tr"Replace and clear sth", 2500, filter_processing_function)