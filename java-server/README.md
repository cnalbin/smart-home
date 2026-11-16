# Java 智能家居后端

Spring Boot、JDK 17、RabbitMQ、InfluxDB 2.x。消费 MQTT 主题 home/livingroom/sensor 的消息，将新采样写入 smart_home_sensor Bucket。旧 MySQL 数据不迁移，也不再用于采样查询。

## 登录与会话

- POST /api/auth/login：JSON `{ "username": "root", "password": "用户输入的密码" }`。成功返回 accessToken、expiresAt。
- 所有业务接口携带 `Authorization: Bearer <accessToken>`，App 自动处理，无需用户配置密钥。
- POST /api/auth/logout：注销当前会话，成功返回 204。
- 账号保存在 MySQL app_user 表，密码只保存 BCrypt 摘要。登录从用户表查询，不再使用 AUTH_USERNAME、AUTH_PASSWORD_HASH 或内置账号兜底。首次部署初始化现有 root 账号，此后重复部署不覆盖密码。
- 登录接口每分钟全局最多 20 次请求；会话最多 1000 个。当前不含注册和用户管理接口，新增账号需受控运维。全部启用账号具有相同的数据查询权限。
- 会话有效期 24 小时，仍保存在服务器内存；服务重启后需重新登录。每次业务请求检查账号启用状态，禁用或删除账号后已有会话失效。修改密码不会自动撤销已发出的会话。
- 数据库不可用时不允许使用默认凭据绕过登录。旧的 API_TOKEN 不再提供接口访问权限。

## Knife4j 接口文档

浏览器打开 /doc.html，OpenAPI 结构为 /v3/api-docs。先调用登录接口，再在授权区域填入 accessToken，即可调试受保护的温湿度查询和注销接口。文档 UI 可直接查看。Knife4j 增强定制器因 Springdoc 版本兼容未启用，Knife4j UI 正常使用。

## 查询

- GET /api/devices/{deviceId}/readings/latest
- GET /api/devices/{deviceId}/readings?from=...&to=...&limit=100&beforeId=...
- GET /api/devices/{deviceId}/readings/chart?from=...&to=...&bucketSeconds=3600

时间范围为左闭右开，参数使用带时区 ISO 8601 时间。列表最多 500 条，使用 nextBeforeId 翻页。曲线桶支持 60、3600、86400 秒，最多约 2000 个桶、366 天。按采集时间筛选，缺失时使用服务接收时间。

## InfluxDB 数据模型

- Bucket：smart_home_sensor；measurement：environment；tag：device_id。
- 数值 field：temperature、humidity；元数据 field：measured_at、received_at、time_source。
- 点时间使用可信的设备采集时刻；未校时、采集时间为空时使用服务处理时刻。服务处理时间不等于 RabbitMQ 收到消息的时间。
- InfluxDB 按绝对时刻存储，原始时间使用 UTC 表示；API 返回北京时间（+08:00），日聚合以北京时间零点为边界。不能再额外加 8 小时写入，否则会产生偏移。
- 列表 id 与 nextBeforeId 使用点时间的 Unix 毫秒值，仅作为数字游标，客户端不应依赖旧 MySQL 自增 ID。
- 相同 measurement、device_id 和毫秒时间的消息会更新同一个点；缺少采集时间时，重投可能以新的服务时间写入另一点。
- NAS 当前 Bucket 未设置到期自动删除；长期保留需另行定期备份和验证恢复。

## 部署

执行 `mvn clean package` 后按 Dockerfile 构建，运行 JRE 17 镜像。必需环境变量：

| 变量 | 含义 |
| --- | --- |
| INFLUX_URL | InfluxDB 地址，例如 http://10.10.10.17:8086 |
| INFLUX_ORG_ID | Bucket 所属组织 ID |
| INFLUX_BUCKET | 默认 smart_home_sensor |
| INFLUX_TOKEN | 仅服务端使用的 Bucket 读写 Token |
| DB_URL | MySQL JDBC 地址，配置 connectionTimeZone=Asia/Shanghai |
| DB_USER、DB_PASSWORD | 对 app_user 仅有 SELECT 权限的应用账号 |
| RABBIT_HOST | RabbitMQ 地址 |
| RABBIT_USER、RABBIT_PASSWORD | 消费账号 |

可选 RABBIT_PORT（5672）、RABBIT_VHOST（/）。Token 和密码通过受保护的配置注入，不提交仓库，不写入 App。数据库 Token 不代替 App 的账号登录。

NAS 容器名 smart-home-sensor，监听局域网 10.10.10.17:8080，外网经现有 HTTPS 域名访问。NAS 运行配置加密保存于受保护的服务目录。schema.sql 仅定义当前 app_user 用户表；部署时由有建表权限的运维账号执行，不允许应用使用 MySQL root。连接池会设置会话为北京时间，创建和修改时间使用 DATETIME(3)。部署已移除旧 sensor_reading、sensor_migration 表，清理前在 NAS 受保护的服务目录中保存加密备份。

队列 smart_home.sensor.save 独立于测试队列。同步写入 InfluxDB 成功后才确认消费，有限重试后进入失败队列 smart_home.sensor.dead。ESP32 目前 QoS 0 且无断网缓存，仍可能缺失数据。需要定期检查失败队列并备份 InfluxDB；没有实施自动补传或自动备份。
