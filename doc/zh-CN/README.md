# 入门

### Aegisub 自动载入脚本

#### 安装版
将lua文件放到`C:\Program Files\Aegisub\automation\autoload`中

如果 Aegisub 安装在非默认位置，则同便携版

#### 便携版
将lua文件放到`.\automation\autoload`中

### 使用

先写一个简单的案例：

将一行字幕注释掉，然后在特效(Effect)栏写上 `template@1#`，文本(Text)栏写上 `{tag1}{tag2}`  
再新建一行字幕，在特效(Effect)栏写上 `beretag@1#`，文本(Text)栏写上 `{tag1}12345`  
执行脚本

![图片](https://github.com/user-attachments/assets/2e59cdbc-ba6d-41a4-8066-0d4416503dae)

![图片](https://github.com/user-attachments/assets/61feba4d-5594-4cd1-bb7c-bff3a060fdab)

执行后，第二行被注释掉了，新出现了第三行，且第三行的 `tag1` 被替换成了 `tag2`  
这就是 `Tag Replace` 最底层的功能——替换标签

执行脚本的清理功能，字幕还原成了原本的样子  
这就是 `Tag Replace` 的核心思想——随时重载+完全可逆


# 模式

我们将特效栏为 `template` 开头的行简称为 `模板行` 或 `temp行`；`beretag` 开头的行简称为 `替换行` 或 `bere行`

通过入门案例的演示，大家应该能发现示例中的共同点——`@1`。这是 `Tag Replace` 语法的一部分，`@` 后可以跟随类(class)名，当temp行与bere行的类名存在交集的时候，该temp行就会在该bere行上执行。  
例如入门案例中的 `{tag1}{tag2}`，就是将bere行中标签中(`{}`括起来的部分)的 `tag1` 替换为 `tag2`

temp行的 `#` 后跟的是模式名，具体有以下模式：
```
<空>:
    默认模式
onlyfind:
    不执行替换
cuttag:
    将每次替换后的内容添加到新行，以被替换的{}位置作为切割点
strictstyle:
    严格匹配样式名(Style)，仅对同样式名的行执行替换
strictactor:
    严格匹配说话人(Name)，仅对同说话人的行执行替换
strictclass:
    严格匹配class，必须所有class一致才会执行
findtext:
    将匹配整行文本，而不是仅匹配标签
append:
    新的行将被append到所有字幕行的末尾，而不是bere行的后面
keyframe:
    将先执行关键帧替换，对应关键帧文本为 $keytext，蒙蔽为 $keyclip
recache:
    将缓存行($subcache)插入到字幕
uninsert:
    将不会插入新的bere行
cuttime:
    {<start_tag>}{<end_tag>}
    bere行在时域上从start_tag渐变到end_tag
classmix:
    {<class>[;<class>...]}{<class>[;<class>...]}[{<class>[;<class>...]}]
    合并两种类的行，第三个{}中是新的class
```

例如可以通过 `findtext` 模式和正则表达式，把 `中文|英文` 的行分割成双语字幕，并附带漏译检测($debug 函数中的形参就是检测到漏译后输出的文本)
```
Comment: 0,0:00:00.00,0:00:00.00,zh,,0,1240,0,template@dialog#onlyfind,!local line=sub[$bere_line] if not line.text:find("|") then $debug("") end table.insert($subcache,$deepCopy(line)) if line.style=="zh" then line.style="en" else if line.style=="zh-top" then line.style="en-top" else $debug("dialog error: "..line.text) end end line.layer=1 table.insert($subcache,line)!
Comment: 0,0:00:00.00,0:00:00.00,zh,,0,1240,0,template@dialog#recache;uninsert;append,{}{}
Comment: 0,0:00:00.00,0:00:00.00,zh,,0,1240,0,template@dialog#findtext;strictstyle,{|.*}
Comment: 0,0:00:00.00,0:00:00.00,en,,0,1240,0,template@dialog#findtext;strictstyle,{.*|}
Comment: 0,0:00:00.00,0:00:00.00,zh-top,,0,1240,0,template@dialog#findtext;strictstyle,{|.*}
Comment: 0,0:00:00.00,0:00:00.00,en-top,,0,1240,0,template@dialog#findtext;strictstyle,{.*|}
Dialogue: 0,0:00:00.00,0:00:05.00,zh,,0,0,0,beretag@dialog,一二三|one two three
Dialogue: 0,0:00:00.00,0:00:05.00,zh-top,,0,0,0,beretag@dialog,编辑字幕|Edit ASS
```
![图片](https://github.com/user-attachments/assets/9dfe5789-06e7-4c2e-8671-0682350081cb)


# 内置变量与关键字

Tag Replace 存在一些内置变量，用于方便用户操作

Tag Replace 的操作规范中，局部变量同 lua 语法，全局变量使用 `$` 或 `user_var.` 作为开头，例如 `$number1`，本质上是 `$` 会被自动替换为 `user_var`

关键字是会被直接替换的，它长得和全局变量一样，但不能真正调用到对应的变量，因为它会最优先被替换为对应值

* sub / $sub  
  `sub` 是使用规范中唯一允许用户调用的真正的全局变量，其与 `$sub` 一样，都是 Aegisub API 的 subtitle 对象
* $this
  当前 bere 行的 karaskel 处理后的只读副本，用于方便访问bere行的属性
  同时允许 `$` 直接访问 `$this` 的属性，例如 `$start_time` `$top`
* $kdur / user_var.kdur={0,0}  
  这是 `\k` 标签后跟的值，可以在替换 karaok 标签时使用  
  注意这是个关键字，如果需要调用其对应的变量，不能使用 `$`
* $begin=find_event(sub)  
  [Events]类型行的第一行，也是 Aegisub 字幕行的第一行对应的 index 号
* $temp_line 当前所读取的template行的键  
  调用对应行可以用 `sub[$temp_line]`
* $bere_line 当前所读取的beretag行的键  
  调用对应行可以用 `sub[$bere_line]`
* $bere_text 当前被替换的文本


# 内置函数

Tag Replace 存在一些内置函数，用于调用特殊功能和更改模式处理

Tag Replace 的操作规范中，局部变量同 lua 语法，全局变量使用 `$` 或 `user_var.` 作为开头，例如 `$number1`，本质上是 `$` 会被自动替换为 `user_var.`
