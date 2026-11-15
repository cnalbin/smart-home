package com.smarthome.monitor;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/** 智能家居传感器服务入口。 */
@SpringBootApplication
public class SensorApplication {
    /** 启动传感器服务。
     * @param args 启动参数
     */
    public static void main(String[] args) {
        SpringApplication.run(SensorApplication.class, args);
    }
}
