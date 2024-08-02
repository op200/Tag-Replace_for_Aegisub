local util = require("aegisub.util")
require("karaskel")

local gt=aegisub.gettext

script_name = gt"Tag Replace"
script_description = gt"Replace string such as tag"
script_author = "op200"
script_version = "1.6"
-- https://github.com/op200/Tag-Replace_for_Aegisub


local user_var--自定义变量键值表
user_var={
	sub,
	subcache={},
	kdur={0,0},--存储方式为前缀和，从[2]开始计数，方便相对值计算
	begin,
	temp_line,
	bere_line,
	keyfile="",
	keytext="",
	forcefps=false,
	bere_text="",
	--内置函数
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
	colorGradient = function(line_info, rgba, step_set, tags, control_points)
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
		local function bezier_interpolate(t, control_points)
			local n = #control_points - 1
			local p = {0, 0, 0, 0}
			for i = 0, n do
				local binomial_coeff = math.comb(n, i)
				local u = (1 - t) ^ (n - i)
				local tt = t ^ i
				for j = 1, 4 do
					p[j] = p[j] + binomial_coeff * u * tt * control_points[i + 1][j]
				end
			end
			return p
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
			x1, y1, x2, y2 = pos_line.left - expand, pos_line.top - expand, pos_line.right + expand, pos_line.bottom + expand
		end
	
		local pos_x, pos_y = pos_line.x, pos_line.y
	
		rgba1, rgba2, rgba3, rgba4 = rgba[1], rgba[2], rgba[3], rgba[4]
		if type(rgba1) == "string" then rgba1 = {util.extract_color(rgba1)} end
		if type(rgba2) == "string" then rgba2 = {util.extract_color(rgba2)} end
		if type(rgba3) == "string" then rgba3 = {util.extract_color(rgba3)} end
		if type(rgba4) == "string" then rgba4 = {util.extract_color(rgba4)} end
	
		-- 计算矩形的宽度和高度
		local width = x2 - x1
		local height = y2 - y1
	
		step_set = step_set or {nil, nil}
		step_set[1] = step_set[1] or width + 1
		step_set[2] = step_set[2] or height + 1
	
		tags = tags or {nil, nil}
		color_tag = tags[1] or "c"
		transparent_tag = tags[2] or "1a"
	
		control_points = control_points or {rgba1, rgba2, rgba3, rgba4, rgba1, rgba4}
	
		-- 遍历矩形中的每个点
		for x = x1, x2, step_set[1] do
			for y = y1, y2, step_set[2] do
				-- 计算点(x, y)在矩形中的相对位置
				local dx = (x - x1) / width
				local dy = (y - y1) / height
	
				-- 使用贝塞尔曲线插值计算RGBA值
				local rgba_top = bezier_interpolate(dx, {rgba1, control_points[1], control_points[2], rgba2})
				local rgba_bottom = bezier_interpolate(dx, {rgba3, control_points[3], control_points[4], rgba4})
				local rgba = bezier_interpolate(dy, {rgba_top, control_points[5], control_points[6], rgba_bottom})
	
				-- 确保 rgba 是四个有效的整数值
				local r, g, b, a = math.floor(rgba[1] + 0.5), math.floor(rgba[2] + 0.5), math.floor(rgba[3] + 0.5), math.floor(rgba[4] + 0.5)
				if r and g and b and a then
					local subline = user_var.sub[line_num]
					subline.text = string.format("{\\clip(%.2f,%.2f,%.2f,%.2f)\\%s%s\\%s%s\\pos(%s,%s)}%s",
						x, y, x + step_set[1], y + step_set[2],
						color_tag, util.ass_color(rgba[1], rgba[2], rgba[3]),
						transparent_tag, util.ass_alpha(rgba[4]),
						pos_x, pos_y,
						subline.text)
					table.insert(user_var.subcache, subline)
				else
					aegisub.dialog.display({{class = "label", label = "Error: rgba does not contain 4 valid elements" .. r .. g .. b .. a}})
					exit()
				end
			end
		end
	end
}

local function cmp_class(temp_effct,bere_effct)
	local temp_class={}
	for word in temp_effct:match("@(.*)#"):gmatch("[^;]+") do
		table.insert(temp_class,word)
	end

	local bere_class={}
	if bere_effct:find("^beretag[@!]") then
		for word in bere_effct:match("[@!]([^#]*)$"):gmatch("[^;]+") do
			table.insert(bere_class,word)
		end
	end

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
		strictname=false,
		findtext=false,
		append=false,
		keyframe=false
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

