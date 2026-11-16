# 智能家居温湿度监测

当前链路：ESP32 DHT11 → RabbitMQ MQTT → Spring Boot → InfluxDB 2.x → iOS App。支持最新温湿度、历史分页和分钟／小时／天聚合曲线。接口时间与曲线日边界采用北京时间。

- `device/esp32-mqtt/`：当前 ESP32 程序及上传步骤。配置 Wi-Fi 和 MQTT 凭据后通过 Thonny 保存至设备，GPIO 17 连接 DHT11，采样间隔由配置决定；断网不缓存补传。
- `java-server/`：当前 Java 后端、Dockerfile、登录与业务接口、Knife4j 文档。部署与 InfluxDB 配置见该目录 README.md。新数据写入 smart_home_sensor Bucket，旧 MySQL 数据不迁移。
- `ios/`：SwiftUI App。通过账号密码登录，不需要单独配置数据库 Token。连接现有 HTTPS 服务查看数据，支持可选记住密码。
- `.github/workflows/ios.yml`：GitHub Actions 构建未签名 IPA。下载产物后自行签名安装，仓库不保存签名证书。

NAS 当前服务为 smart-home-sensor 容器，局域网访问 10.10.10.17:8080，外网经 HTTPS 入口转发；接口文档为 /doc.html。业务请求需登录获得 Bearer 会话，后端重启后需重新登录。

根目录 compose.yml、server/ 和 device/main.py 属于早期 HTTP/SQLite 原型，不用于当前 MQTT/Java/InfluxDB 部署。不要用旧 compose 覆盖正在运行的服务。

请勿提交本地 Wi-Fi 密码、MQTT 凭据、InfluxDB Token 或运行环境配置。长期保留需备份数据库并验证恢复，当前未实现自动备份和设备离线补传。
