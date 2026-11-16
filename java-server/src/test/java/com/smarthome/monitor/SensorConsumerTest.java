package com.smarthome.monitor;

import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.nio.charset.StandardCharsets;
import org.junit.jupiter.api.Test;
import org.springframework.amqp.AmqpRejectAndDontRequeueException;
import java.time.Instant;

/** 验证消息校验及保存边界。 */
class SensorConsumerTest {
    @Test
    void receive_validMessage_saves() {
        SensorRepository repository = mock(SensorRepository.class);
        SensorConsumer consumer = new SensorConsumer(repository, new ObjectMapper());
        consumer.receive(("{\"device_id\":\"esp32-livingroom\",\"temperature\":20,\"humidity\":74,"
                + "\"measured_at\":\"2026-11-13T10:00:00+08:00\"}").getBytes(StandardCharsets.UTF_8));
        verify(repository).save(eq("esp32-livingroom"), any(), any(),
                eq(Instant.parse("2026-11-13T02:00:00Z")), any());
    }
    @Test
    void receive_invalidHumidity_rejects() {
        SensorRepository repository = mock(SensorRepository.class);
        SensorConsumer consumer = new SensorConsumer(repository, new ObjectMapper());
        byte[] data = "{\"device_id\":\"device\",\"temperature\":20,\"humidity\":101}"
                .getBytes(StandardCharsets.UTF_8);
        assertThrows(AmqpRejectAndDontRequeueException.class, () -> consumer.receive(data));
        verifyNoInteractions(repository);
    }
}
