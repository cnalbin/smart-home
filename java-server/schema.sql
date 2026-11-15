CREATE TABLE IF NOT EXISTS sensor_reading (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '主键',
    device_id VARCHAR(64) NOT NULL COMMENT '设备编号',
    temperature DECIMAL(6,2) NOT NULL COMMENT '温度，摄氏度',
    humidity DECIMAL(5,2) UNSIGNED NOT NULL COMMENT '相对湿度，百分比',
    measured_at DATETIME(3) NULL COMMENT '设备采集时间，北京时间',
    received_at DATETIME(3) NOT NULL COMMENT '服务接收时间，北京时间',
    observed_at DATETIME(3) NOT NULL COMMENT '曲线时间，优先采集时间，缺失时使用接收时间，北京时间',
    gmt_create DATETIME(3) NOT NULL COMMENT '创建时间，北京时间',
    gmt_modified DATETIME(3) NOT NULL COMMENT '修改时间，北京时间',
    PRIMARY KEY (id),
    KEY idx_device_id_observed_at (device_id(32), observed_at, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='传感器采集记录';
