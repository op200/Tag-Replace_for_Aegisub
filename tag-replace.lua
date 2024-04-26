local gt=aegisub.gettext

script_name = gt"Tag Replace"
script_description = gt"Replace string such as tag"
script_author = "op200"
script_version = "0.1.4"

local user_var={--自定义变量键值表
	kdur={0,0},--存储方式为前缀和，从[2]开始计数，方便相对值计算
	begin,
	temp_line,
	bere_line
}

function get_temp_class(effect)--return table
	local class={}
	for world in effect:match("@(.*)#"):gmatch("[^;]+") do
		table.insert(class,world)
	end
	return class
end

function get_bere_class(effect)--return table
	local classstring = effect:match("[@!]([^#]*)$")
	if not classstring then return {} end
	local class={}
	for world in classstring:gmatch("[^;]+") do
		table.insert(class,world)
	end
	return class
end

function get_mode(effect)--return int
	local modestring = effect:match("#(.*)$")
	if modestring:len()==0 then
		return 0
	elseif modestring:len()==1 then
		return tonumber(modestring)
	end

	local mode=0
	for world in modestring:gmatch("[^;]+") do--判断mode，返回对应int值
		if world=="rmtag" and mode%10<1 then mode=1
		elseif world=="rmalltag" and mode%10<2 then mode=2
		end
	end
	return mode
end

function initialize(sub,begin)
	local findline=begin
	while findline<=#sub do
		if sub[findline].effect:find("^beretag!") and not sub[findline].comment then--删除beretag!行
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

function var_expansion(text, re_num, sub)--input文本和replace次数，通过re_num映射karaok变量至变量表
	--扩展变量
	while true do
		local pos1, pos2 = text:find("%$%w+")
		if not pos1 then break end
		local var = text:sub(pos1+1,pos2)
		if not (var=="") then
			if var=="kdur" then
				text = text:sub(1,pos1-1)..(user_var.kdur[re_num]-user_var.kdur[re_num-1])..text:sub(pos2+1)
			elseif var=="start" then
				text = text:sub(1,pos1-1)..(user_var.kdur[re_num-1]*10)..text:sub(pos2+1)
			elseif var=="end" then
				text = text:sub(1,pos1-1)..(user_var.kdur[re_num]*10)..text:sub(pos2+1)
			elseif var=="mid" then
				text = text:sub(1,pos1-1)..math.floor((user_var.kdur[re_num-1] + user_var.kdur[re_num]) * 5)..text:sub(pos2+1)
			else
				text = text:sub(1,pos1-1).."user_var."..var..text:sub(pos2+1)
			end
		end
	end
	--扩展表达式
	while true do
		local pos1, pos2 = text:find("!.-!")
		if not pos1 then break end
		local expression = text:sub(pos1+1,pos2-1)
		if not (expression=="") then
			local return_str = loadstring("return function(sub,user_var) "..expression.." end")()(sub,user_var)
			if not return_str then return_str="" end
			text = text:sub(1,pos1-1)..return_str..text:sub(pos2+1)
		end
	end

	return text
end

function do_replace(sub, temp, bere, class, mode, begin)--return int
	if sub[bere].comment or not sub[bere].effect:find("^beretag") then return 0 end--若该行被注释或为非beretag行，则跳过
--判断该行class是否与模板行class有交集
    local re,line_class=false,get_bere_class(sub[bere].effect)
    for i=1,#line_class do
        for p=1,#class do
            if line_class[i]==class[p] then
                re=true
                goto start
            end
        end
    end
    ::start::
    if not re then return 0 end
