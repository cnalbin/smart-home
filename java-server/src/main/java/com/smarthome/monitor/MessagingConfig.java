package com.smarthome.monitor;

import org.springframework.amqp.core.Binding;
import org.springframework.amqp.core.BindingBuilder;
import org.springframework.amqp.core.DirectExchange;
import org.springframework.amqp.core.Queue;
import org.springframework.amqp.core.QueueBuilder;
import org.springframework.amqp.core.TopicExchange;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/** 定义传感器消息的独立队列及失败消息队列。 */
@Configuration
public class MessagingConfig {
    /** 业务队列名称。 */
    public static final String QUEUE = "smart_home.sensor.save";
    /** 构造持久业务队列。 @return 业务队列 */
    @Bean Queue sensorQueue() {
        return QueueBuilder.durable(QUEUE).deadLetterExchange("smart_home.sensor.dead")
                .deadLetterRoutingKey("failed").build();
    }
    /** 构造失败交换机。 @return 交换机 */
    @Bean DirectExchange deadExchange() { return new DirectExchange("smart_home.sensor.dead", true, false); }
    /** 构造失败队列。 @return 失败队列 */
    @Bean Queue deadQueue() { return QueueBuilder.durable("smart_home.sensor.dead").build(); }
    /** 绑定失败队列。 @return 绑定 */
    @Bean Binding deadBinding(Queue deadQueue, DirectExchange deadExchange) {
        return BindingBuilder.bind(deadQueue).to(deadExchange).with("failed");
    }
    /** 绑定 RabbitMQ MQTT 默认交换机。 @return 绑定 */
    @Bean Binding sensorBinding(Queue sensorQueue) {
        return BindingBuilder.bind(sensorQueue).to(new TopicExchange("amq.topic", true, false))
                .with("home.livingroom.sensor");
    }
}