local function initialize(sub,begin)
	local findline=begin
	while findline<=#sub do
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
		local expression = text:sub(pos1+1,pos2-1)
		local return_str = loadstring("return function(sub,user_var) "..expression.." end")()(sub,user_var)
		if not return_str then return_str="" end
		text = text:sub(1,pos1-1)..return_str..text:sub(pos2+1)
	end
	return text
end

local append_num

local function do_replace(sub, temp, bere, mode, begin)--return int
	if sub[bere].comment or not sub[bere].effect:find("^beretag") then return 0 end--若该行被注释或为非beretag行，则跳过
--判断该行class是否与模板行class有交集
	if not cmp_class(sub[temp].effect,sub[bere].effect) then return 0 end
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
	local temp_tag, temp_add_tail = sub[temp].text:match("^{(.-)}"), sub[temp].text:match("^{.-}(.*)")
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
		if mode.cuttag then
			local i=1
			if mode.append then
				while i<=#insert_table do
					insert_content.text = insert_table[i]
					sub[0] = insert_content
					i, append_num = i+1, append_num+1
				end
				return 0
			else
				while i<=#insert_table do
					insert_content.text = insert_table[i]
					sub.insert(pos+i-1,insert_content)
					i, append_num = i+1, append_num+1
				end
				return i-2
			end
		end

		if mode.append then
			sub[0] = insert_content
			append_num = append_num+1
			return -1
		else
			sub.insert(pos,insert_content)
			return 0
		end
	end

	if sub[bere].effect:find("^beretag!") then--删除行
		--这里插入和删除的顺序不能更改，否则会导致逆天bug
		local add_line_num = _do_insert(bere+1,insert_line)
		sub.delete(bere)
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
	user_var.sub=sub
	local begin=find_event(sub)
	local temp=begin
	user_var.begin=begin
	initialize(sub,begin)--初始化，删除所有beretag!行，并还原:beretag@行
	append_num=0--初始化append边界
	while temp<=#sub do
		if sub[temp].comment then
		--Find template lines. 检索模板行
			if sub[temp].effect:find("^template@[%w;]-#[%w;]*$") then
				local mode = get_mode(sub[temp].effect)
				local bere = begin
				--根据mode判断
				if mode.keyframe then
					if user_var.keytext~="" then
						user_var.keyfile = os.getenv("TEMP") .. [[\tag-replace_keyfile.txt]]
						local f = io.open(user_var.keyfile,'w')
						f:write(user_var.keytext:gsub([[\N]],'\n'))
						f:close()
					end
					local find_end = #sub
					while bere<=find_end do--找到bere行
						if not sub[bere].comment and sub[bere].effect:find("^beretag") and cmp_class(sub[temp].effect,sub[bere].effect) 
							and (not mode.strictname or sub[temp].actor==sub[bere].actor) and (not mode.strictstyle or sub[temp].style==sub[bere].style) then
							if sub[bere].text:find([[\pos%([^,]*,[^,]*%)]]) then--开始读取文件
								--判断file是否可打开
								local file = io.open(user_var.keyfile)--这个io.open是unicode-monkeypatch.lua里重载的
								local line=file:read("l")
								if not file then
									aegisub.dialog.display({{class="label",label="keyframe file doesn't exist"}})
								end
								if line=="Adobe After Effects 6.0 Keyframe Data" then
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
									--开始处理所读内容
									file:read("l")
									local fps
									if user_var.forcefps then
										fps = user_var.forcefps
									else
										fps = file:read("l"):match("%d+%.?%d*")
									end
									local time_start, step_num, time_end = key_line.start_time, 1
									while line~=[[	Frame	X pixels	Y pixels	Z pixels]] do
										line=file:read("l")
									end
									local key_pos, key_scale, key_rot = {},{},{}
									while true do--read Position
										if not file:read("n") then break end
										table.insert(key_pos,{file:read("n"),file:read("n")})
										file:read("n")
									end
									file:read("l") file:read("l")
									while true do--read Scale
										if not file:read("n") then break end
										table.insert(key_scale,{file:read("n"),file:read("n")})
										file:read("n")
									end
									file:read("l") file:read("l")
									while true do--read Rotation
										if not file:read("n") then break end
										table.insert(key_rot,{file:read("n")})
									end
									file:close()
								--开始插入行
									local x,y,fx,fy,fz
									local pos_table, out_value = {1,#key_line.text}, {}
									
									local pos1,pos2 = key_line.text:find([[\pos%([^,]*,]])
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
									

									table.sort(out_value, function(a,b) return a[1] < b[1] end) table.sort(pos_table)
	
									local insert_key_line_table, insert_key_line = {
										key_line.text:sub(pos_table[1],pos_table[2]),
										key_line.text:sub(pos_table[3],pos_table[4]),
										key_line.text:sub(pos_table[5],pos_table[6]),
										key_line.text:sub(pos_table[7],pos_table[8]),
										key_line.text:sub(pos_table[9],pos_table[10]),
										key_line.text:sub(pos_table[11],pos_table[12])
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
												key_line_value(1,i) ..
												key_line_value(2,i) ..
												key_line_value(3,i) ..
												key_line_value(4,i) ..
												key_line_value(5,i) ..
												insert_key_line_table[6]
	
											insert_key_line.start_time = time_end
											time_end = time_start + math.floor(step_num*1000/fps+0.5)
											insert_key_line.end_time = time_end
											step_num = step_num+1
	
											sub[0] = insert_key_line
										end
									else
										local insert_pos = bere+1
										for i=1,#key_rot do
											insert_key_line = key_line
											insert_key_line.text =
												key_line_value(1,i) ..
												key_line_value(2,i) ..
												key_line_value(3,i) ..
												key_line_value(4,i) ..
												key_line_value(5,i) ..
												insert_key_line_table[6]
	
											insert_key_line.start_time = time_end
											time_end = time_start + math.floor(step_num*1000/fps+0.5)
											insert_key_line.end_time = time_end
											step_num = step_num+1
	
											sub.insert(insert_pos,insert_key_line)
											insert_pos = insert_pos+1
										end
										find_end = find_end + insert_pos - bere - 1
										bere = insert_pos - 1
									end
								else
									aegisub.dialog.display({{class="label",label=gt([["]]..tostring(line)..[[" is not supported]])}})
								end
							else
								aegisub.dialog.display({{class="label",label=gt[["\pos" not found]]}})
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
				end
				if mode.strictstyle then
					if mode.strictname then
						while bere <= #sub - append_num do
							if sub[temp].style == sub[bere].style and sub[temp].actor == sub[bere].actor then
								user_var.temp_line, user_var.bere_line=temp, bere
								bere = bere + 1 + do_replace(sub, temp, bere, mode, begin)
							else
								bere = bere + 1
							end
						end
					else
						while bere <= #sub - append_num do
							if sub[temp].style == sub[bere].style then
								user_var.temp_line, user_var.bere_line=temp, bere
								bere = bere + 1 + do_replace(sub, temp, bere, mode, begin)
							else
								bere = bere + 1
							end
						end
					end
				elseif mode.strictname then
					while bere <= #sub - append_num do
						if sub[temp].actor == sub[bere].actor then
							user_var.temp_line, user_var.bere_line=temp, bere
							bere = bere + 1 + do_replace(sub, temp, bere, mode, begin)
						else
							bere = bere + 1
						end
					end
				else
					while bere <= #sub - append_num do
						user_var.temp_line, user_var.bere_line = temp, bere
						bere = bere + 1 + do_replace(sub, temp, bere, mode, begin)
					end
				end
				if #user_var.subcache > 0 and mode.recache then--插入缓存行
					for i=1,#user_var.subcache do
						user_var.subcache[i].effect = "beretag!"..user_var.subcache[i].effect:sub(9)
					end
					if mode.append then
						for i,v in ipairs(user_var.subcache) do
							sub[0]=v
						end
					else
						for i,v in ipairs(user_var.subcache) do
							sub.insert(temp+i,v)
						end
					end
					user_var.subcache={}
				end
			end
		--检索命令行
			if sub[temp].effect:find("^template#code") then
				var_expansion(sub[temp].text, 2, sub)
				if #user_var.subcache > 0 then--插入缓存行
					mode = get_mode(sub[temp].effect)
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
								sub.insert(temp+i,v)
							end
						end
						user_var.subcache={}
					end
				end
			end
		end
		temp=temp+1
	end
end

local function user_code(sub)--运行自定义预处理code行
	for i=find_event(sub),#sub do
		if sub[i].comment and sub[i].effect:find("^template#ppcode$") then
			var_expansion(sub[i].text, 2, sub)
		end
	end
end

local function macro_processing_function(subtitles)--Execute Macro. 执行宏
	user_code(subtitles)
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
	user_code(subtitles)
	do_macro(subtitles)
	uncomment_template_line(subtitles)
end

local function macro_processing_function_initialize(subtitles)--初始化
	initialize(subtitles,find_event(subtitles))
end

local function macro_validation_function()--判断是否可执行
	return true
end

aegisub.register_macro(gt"Tag Replace Apply", gt"Replace all strings with your settings", macro_processing_function, macro_validation_function)
aegisub.register_macro(gt"Tag Replace Apply in selected lines", gt"Replace selected lines' strings with your settings", macro_processing_function_selected, macro_validation_function)
aegisub.register_macro(gt"Tag Replace Initialize", gt"Only do the initialize function", macro_processing_function_initialize)