--准备replace
	local insert_line=sub[bere]
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
	local temp_tag, temp_re_tag, temp_add_text = sub[temp].text:match("^{(.-)}"), sub[temp].text:match("^{.-}{(.-)}"), sub[temp].text:match("^{.-}{.-}(.*)")
    if mode%10==0 then--根据mode判断替换方式以修改insert_line
		--循环找到insert_line里所有的temp_tag
		if temp_tag=="" then--考虑到{}的情况
			temp_tag="none"
			insert_line.text = insert_line.text:gsub("}","none}")
		end
		local user_var=user_var--修改变量键值表
		local find_pos, re_num=1, 2--re_num从2开始计数
		while true do
			local pos1, pos2 = insert_line.text:find(temp_tag,find_pos)--记录找到的temp_tag位置
			if not pos1 then break end
			--先在}后插入temp_add_text，再替换temp_tag为temp_re_tag
			local pos3 = insert_line.text:find("}",pos2+1)--记录temp_tag后的}的位置

			local new_temp_add_text=var_expansion(temp_add_text,re_num,sub)
			insert_line.text = insert_line.text:sub(1,pos3)..new_temp_add_text..insert_line.text:sub(pos3+1)--插入new_temp_add_text
			pos3 = pos3 + new_temp_add_text:len() - insert_line.text:len()--因为temp_tag含有正则表达式，无法直接获取长度，所以pos3先减原长，循环结束时再加新长

			local new_temp_re_tag=var_expansion(temp_re_tag,re_num,sub)
			insert_line.text = insert_line.text:sub(1,pos1-1)..new_temp_re_tag..insert_line.text:sub(pos2+1)--插入new_temp_re_tag
			find_pos, re_num = pos3 + insert_line.text:len() + 1, re_num+1
		end
    elseif mode%10==1 then

    elseif mode%10==2 then

    end

--判断该行类型，第一次替换则注释该行，多次替换则删除该行
	if sub[bere].effect:find("^beretag!") then--删除行
		--这里插入和删除的顺序不能更改，否则会导致逆天bug
		sub.insert(bere+1,insert_line)
		sub.delete(bere)
		return 0
	end
--注释行，并在effect头部加上:
	local tocmt=sub[bere]
	tocmt.comment=true
	tocmt.effect=":"..tocmt.effect
	sub[bere]=tocmt
--将@改为!
	insert_line.effect="beretag!"..insert_line.effect:sub(9)
	sub.insert(bere+1,insert_line)
	return 1
end

function find_event(sub)
    for i=1,#sub do--Find dialogue lines to reduce if judgments. 找到对话行以减少if判断
        if sub[i].section=="[Events]" then
            return i
        end
    end
end

function do_macro(sub)
    local begin=find_event(sub)
	local temp=begin
	user_var.begin=begin
	initialize(sub,begin)--初始化，删除所有beretag!行，并还原:beretag@行
    while temp<=#sub do--Find template lines. 检索模板行
		-- if temp>#sub then break end--debug用
        if sub[temp].comment and sub[temp].effect:find("^template@[%w,]-#[%w,]*$") then
            local class,mode=get_temp_class(sub[temp].effect),get_mode(sub[temp].effect)
			local bere=begin
            while bere<=#sub do
				if mode%10==0 then--根据mode判断是否替换
					user_var.temp_line, user_var.bere_line=temp, bere
					local skip = do_replace(sub, temp, bere, class, mode, begin)
					bere = bere + skip + 1
				elseif mode%10==1 then
			
				elseif mode%10==2 then
			
				end
            end
        end
		temp=temp+1
    end
end

function user_code(sub)--运行自定义预处理code行
	for i=find_event(sub),#sub do
		if sub[i].comment and sub[i].effect:find("^template#ppcode$") then
			var_expansion(sub[i].text, 2, sub)
		end
	end
end

function user_require(sub)--自定义文件引用
	for i=find_event(sub),#sub do
		if sub[i].comment and sub[i].effect:find("^retag@require$") then
			for filename in sub[i].text:gmatch("[^;]+") do
				require(filename)
			end
		end
	end
end

function macro_processing_function(subtitles,selected_lines)--Execute Macro. 执行宏
	user_require(subtitles)
	user_code(subtitles)
    do_macro(subtitles)
end

function macro_processing_function_selected(subtitles,selected_lines)--Execute Macro in selected lines. 在所选行执行宏
    -- do_macro(selected_lines)
end

function macro_processing_function_initialize(subtitles)--初始化
    initialize(subtitles,find_event(subtitles))
end

function macro_validation_function()--判断是否可执行
    return true
end

aegisub.register_macro(gt"Tag Replace Apply", gt"Replace all strings with your settings", macro_processing_function, macro_validation_function)
-- aegisub.register_macro(gt"Tag Replace Apply in selected lines", gt"Replace selected lines' strings with your settings", macro_processing_function_selected, macro_validation_function)
aegisub.register_macro(gt"Tag Replace Initialize", gt"Only do the initialize function", macro_processing_function_initialize)