require"karaskel"
local util = require"aegisub.util"
local ffi = require"ffi"
local bit = require"bit"
local re = require"aegisub.re"

local tr = aegisub.gettext

script_name = tr"Tag Replace"
script_description = tr"Replace string such as tag"
script_author = "op200"
script_version = "2.7.4"
-- https://github.com/op200/Tag-Replace_for_Aegisub

local function get_class() end

local base64_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local base64_reverse = {}
for i = 1, #base64_chars do
	base64_reverse[base64_chars:sub(i, i)] = i - 1
end

local user_var--自定义变量键值表
user_var={
	sub,
	progress={0,0},
	subcache={},
	msg={},
	kdur={0,0},--存储方式为前缀和，从[2]开始计数，方便相对值计算
	begin=false,
	temp_line=false,
	bere_line=false,
	bere_text="",
	bere_match={},
	bere_num=0,
	exp_num=0,
	forcefps=false,
	keytext="",
	keyclip="",
	cuttime={
		frame_model=true,
		accel=1,
		interpolate=function(current_time, total_time, start_value, end_value, tag)
			local factor = (end_value - start_value) / ((total_time ^ user_var.cuttime.accel) - 1)
			return start_value + factor * ((current_time ^ user_var.cuttime.accel) - 1)
		end
	},
	use_xpcall=false,

	--功能性

	deepCopy=function(add)
		if add == nil then return nil end

		local visited = {}

		local function _deepCopy(obj)
			if visited[obj] then
				return visited[obj]
			end

			if type(obj) == "table" then
				local copy = {}
				visited[obj] = copy

				local mt = getmetatable(obj)
				if mt then
					setmetatable(copy, mt)
				end

				for k, v in next, obj do
					copy[_deepCopy(k)] = _deepCopy(v)
				end

				return copy
			else
				return obj
			end
		end

		return _deepCopy(add)
	end,
	checkVer=function(ver, is_must_equal)
		if ver:find("[a-zA-z]") or script_version:find("%a") then
			user_var.debug("$checkVer: Can not check informal version", true)
		end

		local pass = nil

		if is_must_equal then
			if ver == script_version then
				pass = true
			end
		else
			local script_ver, input_ver = {}, {}
			for v in (script_version:match("(.-)%-") or script_version):gmatch("%d+") do
				table.insert(script_ver, tonumber(v))
			end
			for v in (ver:match("(.-)%-") or ver):gmatch("%d+") do
				table.insert(input_ver, tonumber(v))
			end

			local max_len = math.max(#script_ver, #input_ver)
			pass = true
			for i = 1, max_len do
				local script_num = script_ver[i] or 0
				local input_num = input_ver[i] or 0
				if script_num > input_num then
					break
				elseif script_num < input_num then
					pass = false
					break
				end
			end
		end

		if not pass then
			user_var.debug("$checkVer: Tag Replace version mismatch", true)
		end
	end,
	debug=function(text, to_exit)
		local button = aegisub.dialog.display({{class="label",label=user_var.sanitize_utf8(tostring(text)):gsub("&", "&&")}})
		if not button or to_exit then aegisub.cancel() end
	end,
	addClass=function(line, ...)
		if not line.effect:find("^beretag@.") then user_var.debug(tr"Must beretag") return end
		local class = get_class(line.effect, false)
		local new_class = {select(1, ...)}
		for _,v in pairs(new_class) do
			table.insert(class, v)
		end
		local class_dict = {}
		for _,v in pairs(class) do
			class_dict[v] = true
		end
		class = {}
		for k in pairs(class_dict) do
			table.insert(class, k)
		end
		line.effect = "beretag@" .. table.concat(class, ";")
	end,
	delClass=function(line, ...)
		if not line.effect:find("^beretag@.") then user_var.debug(tr"Must beretag") return end
		local class = get_class(line.effect, false)
		local del_class = {select(1, ...)}
		local class_dict = {}
		for _,v in pairs(class) do
			class_dict[v] = true
		end
		for _,v in pairs(del_class) do
			class_dict[v] = nil
		end
		class = {}
		for k in pairs(class_dict) do
			table.insert(class, k)
		end
		line.effect = "beretag@" .. table.concat(class, ";")
	end,
	newClass=function(line, ...)
		if not line.effect:find("^beretag@.") then user_var.debug(tr"Must beretag") return end
		local new_class = {select(1, ...)}
		line.effect = "beretag@" .. table.concat(new_class, ";")
	end,
	addLine=function(...)
		for _,line in ipairs({select(1, ...)}) do
			table.insert(user_var.subcache, user_var.deepCopy(line))
		end
	end,
	addMsg=function(...)
		for _,msg in ipairs({select(1, ...)}) do
			table.insert(user_var.msg, user_var.deepCopy(msg))
		end
	end,
	ms2f=function(ms)
		return aegisub.frame_from_ms(ms)
	end,
	f2ms=function(f)
		return aegisub.ms_from_frame(f)
	end,
	enbase64=function(str)
		local b64 = {}
		local bit = 0
		local buffer = 0
		local length = #str
		local index = 1

		while index <= length do
			buffer = buffer * 256
			if index <= length then
					buffer = buffer + string.byte(str, index)
					index = index + 1
			end
			bit = bit + 8
			while bit >= 6 do
					bit = bit - 6
					local char_index = math.floor(buffer / (2 ^ bit)) % 64 + 1
					table.insert(b64, base64_chars:sub(char_index, char_index))
					buffer = buffer % (2 ^ bit)
			end
		end

		if bit > 0 then
			buffer = buffer * (2 ^ (6 - bit))
			table.insert(b64, base64_chars:sub(buffer + 1, buffer + 1))
		end

		while #b64 % 4 ~= 0 do
			table.insert(b64, "=")
		end

		return table.concat(b64)
	end,
	debase64=function(str)
		local result = {}
		local buffer = 0
		local bit = 0
		local length = #str

		for i = 1, length do
			local char = str:sub(i, i)
			if char ~= "=" then
					buffer = buffer * 64 + base64_reverse[char]
					bit = bit + 6
					if bit >= 8 then
						bit = bit - 8
						table.insert(result, string.char(math.floor(buffer / (2 ^ bit))))
						buffer = buffer % (2 ^ bit)
					end
			end
		end

		return table.concat(result)
	end,
	sanitize_utf8=function(input)
		local output = {}
		local i = 1
		local len = #input
		
		while i <= len do
			local byte = input:byte(i)
			
			-- ASCII 字符 (0-127)
			if byte < 0x80 then
					table.insert(output, string.char(byte))
					i = i + 1
			
			-- 2字节 UTF-8 字符
			elseif byte >= 0xC2 and byte <= 0xDF then
					if i + 1 <= len then
						local byte2 = input:byte(i + 1)
						if byte2 >= 0x80 and byte2 <= 0xBF then
							table.insert(output, string.sub(input, i, i + 1))
							i = i + 2
						else
							table.insert(output, "?")
							i = i + 1
						end
					else
						table.insert(output, "?")
						i = i + 1
					end
			
			-- 3字节 UTF-8 字符
			elseif byte >= 0xE0 and byte <= 0xEF then
					if i + 2 <= len then
						local byte2 = input:byte(i + 1)
						local byte3 = input:byte(i + 2)
						if (byte2 >= 0x80 and byte2 <= 0xBF) and 
							(byte3 >= 0x80 and byte3 <= 0xBF) then
							-- 检查过长的编码 (overlong)
							if byte == 0xE0 and byte2 < 0xA0 then
									table.insert(output, "?")
									i = i + 1
							elseif byte == 0xED and byte2 > 0x9F then
									table.insert(output, "?")
									i = i + 1
							else
									table.insert(output, string.sub(input, i, i + 2))
									i = i + 3
							end
						else
							table.insert(output, "?")
							i = i + 1
						end
					else
						table.insert(output, "?")
						i = i + 1
					end
			
			-- 4字节 UTF-8 字符
			elseif byte >= 0xF0 and byte <= 0xF4 then
					if i + 3 <= len then
						local byte2 = input:byte(i + 1)
						local byte3 = input:byte(i + 2)
						local byte4 = input:byte(i + 3)
						if (byte2 >= 0x80 and byte2 <= 0xBF) and 
							(byte3 >= 0x80 and byte3 <= 0xBF) and 
							(byte4 >= 0x80 and byte4 <= 0xBF) then
							-- 检查过长的编码 (overlong) 和超出范围的编码
							if byte == 0xF0 and byte2 < 0x90 then
									table.insert(output, "?")
									i = i + 1
							elseif byte == 0xF4 and byte2 > 0x8F then
									table.insert(output, "?")
									i = i + 1
							else
									table.insert(output, string.sub(input, i, i + 3))
									i = i + 4
							end
						else
							table.insert(output, "?")
							i = i + 1
						end
					else
						table.insert(output, "?")
						i = i + 1
					end
			
			-- 无效的 UTF-8 起始字节
			else
					table.insert(output, "?")
					i = i + 1
			end
		end
		
		return table.concat(output)
	end,

	--后处理

	postProc=function(line)
	end,
	keyProc=function(line, progress)
	end,
	classmixProc=function(first, second, new_class)
		if not (first and second) then return first or second end
		local new = first
		new.text = new.text..second.text
		local effect_table = {new.effect:match("([^@]*@)(.*)")}
		if new_class then
			new.effect = effect_table[1]..new_class
		else
			new.effect = effect_table[1]..second.effect:match("@([^#]*)")..effect_table[2]
		end
		return new
	end,

	--行处理

	--- @param line table
	--- @param tags string | nil
	--- @return nil
	rePreLine=function(line, tags)
		local meta, styles = karaskel.collect_head(user_var.sub)
		local style = styles[line.style]

		tags = tags or line.text:gsub("}{", ""):match("^{(.-)}") or ""

		for fn in tags:gmatch("\\fn([^}\\]+)") do -- \fn
			style.fontname = fn
		end

		for n, a in tags:gmatch("\\a(n?)(%d+)") do -- \an?
			if n == 'n' then
				style.align = tonumber(a)
			else
				style.align = ({1,2,3, 7,7,8,9, 7,4,5,6})[tonumber(a)]
			end
		end

		for fs in tags:gmatch("\\fs(%d+%.?%d+)") do -- \fs
			style.fontsize = tonumber(fs)
		end

		for c, fs in tags:gmatch("\\fs([%+%-])(%d+%.?%d+)") do -- \fs[+-]
			if c == '+' then
				style.fontsize = (1 + fs / 10) * style.fontsize
			else
				style.fontsize = (1 - fs / 10) * style.fontsize
			end
		end

		for fsp in tags:gmatch("\\fsp(%-?%d+%.?%d+)") do -- \fsp
			style.spacing = tonumber(fsp)
		end

		for p, fsc in tags:gmatch("\\fsc([xy])(%d+%.?%d+)") do -- \fsc[xy]
			if p == 'x' then
				style.scale_x = tonumber(fsc)
			else
				style.scale_y = tonumber(fsc)
			end
		end

		karaskel.preproc_line_text(meta, styles, line)
		karaskel.preproc_line_size(meta, styles, line)
		karaskel.preproc_line_pos(meta, styles, line)

		-- 重新计算宽高
		local line_break_num = 0
		for _ in line.text:gmatch([[\N]]) do
			line_break_num = line_break_num + 1
		end
		if line.text:find([[\N$]]) then
			line_break_num = line_break_num - 1
		end

		if line_break_num == 0 then
			return
		end

		local new_height, new_width = 0, 0

		for t in (line.text..[[\N]]):gmatch([[(.-)\N]]) do
			local new_line = user_var.deepCopy(line)
			new_line.text = t

			if t == "" then
				new_line.text = " "
				user_var.rePreLine(new_line)
				new_height = new_height + new_line.height / 2
			else
				user_var.rePreLine(new_line)
				new_height = new_height + new_line.height
			end

			if new_line.width > new_width then
				new_width = new_line.width
			end
		end

		line.height, line.width = new_height, new_width

		if line.halign == "center" then
			local half_w = new_width / 2
			line.left, line.right = line.x - half_w, line.x + half_w
		elseif line.halign == "left" then
			line.right = line.left + new_width
		else
			line.left = line.right - new_width
		end

		if line.valign == "bottom" then
			line.top = line.bottom - new_height
		elseif line.valign == "top" then
			line.bottom = line.top + new_height
		else
			local half_h = new_height / 2
			line.top, line.bottom = line.y - half_h, line.y + half_h
		end
	end,
	--- @param line table  
	--- @param callback function(line, position: dict, progress: list) -> nil  
	--- 　@param position: {x, y, l, r, t, b, w, h, x_r = x - l, y_r}  
	--- 　@param progress: {x_fraction: list, y_fraction, x_percent: number, y_percent}  
	--- @param step table<number | nil> | nil  
	--- 　{x_step: number | nil, y_step: number | nil, expand: list | nil}  
	--- 　　expand: list{number | nil} = {left, top, right, bottom}  
	--- @param pos table<number | nil> | nil  
	--- 　{x: number | nil, y: number | nil}  
	--- @return nil -- insert subcache
	gradient=function(line, callback, step, pos)
		line = user_var.deepCopy(line)

		local meta, styles = karaskel.collect_head(user_var.sub)
		local style = styles[line.style]

		-- 根据头部 {} 中的 \pos \fn \an? \fs[+-]? \fsp \fsc[xy] \[xy]?bord \[xy]?shad 标签重计算位置, pos 不是 style 中的, 放最后单独计算
		local tags = line.text:gsub("}{", ""):match("^{(.-)}") or ""

		user_var.rePreLine(line, tags)

		-- \[xy]?bord
		local bord = {style.outline, style.outline}
		for p, b in tags:gmatch("\\([xy]?)bord(%d+%.?%d+)") do
			if p == 'x' then
				bord[1] = tonumber(b)
			elseif p == 'y' then
				bord[2] = tonumber(b)
			else
				b = tonumber(b)
				bord = {b, b}
			end
		end

		-- \[xy]?shad
		local shad = {style.shadow, style.shadow}
		for p, s in tags:gmatch("\\([xy]?)shad(%d+%.?%d+)") do
			if p == 'x' then
				shad[1] = tonumber(s)
			elseif p == 'y' then
				shad[2] = tonumber(s)
			else
				s = tonumber(s)
				shad = {s, s}
			end
		end

		local l, r, t, b = line.left, line.right - line.styleref.spacing * 2, line.top, line.bottom
		l, r, t, b = l - bord[1], r + bord[1], t - bord[2], b + bord[2]
		if shad[1] > 0 then
			r = r + shad[1]
		else
			l = l + shad[1]
		end
		if shad[2] > 0 then
			b = b + shad[2]
		else
			t = t + shad[2]
		end

		step = step or {}
		local expand = step[3] or {0, 0, 0, 0}

		local pos_tag = {line.text:match("\\pos%(([^,]-),([^%)]-)%)")}
		pos = pos or {}
		pos = {pos[1] or pos_tag[1] or line.x, pos[2] or pos_tag[2] or line.y}
		if not pos[1] or not pos[2] then user_var.debug(tr"Need position", true) end

		local offset_x, offset_y = pos[1] - line.x, pos[2] - line.y
		l, r, t, b =
			l + offset_x - (expand[1] or 0),
			r + offset_x + (expand[3] or 0),
			t + offset_y - (expand[2] or 0),
			b + offset_y + (expand[4] or 0)

		local step1, step2 = step[1] or r-l+1, step[2] or b-t+1

		for x = l, r, step1 do
			for y = t, b, step2 do
				local new_line = user_var.deepCopy(line)
				new_line.text = string.format([[{\pos(%.2f,%.2f)\clip(%.2f,%.2f,%.2f,%.2f)}%s]],
					pos[1], pos[2],
					x, y, x+step1, y+step2,
					new_line.text:gsub([[\pos%([^%)]-%)]], ""))
				local w, h = r - l, b - t
				local x_relative, y_relative = x - l, y - t
				callback(new_line,
					{
						x = x, y = y, l = l, r = r, t = t, b = b,
						w = w, h = h, x_r = x_relative, y_r = y_relative },
					{
						{ x_relative, w },
						{ y_relative, h },
						100 * x_relative / w,
						100 * y_relative / h })
				table.insert(user_var.subcache, new_line)
			end
		end
	end,
	--- @param line table  
	--- @param colors table<string>
	--- @param tags table<string>
	--- @param step table<number | nil> | nil  
	--- 　{x_step: number | nil, y_step: number | nil, expand: list | nil}  
	--- 　　expand: list{number | nil} = {left, top, right, bottom}  
	--- @param pos table<number | nil> | nil  
	--- 　{x: number | nil, y: number | nil}  
	--- @return nil -- insert subcache
	gradientColor=function(line, colors, tags, step, pos)
		if #colors ~= 4 then
			user_var.debug(string.format(tr"Parameter '%s' length not %d", "colors", 4), true)
		end

		local r1, g1, b1, a1 = util.extract_color(colors[1])
		local r2, g2, b2, a2 = util.extract_color(colors[2])
		local r3, g3, b3, a3 = util.extract_color(colors[3])
		local r4, g4, b4, a4 = util.extract_color(colors[4])
		if not (r1 and g1 and b1 and a1) then
			user_var.debug(string.format(tr"The format of string '%s' is invalid", "colors[1]"), true)
		end
		if not (r2 and g2 and b2 and a2) then
			user_var.debug(string.format(tr"The format of string '%s' is invalid", "colors[2]"), true)
		end
		if not (r3 and g3 and b3 and a3) then
			user_var.debug(string.format(tr"The format of string '%s' is invalid", "colors[3]"), true)
		end
		if not (r4 and g4 and b4 and a4) then
			user_var.debug(string.format(tr"The format of string '%s' is invalid", "colors[4]"), true)
		end

		local c_format_str = ""
		local a_format_str = ""
		for _, tag in pairs(tags) do
			if tag:find("a") then
				a_format_str = a_format_str .. "\\" .. tag .. "%s"
			else
				c_format_str = c_format_str .. "\\" .. tag .. "%s"
			end
		end

		local function tags_format(c_str, a_str)
			return "{" .. c_format_str:gsub("%%s", c_str) .. a_format_str:gsub("%%s", a_str) .. "}"
		end

		user_var.gradient(line,
		function(line, _, prog)
			local prog1, prog2 = prog[4] / 100, prog[3] / 100

			local r = util.interpolate(
				prog1,
				util.interpolate(prog2, r1, r2),
				util.interpolate(prog2, r3, r4)
			)
			local g = util.interpolate(
				prog1,
				util.interpolate(prog2, g1, g2),
				util.interpolate(prog2, g3, g4)
			)
			local b = util.interpolate(
				prog1,
				util.interpolate(prog2, b1, b2),
				util.interpolate(prog2, b3, b4)
			)
			local a = util.interpolate(
				prog1,
				util.interpolate(prog2, a1, a2),
				util.interpolate(prog2, a3, a4)
			)

			line.text = tags_format(util.ass_color(r, g, b), util.ass_alpha(a)) .. line.text
		end,
		step, pos)
	end,
	colorGradient=function(line_info, rgba, step_set, tags, control_points, pos)
		user_var.addMsg(string.format(tr"This is a deprecated function: %s", "$colorGradient"))
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
		local x1, y1, x2, y2
	
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
		local color_tag = tags[1] or "c"
		local transparent_tag = tags[2] or "1a"

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
	--- @param line table
	--- @param width number | nil
	posLine=function(line, width)
		line = user_var.deepCopy(line)

		user_var.rePreLine(line)
		width = width or 1

		local xres, yres = aegisub.video_size()
		xres, yres = (xres or 1920) * 10, (yres or 1080) * 10
		local pos_tag = {line.text:match("\\pos%(([^,]-),([^%)]-)%)")}
		local x, y = pos_tag[1] or line.x, pos_tag[2] or line.y
		local offset_x, offset_y = x - line.x, y - line.y
		local l, r, t, b = line.left, line.right - line.styleref.spacing * 2, line.top, line.bottom
		l, r, t, b = l + offset_x, r + offset_x, t + offset_y, b + offset_y

		local line_line = user_var.deepCopy(line)

		-- top bottom
		local top_bottom = string.format(
			[[{\an\pos(%s,pos_y)\bord0\shad0\c&H0000FF&\1a&H80&\p1}m 0 0 l 0 %d %d %d %d 0]],
			x,
			width,
			xres, width,
			xres)
		line_line.text = top_bottom:gsub([[\an]], [[\an2]]):gsub("pos_y", t)
		user_var.addLine(line_line)
		line_line.text = top_bottom:gsub([[\an]], [[\an8]]):gsub("pos_y", b)
		user_var.addLine(line_line)

		-- left right
		local left_right = string.format(
			[[{\an\pos(pos_x,%s)\bord0\shad0\c&H00FF00&\1a&H80&\p1}m 0 0 l %d 0 %d %d 0 %d]],
			y,
			width,
			width, yres,
			yres)
		line_line.text = left_right:gsub([[\an]], [[\an6]]):gsub("pos_x", l)
		user_var.addLine(line_line)
		line_line.text = left_right:gsub([[\an]], [[\an4]]):gsub("pos_x", r)
		user_var.addLine(line_line)

		-- descent ext_lead
		local _, _, descent, ext_lead = aegisub.text_extents(line.styleref, "")
		descent, ext_lead = tonumber(descent), tonumber(ext_lead)
		local descent_extlead = string.format(
			[[{\an\pos(%s,pos_y)\bord0\shad0\&HFF0000&\1a&H80&\p1}m 0 0 l 0 %d %d %d %d 0]],
			x,
			width,
			xres, width,
			xres)
		if descent ~= 0 then
			line_line.text = descent_extlead:gsub([[\an]], [[\an2]]):gsub("pos_y", t + descent)
			user_var.addLine(line_line)
			line_line.text = descent_extlead:gsub([[\an]], [[\an8]]):gsub("pos_y", b - descent)
			user_var.addLine(line_line)
		end
		if ext_lead ~= 0 then
			line_line.text = descent_extlead:gsub([[\an]], [[\an2]]):gsub("pos_y", t - ext_lead)
			user_var.addLine(line_line)
			line_line.text = descent_extlead:gsub([[\an]], [[\an8]]):gsub("pos_y", b + ext_lead)
			user_var.addLine(line_line)
		end
	end,

	--外部

	--- @return string | boolean?
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
	psCode=function(cmd, popen)
		cmd = [[powershell -ExecutionPolicy Bypass -Command "]] ..
			string.format(([[
					$base64String = "%s";

					$bytes = [System.Convert]::FromBase64String($base64String);
					$decodedString = [System.Text.Encoding]::UTF8.GetString($bytes);

					Invoke-Expression $decodedString;
				]]):gsub('\r?\n', ''),
				user_var.enbase64(cmd:gsub('\r?\n', ''))
			):gsub('"', '\\"') .. '"'
		return user_var.cmdCode(cmd, popen)
	end,
	pyCode=function(cmd, popen)
		return user_var.cmdCode(string.format(
			[[python -c "%s"]], cmd:gsub([[\N]], ';')), popen)
	end,
	getGlyph=function(char, line)
		local line = user_var.deepCopy(line)
		user_var.rePreLine(line)
		local _, _, descent, ext_lead = aegisub.text_extents(line.styleref, "")

		local ps_script = string.format(
			[[$Character='%s';$FontName="%s";$FontSize=%s;]], char, line.styleref.fontname, line.bottom - line.top - descent
		) .. [==[
				Add-Type -AssemblyName PresentationCore;
				Add-Type -AssemblyName WindowsBase;

				function Get-GlyphData {
					[CmdletBinding()]param (
						[Parameter(Mandatory = $true)]
						[char]$Character,
						[Parameter(Mandatory = $true)]
						[string]$FontName,
						[Parameter(Mandatory = $true)]
						[string]$FontSize
					);

					<# 查找字体 #>
					$fontFamily = [System.Windows.Media.Fonts]::SystemFontFamilies |
					Where-Object { $_.FamilyNames.Values -contains $FontName } |
					Select-Object -First 1;
					if (-not $fontFamily) { throw "Font '$FontName' not found"; }

					<# 获取GlyphTypeface #>
					$typeface = New-Object System.Windows.Media.Typeface(
						$fontFamily,
						[System.Windows.FontStyles]::Normal,
						[System.Windows.FontWeights]::Normal,
						[System.Windows.FontStretches]::Normal
					);
					$glyphTypeface = $null;
					if (-not $typeface.TryGetGlyphTypeface([ref]$glyphTypeface)) {
						throw "Failed to get GlyphTypeface";
					}

					<# 获取字形索引 #>
					$unicode = [int][char]$Character;
					if (-not $glyphTypeface.CharacterToGlyphMap.ContainsKey($unicode)) {
						throw "Character '$Character' not found";
					}
					$glyphIndex = $glyphTypeface.CharacterToGlyphMap[$unicode];

					<# 获取几何数据 #>
					$geometry = $glyphTypeface.GetGlyphOutline($glyphIndex, $FontSize, 1);
					$pathGeometry = [System.Windows.Media.PathGeometry]::CreateFromGeometry($geometry);

					<# 计算行高并进行向上偏移 #>
					$lineHeight = $glyphTypeface.LineSpacing * $FontSize;
					$offsetY = $pathGeometry.Bounds.Height - $lineHeight;

					$assCommands = New-Object System.Collections.Generic.List[string];

					foreach ($figure in $pathGeometry.Figures) {
						$startPoint = $figure.StartPoint;
						$assCommands.Add("m $($startPoint.X.ToString("F2")) $(($startPoint.Y + $offsetY).ToString("F2"))");

						$currentPoint = $startPoint;
						foreach ($segment in $figure.Segments) {
							if ($segment -is [System.Windows.Media.LineSegment]) {
									$assCommands.Add("l $($segment.Point.X.ToString("F2")) $(($segment.Point.Y + $offsetY).ToString("F2"))");
									$currentPoint = $segment.Point;
							}
							elseif ($segment -is [System.Windows.Media.BezierSegment]) {
									$assCommands.Add("b $($segment.Point1.X.ToString("F2")) $(($segment.Point1.Y + $offsetY).ToString("F2")) $($segment.Point2.X.ToString("F2")) $(($segment.Point2.Y + $offsetY).ToString("F2")) $($segment.Point3.X.ToString("F2")) $(($segment.Point3.Y + $offsetY).ToString("F2"))");
									$currentPoint = $segment.Point3;
							}
							elseif ($segment -is [System.Windows.Media.PolyLineSegment]) {
									foreach ($point in $segment.Points) {
										$assCommands.Add("l $($point.X.ToString("F2")) $(($point.Y + $offsetY).ToString("F2"))");
										$currentPoint = $point;
									}
							}
							elseif ($segment -is [System.Windows.Media.PolyBezierSegment]) {
									$points = $segment.Points;
									for ($i = 0; $i -lt $points.Count; $i += 3) {
										if ($i + 2 -ge $points.Count) { break }
										$assCommands.Add("b $($points[$i].X.ToString("F2")) $(($points[$i].Y + $offsetY).ToString("F2")) $($points[$i+1].X.ToString("F2")) $(($points[$i+1].Y + $offsetY).ToString("F2")) $($points[$i+2].X.ToString("F2")) $(($points[$i+2].Y + $offsetY).ToString("F2"))");
										$currentPoint = $points[$i + 2];
									}
							}
						}
						$assCommands.Add("l $($startPoint.X.ToString("F2")) $(($startPoint.Y + $offsetY).ToString("F2"))"); <# 闭合路径 #>
					}

					<# 构建 ASS 绘图格式 #>
					$assDrawing = "{\p1} " + ($assCommands -join " ") + " {\p0}";
					$assDrawing;
				}

				try {
					Get-GlyphData -Character $Character -FontName $FontName -FontSize $FontSize;
				}
				catch {
					$out = "[ERROR] Character=$Character, FontName=$FontName, FontSize=$FontSize, Error=$($_.Exception.Message)";
					
					$utf8Bytes = [System.Text.Encoding]::UTF8.GetBytes($out);
					$base64String = [Convert]::ToBase64String($utf8Bytes);
					Write-Output $base64String;
				}
		]==]

		local res = user_var.psCode(ps_script, true)
		res = res:gsub("\r?\n$", "")
		if not res:find("^{") then
			local decoded = user_var.debase64(res)
			if decoded:find("^%[ERROR%]") then
				user_var.debug(string.format(
					"%s - %s: %s",
					user_var.temp_line, user_var.num, decoded
				))
				return nil
			end
		end

		return res
	end,
}
local _this_line, _this_index_time = nil, 0
setmetatable(user_var, {
	__index = function(t, k)
		if _this_index_time > 2 or not t.bere_line then
			_this_index_time = 0
			return nil
		elseif k == "this" then
			local num = t.bere_line - user_var.begin + 1
			if _this_line and _this_line.num == num then
				return _this_line
			end
			_this_line = t.sub[t.bere_line]
			setmetatable(_this_line, {
				__index = function(_, _k)
					_this_line = t.sub[t.bere_line]
					local meta, styles = karaskel.collect_head(t.sub)
					karaskel.preproc_line_pos(meta, styles, _this_line)
					return _this_line[_k]
				end	
			})
			_this_line.num = num
			_this_index_time = 0
			return _this_line
		elseif k == "start_frame" then
			_this_index_time = _this_index_time + 1
			if t.this["start_time"] then
				_this_index_time = 0
				return user_var.ms2f(_this_line["start_time"])
			else
				_this_index_time = 0
				return nil
			end
		elseif k == "end_frame" then
			_this_index_time = _this_index_time + 1
			if t.this["end_time"] then
				_this_index_time = 0
				return user_var.ms2f(_this_line["end_time"])
			else
				_this_index_time = 0
				return nil
			end
		else
			_this_index_time = _this_index_time + 1
			if t.this[k] then
				_this_index_time = 0
				return _this_line[k]
			else
				_this_index_time = 0
				return nil
			end
		end
	end
})
local user_var_org = user_var.deepCopy(user_var)

--初始化，删除所有beretag!行，并还原:beretag@行
local function initialize(sub,begin)
	user_var = user_var_org.deepCopy(user_var_org)
	_this_line = nil

	local findline = begin
	aegisub.progress.title(tr"Tag Replace - Initializing")
	while findline <= #sub do
		if aegisub.progress.is_cancelled() then aegisub.cancel() end
		aegisub.progress.set(100 * findline / #sub)

		if sub[findline].effect:find("^beretag!") then --删除beretag!行
			sub.delete(findline)
		elseif sub[findline].effect:find("^:beretag@") then --还原:beretag@行
			local new_line = sub[findline]
			new_line.comment = false
			new_line.effect = new_line.effect:sub(2)
			sub[findline] = new_line
			findline = findline + 1
		else
			findline = findline + 1
		end
	end
end

get_class = function(effect,is_temp)
	local class={}
	if is_temp then
		for word in effect:match("@([^#]*)#"):gmatch("[^;]+") do
			table.insert(class,word)
		end
	else
		if effect:find("^beretag[@!]") then
			for word in effect:sub(9):gmatch("[^;]+") do
				table.insert(class,word)
			end
		end
	end
	return class
end

local function cmp_class(temp_effct, bere_effct, strict)
	local temp_class=get_class(temp_effct,true)

	local bere_class=get_class(bere_effct,false)

	if strict then
		if #temp_class ~= #bere_class then return false end
		table.sort(temp_class) table.sort(bere_class)
		for i=1,#temp_class do
			if temp_class[i] ~= bere_class[i] then
				return false
			end
		end
		return true
	else
		for i,j in pairs(temp_class) do
			for p,k in pairs(bere_class) do
				if j==k then return true end
			end
		end
		return false
	end
end

local function get_mode(effect)--return table
	local modestring = effect:match("#(.*)$")
	local mode={
		pre=false,
		recache=false,
		cuttag=false,
		strictstyle=false,
		strictactor=false,
		strictclass=false,
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

--input文本和replace次数，通过re_num映射karaok变量至变量表
local function var_expansion(text, re_num, sub)
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
		pos1, pos2 = text:find("%$[%w_%[%]%.\"%-%+%*/%%%^]+")
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
				text = text:sub(1,pos1-1).."!return user_var."..var.."!"..text:sub(pos2+1)
			end
		end
	end
	--扩展表达式
	user_var.exp_num = re_num - 1
	while true do
		pos1, pos2 = text:find("!.-!")
		if not pos1 then break end
		local load_fun, err = load("return function(sub,user_var) "..text:sub(pos1+1,pos2-1).." end")

		if not load_fun then
			user_var.debug(
				string.format(tr"[var_expansion] Error in template line %s and beretag line %s: %s", user_var.temp_line, user_var.num, err),
				true)
		end

		local return_str, err

		if user_var.use_xpcall then
			xpcall(
				function ()
					return_str = load_fun()(sub,user_var)
				end,
				function (e)
					user_var.debug(debug.traceback(e, 2))
					err = e
				end
			)
		else
			return_str = load_fun()(sub,user_var)
		end

		if err then error(err) end

		if not return_str then return_str="" end
		text = text:sub(1,pos1-1)..return_str..text:sub(pos2+1)
	end
	return text
end

local append_num

local function do_replace(sub, bere, mode)--return int
	if user_var.this.comment or not user_var.this.effect:find("^beretag[@!]") then return 1 end--若该行被注释或为非beretag行，则跳过
	local temp_line_now = sub[user_var.temp_line]
	if not cmp_class(temp_line_now.effect, user_var.this.effect, mode.strictclass) then return 1 end--判断该行class是否与模板行class有交集
	--准备replace
	user_var.bere_num = user_var.bere_num + 1
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
	local temp_tag, temp_add_tail = temp_line_now.text:match("^{(.-)}"), temp_line_now.text:match("^{.-}(.*)")
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
				local find_list = {new_text:find(var_expansion(temp_tag,re_num,sub))}
				local pos1, pos2 = find_list[1], find_list[2]
				table.remove(find_list, 1) table.remove(find_list, 1)
				user_var.bere_text = new_text:sub(pos1,pos2)
				user_var.bere_match = find_list

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
				local find_list = {new_text:find(var_expansion(temp_tag,re_num,sub))}
				local pos1, pos2 = find_list[1], find_list[2]
				table.remove(find_list, 1) table.remove(find_list, 1)
				user_var.bere_text = new_text:sub(pos1,pos2)
				user_var.bere_match = find_list
				
				new_text = new_text:sub(1,pos1-1) .. var_expansion(temp_re_tag,re_num,sub) .. new_text:sub(pos2+1)
				table.insert(insert_table, new_text)
				re_num = re_num+1
			end
		end
	elseif mode.cuttime then
		local fps = user_var.forcefps or 23.976

		local end_value_table = {}
		for v in var_expansion(temp_re_tag,1,sub):gmatch("[^\\]+") do
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
		for v in var_expansion(temp_tag,1,sub):gmatch("[^\\]+") do
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
				if value_table[i][2][p][1]:find("^[%d%.]+$") and value_table[i][2][p][2]:find("^[%d%.]+$") then--十进制
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

		local function _getTag(current_time, total_time, value_table, end_value_table)
			local result = ""

			for i = 1, #value_table do
				if #value_table[i][2] == 1 then
					result = result.."\\"..value_table[i][1] .. _typeChange(_valueCalculation(current_time, total_time, value_table[i], 1), value_table[i][3])
				else
					local str=""
					for p=1,#value_table[i][2] do
						str = str .. _typeChange(_valueCalculation(current_time, total_time, value_table[i], p), value_table[i][3])..","
					end
					result = result.."\\"..value_table[i][1].."("..str:sub(1,-2)..")"
				end
			end

			return "{"..result.."}"
		end
		
		if user_var.cuttime.frame_model and aegisub.video_size() then
			local start_f, end_f = user_var.ms2f(insert_line.start_time), user_var.ms2f(insert_line.end_time)
			local total_time = end_f-start_f
			for i=1,total_time do
				local line = user_var.deepCopy(insert_line)
				line.effect = "beretag!" .. line.effect:sub(9)
				line.start_time = user_var.f2ms(start_f+i-1)
				line.end_time = user_var.f2ms(start_f+i)
				line.text = _getTag(i, total_time, value_table, end_value_table) .. line.text
				table.insert(insert_table, line)
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
				line.text = _getTag(i, total_time, value_table, end_value_table) .. line.text
				table.insert(insert_table, line)
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
				local find_list = {insert_line.text:find(var_expansion(temp_tag,re_num,sub), find_pos)}
				local pos1, pos2 = find_list[1], find_list[2]
				if not pos1 then break end
				table.remove(find_list, 1) table.remove(find_list, 1)
				user_var.bere_text = insert_line.text:sub(pos1,pos2)
				user_var.bere_match = find_list

				find_pos = pos2 + 1 - insert_line.text:len() --先减原长再加新长，防止出现正则表达式导致的字数不同问题
				insert_line.text = insert_line.text:sub(1,pos1-1)..var_expansion(temp_add_tail,re_num,sub)..insert_line.text:sub(pos2+1) --插入temp_add_tail
				find_pos = find_pos + insert_line.text:len()

				re_num = re_num+1
			else
				local find_list = {insert_line.text:find(var_expansion(temp_tag,re_num,sub), find_pos)}
				local pos1, pos2 = find_list[1], find_list[2]
				if not pos1 then break end
				table.remove(find_list, 1) table.remove(find_list, 1)
				user_var.bere_text = insert_line.text:sub(pos1, pos2)
				user_var.bere_match = find_list
				--先在}后插入temp_add_text，再替换temp_tag为temp_re_tag
				local pos3 = insert_line.text:find("}", pos2+1) --记录temp_tag后的}的位置

				local new_temp_add_text = var_expansion(temp_add_text, re_num, sub)
				insert_line.text = insert_line.text:sub(1,pos3)..new_temp_add_text .. insert_line.text:sub(pos3+1) --插入new_temp_add_text
				pos3 = pos3 + new_temp_add_text:len() - insert_line.text:len() --因为temp_tag含有正则表达式，无法直接获取长度，所以pos3先减原长，循环结束时再加新长

				insert_line.text = insert_line.text:sub(1,pos1-1) .. var_expansion(temp_re_tag,re_num,sub) .. insert_line.text:sub(pos2+1) --插入temp_re_tag
				
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
			local i = 1
			if mode.append then
				while i <= #insert_table do
					insert_content = insert_table[i]
					postProc(insert_content)
					sub[0] = insert_content
					i, append_num = i+1, append_num+1
				end
				return 1
			else
				while i <= #insert_table do
					insert_content = insert_table[i]
					postProc(insert_content)
					sub.insert(pos+i-1,insert_content)
					i = i + 1
				end
				return i - 1
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
		_this_line = nil
		if mode.append and bere < user_var.temp_line then
			user_var.temp_line = user_var.temp_line - 1
		end
		return add_line_num
	end
	--注释行，并在effect头部加上:
	local tocmt = sub[bere]
	tocmt.comment = true
	tocmt.effect = ":"..tocmt.effect
	sub[bere] = tocmt
	--将@改为!
	insert_line.effect = "beretag!" .. insert_line.effect:sub(9)
	local add_line_num = _do_insert(bere + 1, insert_line)
	return add_line_num + 1
end

local function find_event(sub)
	for i = 1, #sub do
		if sub[i].section == "[Events]" then
			return i
		end
	end
end

local function do_macro(sub, begin)
	user_var.temp_line = begin
	user_var.sub = sub
	user_var.begin = begin

	append_num = 0 --初始化append边界
	aegisub.progress.title(tr"Tag Replace - Replace")
	for i = begin, #sub do
		if sub[i].effect:find("^template") and sub[i].comment then
			user_var.progress[2] = user_var.progress[2] + 1
		end
	end

	while user_var.temp_line <= #sub do
		--Find template lines. 检索模板行
		local temp_line_now = sub[user_var.temp_line]
		if temp_line_now.comment then
			if aegisub.progress.is_cancelled() then aegisub.cancel() end
			aegisub.progress.set(100 * user_var.progress[1] / math.max(user_var.progress[2], 1))
			user_var.progress[1] = user_var.progress[1] + 1

			if temp_line_now.effect:find("^template@[^#]-#.*$") then
				local mode = get_mode(temp_line_now.effect)
				local bere = begin
				--根据mode判断
				if mode.classmix then
					local first_table,second_table = {},{}
					local to_comment
					local first_class, second_class, new_class = temp_line_now.text:match("^{(.-)}{(.-)}{(.-)}")
					for bere = begin, #sub - append_num do
						local bere_line = sub[bere]
						if (not mode.strictstyle or temp_line_now.style == bere_line.style) and (not mode.strictactor or temp_line_now.actor == bere_line.actor) and cmp_class(temp_line_now.effect,bere_line.effect, mode.strictclass) then
							to_comment = false
							if cmp_class('@'..first_class..'#',bere_line.effect, mode.strictclass) then
								table.insert(first_table, user_var.deepCopy(bere_line))
								to_comment = true
							end
							if cmp_class('@'..second_class..'#',bere_line.effect, mode.strictclass) then
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

					--合并
					local mix_table = {}
					for i = 1,math.max(#first_table,#second_table) do
						local new = user_var.classmixProc(first_table[i],second_table[i],new_class)
						new.effect = "beretag!"..new.effect:sub(9)
						table.insert(mix_table, new)
					end

					--插入
					if mode.append then
						for _,v in ipairs(mix_table) do
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
							_this_line = nil
						else
							i=i+1
						end
					end
				elseif mode.onlyfind then
					while bere <= #sub - append_num do
						user_var.bere_line = bere
						if not user_var.comment and user_var.effect:find("^beretag[@!]")
							and cmp_class(temp_line_now.effect, user_var.effect, mode.strictclass)
							and (
								not mode.strictstyle
								or temp_line_now.style == user_var.style)
							and (
								not mode.strictactor
								or temp_line_now.actor == user_var.actor)
						then
							var_expansion(temp_line_now.text, 2, sub)
							if mode.uninsert then
								local new_line = sub[bere]
								if new_line.effect:sub(8,8) == '@' then
									new_line.comment = true
									new_line.effect = ":" .. new_line.effect
									sub[bere] = new_line
								else
									sub.delete(bere)
									_this_line = nil
									bere = bere - 1
								end
							end
						end
						bere = bere + 1
					end
				else
					--先 (keyframe) 后 替换
					if mode.keyframe then
						local key_text_table = {}
						if user_var.keytext~="" and user_var.keytext then
							for line in user_var.keytext:gsub([[\N]],'\n'):gmatch("[^\n]+") do table.insert(key_text_table,line) end
						end
						local find_end = #sub
						while bere <= find_end do--找到bere行
							user_var.bere_line = bere
							if not user_var.this.comment and user_var.this.effect:find("^beretag[@!]")
								and cmp_class(temp_line_now.effect, user_var.this.effect, mode.strictclass) 
								and (not mode.strictactor or temp_line_now.actor == user_var.this.actor)
								and (not mode.strictstyle or temp_line_now.style == user_var.this.style)
								then

								local insert_key_line

								-- 替换 \fade? 和 \t

								local function gsub_callback_tag_fad(match)
									local t1, t2 = match:match("%(([^,]+),([^%)]+)%)")
									t1, t2 = math.floor(tonumber(t1)), math.floor(tonumber(t2))

									local duration = math.floor(user_var.end_time - user_var.start_time)
									local t = insert_key_line.start_time - user_var.start_time
									if t < t1 or t > duration - t2 then
										return string.format([[\fade(%d,%d,%d,%d,%d,%d,%d)]],
											255, 0, 255,
											0, t1,
											duration - tonumber(t2), duration)
									else
										return ""
									end
								end

								local function gsub_callback_tag_fade(match)
									-- \fade(<a1>,<a2>,<a3>,<t1>,<t2>,<t3>,<t4>)
									local vals = {}
									for s in (match:match([[^\fade%((.+)%)$]]) or ""):gmatch("[^,]+") do
										table.insert(vals, math.floor(s))
									end
									if #vals ~= 7 then
										user_var.debug(string.format([[Wrong \fade in %d]], user_var.num), true)
									end

									local offset = math.floor(user_var.start_time - insert_key_line.start_time)
									return string.format([[\fade(%d,%d,%d,%d,%d,%d,%d)]],
										vals[1], vals[2], vals[3],
										vals[4] + offset, vals[5] + offset,
										vals[6] + offset, vals[7] + offset)
								end

								local function gsub_callback_tag_t(match)
									local vals = {}
									for s in (match:match([[^\t%(([^\]+).+%)$]]) or ""):gmatch("[^,]+") do
										table.insert(vals, s)
									end
									if #vals == 0 then
										vals[1] = 0
										vals[2] = user_var.end_time - user_var.start_time
										vals[3] = 1
									elseif #vals == 1 then -- 加速度
										vals[3] = vals[1]
										vals[1] = 0
										vals[2] = user_var.end_time - user_var.start_time
									elseif #vals == 2 then -- 时间
										vals[3] = 1
									end

									vals[4] = match:match([[^\t%([^\]*(.+)%)$]])
									if not vals[4] or #vals > 4 then
										user_var.debug(string.format([[Wrong \t in %d]], user_var.num), true)
									end

									local offset = user_var.start_time - insert_key_line.start_time
									return string.format([[\t(%d,%d,%s,%s)]],
										vals[1] + offset,
										vals[2] + offset,
										vals[3], vals[4])
								end

								if (user_var.keytext=="" or not user_var.keytext)
									and user_var.keyclip ~= "" and user_var.keyclip
									then -- 只有clip的情况

									--处理keyclip内容
									local key_clip_point_table = {}
									local key_clip_table = {}
									for line in user_var.keyclip:gsub([[\N]],'\n'):gmatch("[^\n]+") do table.insert(key_clip_table, line) end

									if key_clip_table[1] ~= "shake_shape_data 4.0" then
										user_var.debug([[The $keyclip "]]..tostring(key_clip_table[1])..[[" is not supported]])
									end

									local height = select(1,karaskel.collect_head(user_var.sub)).res_y
									for _, line in ipairs(key_clip_table) do
										if line:sub(1,11) == "vertex_data" then
											line = line:sub(13)

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
												[[{\clip(m ]]..line:sub(0, pos2).."l"..line:sub(pos2)..")}")
										end
									end

									--注释bere行
									if user_var.this.effect:find("^beretag@") then
										local line = sub[bere]
										line.effect = ":"..line.effect
										line.comment = true
										sub[bere] = line
									else
										local line = sub[bere]
										line.comment = true
										sub[bere] = line
									end

									local key_line = sub[user_var.bere_line]
									key_line.effect = "beretag!"..key_line.effect:sub(9)
									local fps = user_var.forcefps or key_text_table[2]:match("%d+%.?%d*")
									local time_start, step_num, time_end = key_line.start_time, 1
									if time_start <= 0 then time_start = -400/fps end
									time_end = time_start
									local key_clip_point_table_len = #key_clip_point_table
									if mode.append then
										for i = 1, key_clip_point_table_len do
											insert_key_line = key_line
											insert_key_line.text = key_clip_point_table[i] .. insert_key_line.text

											insert_key_line.start_time = time_end
											time_end = time_start + step_num * 1000 / fps
											insert_key_line.end_time = time_end
											step_num = step_num + 1

											insert_key_line.text = insert_key_line.text
												:gsub([[\fad%([^%)]+%)]], gsub_callback_tag_fad)
												:gsub([[\fade%([^%)]+%)]], gsub_callback_tag_fade)
												:gsub([[\t%([^%)]+%)]], gsub_callback_tag_t)

											user_var.keyProc(insert_key_line, {i,key_clip_point_table_len})
											sub[0] = insert_key_line
										end
									else
										local insert_pos = bere + 1
										for i=1,key_clip_point_table_len do
											local insert_key_line = key_line
											insert_key_line.text = key_clip_point_table[i] .. insert_key_line.text

											insert_key_line.start_time = time_end
											time_end = time_start + step_num * 1000 / fps
											insert_key_line.end_time = time_end
											step_num = step_num + 1

											insert_key_line.text = insert_key_line.text
												:gsub([[\fad%([^%)]+%)]], gsub_callback_tag_fad)
												:gsub([[\fade%([^%)]+%)]], gsub_callback_tag_fade)
												:gsub([[\t%([^%)]+%)]], gsub_callback_tag_t)

											user_var.keyProc(insert_key_line, {i,key_clip_point_table_len})
											sub.insert(insert_pos,insert_key_line)
											insert_pos = insert_pos+1
										end
										find_end = find_end + insert_pos - bere - 1
										bere = insert_pos - 1
									end

								else

									if key_text_table[1] ~= "Adobe After Effects 6.0 Keyframe Data" then
										user_var.debug(string.format(tr[[The $keytext "%s" is not supported]], tostring(key_text_table[1])), true)
									end

									user_var.bere_line = bere

									--注释bere行
									if user_var.this.effect:find("^beretag@") then
										local line = sub[bere]
										line.effect = ":"..line.effect
										line.comment = true
										sub[bere] = line
									else
										local line = sub[bere]
										line.comment = true
										sub[bere] = line
									end

									--补全tag
									local key_line = user_var.deepCopy(user_var.this) --必须复制处理后的行，后面要使用新属性
									if not key_line.text:find("{.-}") then
										key_line.text = "{}"..key_line.text
									end
									if not user_var.text:find([[\pos%([^,]-,[^,%)]-%)]]) then
										local pos = key_line.text:find("}")
										key_line.text = key_line.text:sub(1,pos-1)..string.format([[\pos(%.2f,%.2f)]], key_line.x, key_line.y)..key_line.text:sub(pos)
									end
									if not user_var.text:find([=[\fscx[%d%.]]=]) then
										local pos = key_line.text:find("}")
										key_line.text = key_line.text:sub(1,pos-1)..[[\fscx100]]..key_line.text:sub(pos)
									end
									if not user_var.text:find([=[\fscy[%d%.]]=]) then
										local pos = key_line.text:find("}")
										key_line.text = key_line.text:sub(1,pos-1)..[[\fscy100]]..key_line.text:sub(pos)
									end
									if not user_var.text:find([=[\frz%-?[%d%.]]=]) then
										local pos = key_line.text:find("}")
										key_line.text = key_line.text:sub(1,pos-1)..[[\frz0]]..key_line.text:sub(pos)
									end
									if not user_var.text:find([[\org%([^,]+,[^,]+%)]]) then
										local pos = key_line.text:find("}")
										key_line.text = key_line.text:sub(1,pos-1)..[[\org]]..key_line.text:match([[\pos(%([^%)]-%))]])..key_line.text:sub(pos)
									end
									key_line.effect = "beretag!"..key_line.effect:sub(9)

									--处理keytext内容
									local fps = user_var.forcefps or key_text_table[2]:match("%d+%.?%d*")
									local time_start, step_num, time_end = key_line.start_time, 1
									if time_start <= 0 then time_start = -400/fps end
									local key_text_table_pos = 2
									while key_text_table[key_text_table_pos] ~= [[	Frame	X pixels	Y pixels	Z pixels]] do
										key_text_table_pos=key_text_table_pos+1
									end
									key_text_table_pos=key_text_table_pos+1

									local key_pos, key_scale, key_rot = {},{},{}
									while key_text_table[key_text_table_pos] ~= "Scale" do --read Position
										table.insert(key_pos, {key_text_table[key_text_table_pos]:match("^\t[^\t]*\t([^\t]*)\t([^\t]*)")})
										key_text_table_pos = key_text_table_pos + 1
									end
									key_text_table_pos = key_text_table_pos+2
									while key_text_table[key_text_table_pos] ~= "Rotation" do --read Scale
										table.insert(key_scale, {key_text_table[key_text_table_pos]:match("^\t[^\t]*\t([^\t]*)\t([^\t]*)")})
										key_text_table_pos = key_text_table_pos + 1
									end
									key_text_table_pos = key_text_table_pos+2
									while key_text_table[key_text_table_pos] ~= "End of Keyframe Data" do --read Rotation
										table.insert(key_rot, {key_text_table[key_text_table_pos]:match("^\t[^\t]*\t([^\t]*)")})
										key_text_table_pos = key_text_table_pos + 1
									end
									--处理keyclip内容
									local key_clip_point_table = {}
									if user_var.keyclip ~= "" and user_var.keyclip then
										local key_clip_table = {}
										for line in user_var.keyclip:gsub([[\N]],'\n'):gmatch("[^\n]+") do table.insert(key_clip_table,line) end

										if key_clip_table[1] ~= "shake_shape_data 4.0" then
											user_var.debug([["]]..key_clip_table[1]..[[" is not supported]])
										end

										local height = select(1, karaskel.collect_head(user_var.sub)).res_y
										for _, line in ipairs(key_clip_table) do
											if line:sub(1, 11) == "vertex_data" then
												line=line:sub(13)

												--坐标转换
												local coords = {}
												for x, y in string.gmatch(line, "([^ ]-) ([^ ]-) ") do
													table.insert(coords, {tonumber(x), tonumber(y)})
												end
												for _, coord in ipairs(coords) do
													coord[2] = height - coord[2]
												end
												line = ""
												for _, coord in ipairs(coords) do
													line = line..string.format("%.2f %.2f ", coord[1], coord[2])
												end

												local _, pos2 = line:find("^[^ ]- [^ ]- ")
												table.insert(key_clip_point_table,
													[[{\clip(m ]]..line:sub(0, pos2).."l"..line:sub(pos2)..")}")
											end
										end
									end
									for i = #key_clip_point_table + 1, #key_rot do
										key_clip_point_table[i] = ""
									end
									--开始插入行
									local x, y, fx, fy, fz, ox, oy
									local pos_table, out_value = {1,#key_line.text}, {}
									
									local pos1,pos2 = key_line.text:find([[\pos%([^,]-,]])
									x = key_line.text:sub(pos1+5, pos2-1)
									table.insert(out_value, {pos1, x, key_pos, 1})
									table.insert(pos_table, pos1+4) table.insert(pos_table, pos2)

									pos1, pos2 = key_line.text:find([[,[^,]-%)]], pos2)
									y = key_line.text:sub(pos1+1, pos2-1)
									table.insert(out_value, {pos1, y, key_pos, 2})
									table.insert(pos_table, pos1) table.insert(pos_table, pos2)

									pos1, pos2 = key_line.text:find([[\fscx[%d%.]+]])
									fx = key_line.text:sub(pos1+5, pos2)
									table.insert(out_value, {pos1, fx, key_scale, 1})
									table.insert(pos_table, pos1+4) table.insert(pos_table, pos2+1)

									pos1, pos2 = key_line.text:find([[\fscy[%d%.]+]])
									fy = key_line.text:sub(pos1+5, pos2)
									table.insert(out_value, {pos1, fy, key_scale, 2})
									table.insert(pos_table, pos1+4) table.insert(pos_table, pos2+1)

									pos1, pos2 = key_line.text:find([[\frz%-?[%d%.]+]])
									fz = key_line.text:sub(pos1+4, pos2)
									table.insert(out_value, {pos1, fz, key_rot, 1})
									table.insert(pos_table, pos1+3) table.insert(pos_table, pos2+1)
									
									pos1, pos2 = key_line.text:find([[\org%([^,]-,]])
									ox = key_line.text:sub(pos1+5, pos2-1)
									table.insert(out_value, {pos1, ox, key_pos, 1})
									table.insert(pos_table, pos1+4) table.insert(pos_table, pos2)

									pos1, pos2 = key_line.text:find([[,[^,]-%)]],pos2)
									oy = key_line.text:sub(pos1+1, pos2-1)
									table.insert(out_value, {pos1, oy, key_pos, 2})
									table.insert(pos_table, pos1) table.insert(pos_table, pos2)
									

									table.sort(out_value, function(a,b) return a[1] < b[1] end) table.sort(pos_table)

									local insert_key_line_table = {
										key_line.text:sub(pos_table[ 1], pos_table[ 2]),
										key_line.text:sub(pos_table[ 3], pos_table[ 4]),
										key_line.text:sub(pos_table[ 5], pos_table[ 6]),
										key_line.text:sub(pos_table[ 7], pos_table[ 8]),
										key_line.text:sub(pos_table[ 9], pos_table[10]),
										key_line.text:sub(pos_table[11], pos_table[12]),
										key_line.text:sub(pos_table[13], pos_table[14]),
										key_line.text:sub(pos_table[15], pos_table[16])
									}
									--根据mode插入
									local function key_line_value(num,i)
										-- out_value[num][3][i][out_value[num][4]] keytext 当前行值
										-- out_value[num][3][1][out_value[num][4]] keytext 第一行值
										-- out_value[num][2] beretag 对应标签的值
										local _char = insert_key_line_table[num]:sub(-1)
										if _char=='x' or _char=='y' then
											return
												insert_key_line_table[num] ..
												math.floor((out_value[num][2] * out_value[num][3][i][out_value[num][4]] / out_value[num][3][1][out_value[num][4]])*100+0.5)/100
										elseif _char=='z' then
											return
												insert_key_line_table[num] ..
												math.floor((out_value[num][2] - out_value[num][3][i][out_value[num][4]] + out_value[num][3][1][out_value[num][4]])*100+0.5)/100
										else
											return
												insert_key_line_table[num] ..
												math.floor((out_value[num][2] + out_value[num][3][i][out_value[num][4]] - out_value[num][3][1][out_value[num][4]])*100+0.5)/100
										end
									end

									time_end = time_start
									local key_rot_len = #key_rot
									if mode.append then
										for i = 1, key_rot_len do
											insert_key_line = key_line
											insert_key_line.text =
												key_clip_point_table[i] ..
												key_line_value(1, i) ..
												key_line_value(2, i) ..
												key_line_value(3, i) ..
												key_line_value(4, i) ..
												key_line_value(5, i) ..
												key_line_value(6, i) ..
												key_line_value(7, i) ..
												insert_key_line_table[8]

											insert_key_line.start_time = time_end
											time_end = time_start + step_num*1000/fps
											insert_key_line.end_time = time_end
											step_num = step_num+1

											insert_key_line.text = insert_key_line.text
												:gsub([[\fad%([^%)]+%)]], gsub_callback_tag_fad)
												:gsub([[\fade%([^%)]+%)]], gsub_callback_tag_fade)
												:gsub([[\t%([^%)]+%)]], gsub_callback_tag_t)

											user_var.keyProc(insert_key_line, {i, key_rot_len})
											sub[0] = insert_key_line
										end
									else
										local insert_pos = bere + 1
										for i = 1, key_rot_len do
											insert_key_line = key_line
											insert_key_line.text =
												key_clip_point_table[i] ..
												key_line_value(1, i) ..
												key_line_value(2, i) ..
												key_line_value(3, i) ..
												key_line_value(4, i) ..
												key_line_value(5, i) ..
												key_line_value(6, i) ..
												key_line_value(7, i) ..
												insert_key_line_table[8]

											insert_key_line.start_time = time_end
											time_end = time_start + step_num * 1000 / fps
											insert_key_line.end_time = time_end
											step_num = step_num+1

											insert_key_line.text = insert_key_line.text
												:gsub([[\fad%([^%)]+%)]], gsub_callback_tag_fad)
												:gsub([[\fade%([^%)]+%)]], gsub_callback_tag_fade)
												:gsub([[\t%([^%)]+%)]], gsub_callback_tag_t)

											user_var.keyProc(insert_key_line, {i, key_rot_len})
											sub.insert(insert_pos, insert_key_line)
											insert_pos = insert_pos+1
										end
										find_end = find_end + insert_pos - bere - 1
										bere = insert_pos - 1
									end
								
								end
							end
							--next
							bere = bere + 1
						end
						--end
						bere = begin
						while bere <= #sub do
							if user_var.this.effect:find("^beretag!") and user_var.this.comment then
								sub.delete(bere)
							end
							bere = bere + 1
						end
						_this_line = nil
						bere = begin

						user_var.keytext, user_var.keyclip = "", ""
					end
					--先 keyframe 后 (替换)
					while bere <= #sub - append_num do
						user_var.bere_line = bere
						if (not mode.strictstyle
								or temp_line_now.style == user_var.this.style)
							and
							(not mode.strictactor
								or temp_line_now.actor == user_var.this.actor)
							then
							bere = bere + do_replace(sub, bere, mode)
						else
							bere = bere + 1
						end
					end
				end
				if mode.recache and #user_var.subcache > 0 then--插入缓存行
					for i = 1, #user_var.subcache do
						user_var.subcache[i].effect = "beretag!"..user_var.subcache[i].effect:sub(9)
					end
					if mode.append then
						for _, v in ipairs(user_var.subcache) do
							sub[0]=v
						end
					else
						for i, v in ipairs(user_var.subcache) do
							sub.insert(user_var.temp_line+i,v)
						end
					end
					user_var.subcache = {}
				end
			end
		--检索命令行
			if temp_line_now.effect:find("^template#")
				and not get_mode(temp_line_now.effect).pre
				then
				var_expansion(temp_line_now.text, 2, sub)
				if #user_var.subcache > 0 then --插入缓存行
					local mode = get_mode(temp_line_now.effect)
					if mode.recache then
						for i = 1, #user_var.subcache do
							user_var.subcache[i].effect = "beretag!"..user_var.subcache[i].effect:sub(9)
						end
						if mode.append then
							for _, v in ipairs(user_var.subcache) do
								sub[0] = v
							end
						else
							for i, v in ipairs(user_var.subcache) do
								sub.insert(user_var.temp_line + i, v)
							end
						end
						user_var.subcache = {}
					end
				end
			end
			append_num = 0 --还原append边界
		end
		user_var.temp_line  = user_var.temp_line + 1
		user_var.bere_line  = false
		user_var.bere_text  = ""
		user_var.bere_match = {}
		user_var.bere_num   = 0
	end

	--删除所有空的 beretag! 行
	local i = begin
	while i <= #sub do
		if sub[i].effect:find("^beretag!") and not sub[i].comment and sub[i].text=="" then
			sub.delete(i)
		else
			i = i + 1
		end
	end

	-- 插入 msg
	local msg_line = sub[begin]
	msg_line.comment, msg_line.effect = true, "beretag! Tag Replace Message"
	msg_line.style, msg_line.text = "", ""
	msg_line.start_time, msg_line.end_time = 0, 0
	for _, msg in ipairs(user_var.msg) do
		local line = user_var.deepCopy(msg_line)
		line.text = msg
		sub[-begin] = line
	end
