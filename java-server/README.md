# Java 温湿度服务

JDK 17、Spring Boot、Spring AMQP、MySQL。设备 MQTT 主题 home/livingroom/sensor 通过 RabbitMQ 默认 amq.topic 映射到 AMQP 路由键 home.livingroom.sensor。服务使用独立持久队列 smart_home.sensor.save 和失败队列 smart_home.sensor.dead。

## 接口

接口需要请求头 `Authorization: Bearer <API_TOKEN>`。当前服务监听 NAS 局域网地址 10.10.10.17:8080，供用户调试；HTTP 不加密认证信息，切勿映射到公网。App 外网访问仍需有效证书的 HTTPS 反向代理。

- GET /api/devices/{deviceId}/readings/latest：最新记录。
- GET /api/devices/{deviceId}/readings?from=...&to=...&limit=100&beforeId=...：历史列表。from 含、to 不含，均为 ISO 8601 带时区的时间；limit 最大 500，下一页使用响应的 nextBeforeId，0 表示没有下一页。按 ID 降序。
- GET /api/devices/{deviceId}/readings/chart?from=...&to=...&bucketSeconds=3600：按北京时间桶聚合平均温度和湿度。bucketSeconds 为 60、3600、86400；最多约 2000 个桶，最多查询 366 天。

时间字段使用带 +08:00 的北京时间 ISO 8601；measuredAt 是设备采集时间（设备未校时可能为 null），receivedAt 是 Java 消费处理时间。历史和曲线按采集时间筛选，采集时间缺失时使用接收时间。ID 用于分页，断网补传时代码仍按入库顺序排列。设备时钟不正确会影响曲线位置。曲线目前仅提供平均值和数据点数。

## 运行和部署

编译 `mvn clean package`；镜像使用 Dockerfile、JDK 17。先由数据库管理员执行 schema.sql 并提供独立数据库账号，服务账号只需 SELECT、INSERT；设置 DB_URL、DB_USER、DB_PASSWORD、RABBIT_HOST、RABBIT_USER、RABBIT_PASSWORD、API_TOKEN，API_TOKEN 至少 32 字符。敏感值通过受保护的密钥机制注入，不提交仓库。数据库 DATETIME 按北京时间读写；Java 进程时区为 Asia/Shanghai。

NAS 当前部署：容器 smart-home-sensor，host 网络，重启策略 unless-stopped；监听 10.10.10.17:8080（局域网明文调试）。service.env 加密保存在 /root/smart-home-sensor/service.env.enc，密钥保存在 /root/smart-home-sensor/key，均仅 root 可读；解密密钥和密文在同一主机，不能防止主机管理员或 Docker 管理员访问。运行时密钥也能被具备 Docker 管理权限的人员读取。查看日志：`docker logs --tail 100 smart-home-sensor`。需要重建容器时，需以管理员身份将解密后的环境传递给 docker，避免将明文写入项目或公开。

NAS 上如需自行查看 API 密钥，可通过有管理员权限的终端执行：
`sudo sh -c 'openssl enc -d -aes-256-cbc -pbkdf2 -pass file:/root/smart-home-sensor/key -in /root/smart-home-sensor/service.env.enc | sed -n "s/^API_TOKEN=//p"'`
不要将输出截图、提交仓库或发送到群聊。

当前 ESP32 为 QoS 0，断网期间不缓存，消息有可能丢失；未带消息唯一编号，消费重投时可能重复。持久队列不保证 QoS 0 发布消息在 RabbitMQ 重启时不丢失。请定期备份 MySQL 并验证恢复。数据库与队列都应使用最小权限账号；当前部署暂时使用现有 RabbitMQ 账号，建议后续更换为专用账号。既有 iOS 原型使用另一套 Python API，需要单独适配本 Java API。

## 账号登录（替换静态密钥）

POST /api/auth/login，JSON 字段 username、password；成功返回 accessToken、expiresAt。将 accessToken 作为 Bearer 令牌请求业务接口。POST /api/auth/logout 可立即注销当前会话。令牌为安全随机数，服务器内存保存会话，24 小时到期，重启后全部失效。默认账号 root，默认密码通过 BCrypt 摘要配置；环境变量 AUTH_USERNAME、AUTH_PASSWORD_HASH 可覆盖默认设置。每分钟全局最多 20 次登录尝试。旧 API_TOKEN 不再具有接口访问权限。

Knife4j 文档位于 /doc.html，OpenAPI JSON 位于 /v3/api-docs。先调用登录接口，再将返回的令牌填入文档授权区域即可调试查询、注销接口。文档采用 Knife4j UI + Springdoc；因 Spring Boot 3.5 兼容性，未启用 Knife4j 额外增强自定义器。接口服务器地址使用当前访问域名。
