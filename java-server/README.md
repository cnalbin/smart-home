# Java 智能家居后端

Spring Boot、JDK 17、RabbitMQ、MySQL。消费 MQTT 主题 home/livingroom/sensor 的消息并保存温湿度，按北京时间存储、查询和绘图。

## 登录与会话

- POST /api/auth/login：JSON `{ "username": "root", "password": "用户输入的密码" }`。成功返回 accessToken、expiresAt。
- 所有业务接口携带 `Authorization: Bearer <accessToken>`，App 自动处理，无需用户配置密钥。
- POST /api/auth/logout：注销当前会话，成功返回 204。
- 会话有效期 24 小时，保存在服务器内存；服务重启后需重新登录。密码以 BCrypt 摘要配置，可用 AUTH_USERNAME、AUTH_PASSWORD_HASH 环境变量覆盖默认账号配置。密码不写入 App，也不在日志中输出。
- 登录接口每分钟全局最多 20 次请求；会话最多 1000 个。当前仅提供一个管理员账号，不含用户管理。
- 旧的 API_TOKEN 已不再提供接口访问权限。

## Knife4j 接口文档

浏览器打开 /doc.html，OpenAPI 结构为 /v3/api-docs。先调用登录接口，再在授权区域填入 accessToken，即可调试受保护的温湿度查询和注销接口。文档 UI 可直接查看。Knife4j 增强定制器因 Springdoc 版本兼容未启用，Knife4j UI 正常使用。

## 查询

- GET /api/devices/{deviceId}/readings/latest
- GET /api/devices/{deviceId}/readings?from=...&to=...&limit=100&beforeId=...
- GET /api/devices/{deviceId}/readings/chart?from=...&to=...&bucketSeconds=3600

时间范围为左闭右开，参数使用带时区 ISO 8601 时间。列表最多 500 条，使用 nextBeforeId 翻页。曲线桶支持 60、3600、86400 秒，最多约 2000 个桶、366 天。按采集时间筛选，缺失时使用服务接收时间。

## 部署

`mvn clean package` 后构建 Dockerfile。配置 DB_URL、DB_USER、DB_PASSWORD、RABBIT_HOST、RABBIT_USER、RABBIT_PASSWORD；敏感值通过受保护的配置注入。NAS 容器名 smart-home-sensor，监听局域网 10.10.10.17:8080，外网经现有 HTTPS 域名访问。密码登录及会话令牌应通过 HTTPS 传输。现有数据库 smart_home_sensor，无需迁移历史采集表。

队列 smart_home.sensor.save 独立于测试队列。有限重试后进入失败队列 smart_home.sensor.dead。ESP32 目前 QoS 0 且无断网缓存，仍可能缺失数据；消息没有唯一编号，重投可能重复。应定期备份 MySQL 并验证恢复。