end

local function pre_template_line(sub, begin)
	aegisub.progress.title(tr"Tag Replace - Exp pre line")
	for i = begin, #sub do
		local line = sub[i]
		if line.comment and line.effect:find("^template#") and get_mode(line.effect).pre then
			var_expansion(line.text, 2, sub)
		end
	end
end

local function macro_processing_function(subtitles)--Execute Macro. 执行宏
	local begin = find_event(subtitles)
	initialize(subtitles, begin)
	pre_template_line(subtitles, begin)
	do_macro(subtitles, begin)
end

local function comment_template_line(sub, selected_table)
	for i=find_event(sub),#sub do
		if selected_table[tostring(i)]~=true and sub[i].effect:find("^template[@#]") and sub[i].comment then
			local line = sub[i]
			line.effect = ":"..line.effect
			sub[i] = line
		end
	end
end

local function uncomment_template_line(sub)
	for i = find_event(sub), #sub do
		local line = sub[i]
		if line.effect:find("^:template") then
			line.effect = line.effect:sub(2)
			sub[i] = line
		end
	end
end

--Execute Macro in selected lines. 在所选行执行宏
local function macro_processing_function_selected(subtitles, selected_lines)
	local begin = find_event(subtitles)
	initialize(subtitles, begin)
	pre_template_line(subtitles, begin)
	--搜索所有非所选的template行，对其中注释行头部添加:，执行完后再还原
	local selected_table = {}
	for i,v in ipairs(selected_lines) do
		selected_table[tostring(v)] = true
	end
	comment_template_line(subtitles, selected_table)
	do_macro(subtitles, begin)
	uncomment_template_line(subtitles)
end

local function macro_processing_function_initialize(subtitles)--初始化
	initialize(subtitles, find_event(subtitles))
end

aegisub.register_macro(tr"Tag Replace Apply", tr"Replace all strings with your settings", macro_processing_function)
aegisub.register_macro(tr"Tag Replace Apply in selected lines", tr"Replace selected lines' strings with your settings", macro_processing_function_selected)
aegisub.register_macro(tr"Tag Replace Initialize", tr"Only do the initialize function", macro_processing_function_initialize)

local function filter_processing_function(subtitles, old_settings)
	local begin = find_event(subtitles)
	initialize(subtitles, begin)
	pre_template_line(subtitles, begin)
	do_macro(subtitles, begin)
	for i = find_event(subtitles), #subtitles do
		if subtitles[i].effect:find("^beretag!") and not subtitles[i].comment then
			local line = subtitles[i]
			line.effect = "beretag!"
			subtitles[i] = line
		end
	end
end

aegisub.register_filter(tr"Tag Replace", tr"Replace and clear sth", 2500, filter_processing_function)