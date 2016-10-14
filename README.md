# syncmodel
一个根据时间戳同步的模型

http://blog.codingnow.com/2016/10/synchronization.html

使用应遵循以下规则：

1. model:command 只能修改传入的对象的数据，不得调用会影响其它数据有副作用的函数。

2. 所有客户端的时间戳按一致的规则加上偏移量，保证每条事件都有唯一的时间，即用时间戳可以唯一表示一个 command 。

3. 服务器收到客户端的 command 后，如果超过时间窗口，命令该客户端删除 (model:remove) 这个 command 。

4. 服务器收到时间窗口内的 command ，加入自己的 model (model:command) ，并转发给所有客户端。

5. 服务器和客户端都按时间心跳推进( model:advance ) model 。

6. 在推进 model 后，服务器若发现 error ( 使用 model:error 遍历) ，删除 error 的 command 并通知所有客户端删除。

7. 客户端推进 model 后，如果 error ，不直接删除；保留一段时间；如果在这段时间内，未收到服务器发送来的删除指令，重新和服务器同步状态。

8. 客户端登录后，由服务器把 model 的全部状态 (model:state) 同步给他。
