## 入门

先写一个简单的案例：

将一行字幕注释掉，然后在特效(Effect)栏写上 `template@1#`，文本(Text)栏写上{tag1}{tag2}  
再新建一行字幕，在特效(Effect)栏写上 `beretag@1#`，文本(Text)栏写上{tag1}12345  
执行脚本

![图片](https://github.com/user-attachments/assets/2e59cdbc-ba6d-41a4-8066-0d4416503dae)

![图片](https://github.com/user-attachments/assets/61feba4d-5594-4cd1-bb7c-bff3a060fdab)

执行后，第二行被注释掉了，新出现了第三行，且第三行的 `tag1` 被替换成了 `tag2`  
这就是 `Tag Replace` 最底层的功能——替换标签

执行脚本的清理功能，字幕还原成了原本的样子  
这就是 `Tag Replace` 的核心思想——随时重载+完全可逆


## 模式

我们将特效栏为 `template` 开头的行简称为 `模板行` 或 `temp行`；`beretag` 开头的行简称为 `替换行` 或 `bere行`

通过入门案例的演示，大家应该能发现示例中的共同点——`@1`。这是 `Tag Replace` 语法的一部分，`@` 后可以跟随类(class)名，当temp行与bere行的类名存在交集的时候，该temp行就会在该bere行上执行。  
例如入门案例中的 `{tag1}{tag2}`，就是将bere行中标签中(`{}`括起来的部分)的 `tag1` 替换为 `tag2`
