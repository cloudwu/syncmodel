# syncmodel
一个根据时间戳同步的模型

http://blog.codingnow.com/2016/10/synchronization.html

使用应遵循以下规则：

所有客户端的时间戳按一致的规则加上偏移量，保证每条事件都有唯一的时间，即用时间戳可以唯一表示一个 command 。

对于 Server ，使用 model:apply_command(ti, func) 应用 Client 上传的指令。如果返回 false, error 则执行失败（或回滚队列太长），应该通知该客户端删除。

Server side 可以用 model:current_state 查询当前最新的状态和时间。

对于 Client ，使用 model:queue_command(ti, func) 将自身操作的指令或 Server 下发的指令排入队列，如果返回 false 表示插入无效，此刻应和 Server 做一次状态同步。

Client 应使用 model:snapshot(ti) 获取某个时间点的状态快照；snapshot 传入的时间戳不能比之前的小。如果返回 nil ，表示状态暂不可用，应当等待 Server 后续指令或重新做同步。

当 Server 命令 Client 删除某时刻的指令时，Client 应调用 model:remove_command(ti) 删。通常可以再删除后再次用 snapshot 获取快照。
