# 传感器数据服务设计

- ESP32 → MQTT home/livingroom/sensor → RabbitMQ amq.topic / home.livingroom.sensor → 持久队列 smart_home.sensor.save → Spring Boot → InfluxDB 2.x。
- 同步写入成功后确认消费，处理失败有限重试后进入 smart_home.sensor.dead。ESP32 目前 QoS 0，断网期间不缓存数据，端到端并非零丢失。
- 新数据写入 smart_home_sensor Bucket 的 environment measurement；device_id 为 tag，温湿度为数值 field。采集时间优先，缺失时用消费处理时间作为点时间。时间内部为绝对时刻，API 和曲线分桶使用 Asia/Shanghai。
- 同设备同毫秒的点合并；查询按时间倒序和毫秒游标分页，库侧限制数量；曲线由 Flux aggregateWindow 计算平均值及采样数。
- 不迁移旧 MySQL 历史数据；新传感器查询只读 InfluxDB。旧 sensor_reading、sensor_migration 表在确认新服务正常并加密备份后删除。后续其他传感器须按数值类型、量纲和设备能力扩展，当前实现范围为温湿度。
- App 通过账号密码登录获得限时 Bearer 会话，经现有 HTTPS 入口访问业务接口；InfluxDB Token 仅在后端持有，不提供给 App。服务重启会使现有会话失效。
- 实时 API 返回最新记录，未直接判断设备在线状态；客户端应结合更新时间提示。服务处理时间在队列积压时会晚于采集时间。
- 未设置数据自动过期；备份、容量监控和失败队列补偿需独立运维。本文记录实现方案，不代替公司要求的正式设计评审。

## MySQL 用户认证

app_user 表保存 id、username、password_hash、is_enabled、gmt_create、gmt_modified；账号采用大小写敏感匹配，uk_username 为完整 64 字符唯一前缀索引。密码摘要采用 BCrypt，不存储明文。库连接和时间字段使用北京时间。

UserRepository 使用绑定参数查询，应用数据库账号仅具有 app_user 的 SELECT 权限；建表和初始化通过受控部署步骤执行，重启不重置账号密码。AuthService 校验账号、密码和启用状态后创建关联用户 ID 的限时随机会话；业务请求检查用户是否仍启用。接口响应、会话格式与 iOS 兼容。

数据库故障不回退到配置账号；密码修改不撤销现有会话，禁用或删除用户则撤销。当前无注册、密码修改、角色分权接口，所有启用用户均可查询现有设备。
