package com.smarthome.monitor;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.util.regex.Pattern;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.amqp.AmqpRejectAndDontRequeueException;

import org.springframework.stereotype.Component;


/** 接收并保存温湿度消息。 */
@Component
public class SensorConsumer {
    private static final Pattern DEVICE = Pattern.compile("[A-Za-z0-9_-]{1,64}");
    private final SensorRepository repository;
    private final ObjectMapper mapper;
    /** 创建消费者。 @param repository 时序数据访问器 @param mapper JSON 解析器 */
    public SensorConsumer(SensorRepository repository, ObjectMapper mapper) {
        this.repository = repository;
        this.mapper = mapper;
    }

    /** 校验并保存消息，写入成功后由容器确认。 @param body MQTT 消息正文 */
    @RabbitListener(queues = MessagingConfig.QUEUE)
    public void receive(byte[] body) {
        try {
            if (body.length > 2048) { throw new IllegalArgumentException("message too large"); }
            JsonNode node = mapper.readTree(body);
            if (node == null || !node.isObject() || !node.path("device_id").isTextual()
                    || !DEVICE.matcher(node.path("device_id").asText()).matches()
                    || !node.path("temperature").isNumber() || !node.path("humidity").isNumber()) {
                throw new IllegalArgumentException("invalid fields");
            }
            BigDecimal temperature = node.get("temperature").decimalValue();
            BigDecimal humidity = node.get("humidity").decimalValue();
            if (temperature.compareTo(BigDecimal.valueOf(-40)) < 0 || temperature.compareTo(BigDecimal.valueOf(80)) > 0
                    || humidity.compareTo(BigDecimal.ZERO) < 0 || humidity.compareTo(BigDecimal.valueOf(100)) > 0
                    || temperature.scale() > 2 || humidity.scale() > 2) {
                throw new IllegalArgumentException("invalid measurement");
            }
            Instant measured = null;
            JsonNode time = node.get("measured_at");
            if (time != null && !time.isNull()) {
                if (!time.isTextual()) { throw new IllegalArgumentException("invalid measurement time"); }
                measured = OffsetDateTime.parse(time.asText()).toInstant();
            }
            repository.save(node.get("device_id").asText(), temperature, humidity, measured, Instant.now());
        } catch (java.io.IOException | IllegalArgumentException ex) {
            throw new AmqpRejectAndDontRequeueException("Invalid sensor message", ex);
        }
    }
}
