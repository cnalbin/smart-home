package com.smarthome.monitor;

import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.nio.charset.StandardCharsets;
import java.time.LocalDateTime;
import org.junit.jupiter.api.Test;
import org.springframework.amqp.AmqpRejectAndDontRequeueException;
import org.springframework.jdbc.core.JdbcTemplate;

/** 验证消息校验及保存边界。 */
class SensorConsumerTest {
    @Test
    void receive_validMessage_saves() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        SensorConsumer consumer = new SensorConsumer(jdbc, new ObjectMapper());
        consumer.receive(("{\"device_id\":\"esp32-livingroom\",\"temperature\":20,\"humidity\":74,"
                + "\"measured_at\":\"2026-11-13T10:00:00+08:00\"}").getBytes(StandardCharsets.UTF_8));
        verify(jdbc).update(anyString(), any(), any(), any(), eq(LocalDateTime.of(2026, 11, 13, 10, 0)),
                any(), eq(LocalDateTime.of(2026, 11, 13, 10, 0)), any(), any());
    }
    @Test
    void receive_invalidHumidity_rejects() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        SensorConsumer consumer = new SensorConsumer(jdbc, new ObjectMapper());
        byte[] data = "{\"device_id\":\"device\",\"temperature\":20,\"humidity\":101}"
                .getBytes(StandardCharsets.UTF_8);
        assertThrows(AmqpRejectAndDontRequeueException.class, () -> consumer.receive(data));
        verifyNoInteractions(jdbc);
    }
}
