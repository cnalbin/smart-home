package com.smarthome.monitor;

import com.influxdb.client.InfluxDBClient;
import com.influxdb.client.InfluxDBClientFactory;
import com.influxdb.client.domain.WritePrecision;
import com.influxdb.client.write.Point;
import com.influxdb.query.FluxRecord;
import jakarta.annotation.PreDestroy;
import java.math.BigDecimal;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Repository;

/** 保存和查询 InfluxDB 2.x 温湿度时间序列。 */
@Repository
public class SensorRepository {
    /** 时间展示使用北京时间。 */
    private static final ZoneId BEIJING = ZoneId.of("Asia/Shanghai");
    /** 同时供读写复用的线程安全客户端。 */
    private final InfluxDBClient client;
    /** Bucket 的组织 ID。 */
    private final String org;
    /** 传感器 Bucket。 */
    private final String bucket;

    /** 创建数据库客户端。 @param url 服务地址 @param token 读写令牌
     * @param org 组织 ID @param bucket Bucket 名称 */
    public SensorRepository(@Value("${app.influx-url}") String url,
            @Value("${app.influx-token}") String token, @Value("${app.influx-org}") String org,
            @Value("${app.influx-bucket}") String bucket) {
        if (!bucket.matches("[A-Za-z0-9_-]{1,100}")) { throw new IllegalArgumentException("Invalid bucket name"); }
        this.org = org;
        this.bucket = bucket;
        client = InfluxDBClientFactory.create(url, token.toCharArray(), org, bucket);
    }

    /** 同步写入一次采样，返回成功后才允许确认消息。
     * @param device 设备编号 @param temperature 温度 @param humidity 湿度
     * @param measured 设备采集时刻，可为空 @param received 服务处理时刻 */
    public void save(String device, BigDecimal temperature, BigDecimal humidity, Instant measured, Instant received) {
        validateDevice(device);
        Point point = Point.measurement("environment").addTag("device_id", device)
                .addField("temperature", temperature.doubleValue()).addField("humidity", humidity.doubleValue())
                .addField("received_at", received.toString())
                .addField("time_source", measured == null ? "server" : "device")
                .time(measured == null ? received : measured, WritePrecision.MS);
        if (measured != null) { point.addField("measured_at", measured.toString()); }
        client.getWriteApiBlocking().writePoint(point);
    }

    /** 查询倒序分页记录，时间戳毫秒值作为兼容的数字游标。
     * @param device 设备 @param from 开始时刻 @param to 结束时刻
     * @param beforeId 上页游标 @param limit 最大数量 @return 记录列表 */
    public List<ReadingController.Reading> readings(String device, Instant from, Instant to, long beforeId, int limit) {
        Instant stop = beforeId == Long.MAX_VALUE ? to : earlier(to, Instant.ofEpochMilli(beforeId));
        if (!from.isBefore(stop)) { return List.of(); }
        String flux = source(device, from, stop)
                + " |> sort(columns: [\"_time\"], desc: true) |> limit(n: " + limit + ")"
                + " |> pivot(rowKey: [\"_time\"], columnKey: [\"_field\"], valueColumn: \"_value\")"
                + " |> group(columns: [\"device_id\"])"
                + " |> sort(columns: [\"_time\"], desc: true) |> limit(n: " + limit + ")";
        List<ReadingController.Reading> result = new ArrayList<>();
        for (FluxRecord row : records(flux)) {
            Instant measured = timestamp(row.getValueByKey("measured_at"));
            Instant received = timestamp(row.getValueByKey("received_at"));
            result.add(new ReadingController.Reading(row.getTime().toEpochMilli(), device,
                    number(row, "temperature"), number(row, "humidity"), local(measured), local(received)));
        }
        return result;
    }

    /** 按北京时间时间桶计算平均值和采样数。
     * @param device 设备 @param from 开始时刻 @param to 结束时刻
     * @param seconds 桶宽秒数 @return 曲线点 */
    public List<ReadingController.Point> chart(String device, Instant from, Instant to, int seconds) {
        String window = "aggregateWindow(every: " + seconds + "s, createEmpty: false, timeSrc: \"_start\", ";
        String flux = "import \"timezone\"\noption location = timezone.location(name: \"Asia/Shanghai\")\n"
                + "data = " + source(device, from, to)
                + " |> filter(fn: (r) => r._field == \"temperature\" or r._field == \"humidity\")\n"
                + "means = data |> " + window + "fn: mean)\n"
                + "counts = data |> filter(fn: (r) => r._field == \"temperature\") |> " + window + "fn: count)"
                + " |> map(fn: (r) => ({r with _field: \"count\", _value: float(v: r._value)}))\n"
                + "union(tables: [means, counts]) |> group(columns: [\"device_id\"])"
                + " |> pivot(rowKey: [\"_time\"], columnKey: [\"_field\"], valueColumn: \"_value\")"
                + " |> sort(columns: [\"_time\"])";
        List<ReadingController.Point> result = new ArrayList<>();
        for (FluxRecord row : records(flux)) {
            result.add(new ReadingController.Point(local(row.getTime()), number(row, "temperature"),
                    number(row, "humidity"), number(row, "count").longValueExact()));
        }
        return result;
    }

    /** 创建受限的 Flux 数据源。 @return 数据源表达式 */
    private String source(String device, Instant from, Instant to) {
        validateDevice(device);
        return "from(bucket: \"" + bucket + "\") |> range(start: time(v: \"" + from
                + "\"), stop: time(v: \"" + to + "\"))"
                + " |> filter(fn: (r) => r._measurement == \"environment\" and r.device_id == \"" + device + "\")";
    }
    /** 查询并收集有限结果。 @return 数据点 */
    private List<FluxRecord> records(String flux) {
        return client.getQueryApi().query(flux, org).stream().flatMap(t -> t.getRecords().stream()).toList();
    }
    /** 验证设备标识，阻止将任意表达式拼入查询。 */
    private void validateDevice(String device) {
        if (!device.matches("[A-Za-z0-9_-]{1,64}")) { throw new IllegalArgumentException("Invalid device ID"); }
    }
    /** 解析数值字段。 @return 精确十进制值 */
    private BigDecimal number(FluxRecord row, String field) {
        return new BigDecimal(String.valueOf(row.getValueByKey(field)));
    }
    /** 解析时刻字符串。 @return 时刻或 null */
    private Instant timestamp(Object value) { return value == null ? null : Instant.parse(value.toString()); }
    /** 将时刻转换为北京时间。 @return 带时区的时间 */
    private OffsetDateTime local(Instant instant) {
        return instant == null ? null : instant.atZone(BEIJING).toOffsetDateTime();
    }
    /** 取较早时刻。 @return 较早时刻 */
    private Instant earlier(Instant first, Instant second) { return first.isBefore(second) ? first : second; }
    /** 关闭连接池。 */
    @PreDestroy public void close() { client.close(); }
}
