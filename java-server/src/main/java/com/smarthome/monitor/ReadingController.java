package com.smarthome.monitor;

import java.math.BigDecimal;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.util.List;
import java.util.Map;
import java.util.regex.Pattern;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

/** 提供温湿度最新值、历史列表和曲线。 */
@RestController
@io.swagger.v3.oas.annotations.security.SecurityRequirement(name = "bearerAuth")
@RequestMapping("/api/devices/{deviceId}/readings")
public class ReadingController {
    private static final Pattern DEVICE = Pattern.compile("[A-Za-z0-9_-]{1,64}");
    private static final ZoneId BEIJING = ZoneId.of("Asia/Shanghai");
    private static final LocalDateTime CHART_EPOCH = LocalDateTime.of(1970, 1, 1, 0, 0);
    private final JdbcTemplate jdbc;
    /** 创建查询接口。 @param jdbc 数据库访问器 */
    public ReadingController(JdbcTemplate jdbc) { this.jdbc = jdbc; }

    /** 温湿度记录。 @param id 主键 @param deviceId 设备 @param temperature 温度 @param humidity 湿度
     * @param measuredAt 采集时间 @param receivedAt 接收时间 */
    public record Reading(long id, String deviceId, BigDecimal temperature, BigDecimal humidity,
                          OffsetDateTime measuredAt, OffsetDateTime receivedAt) { }
    /** 曲线时间桶。 @param time 起点 @param temperature 平均温度 @param humidity 平均湿度 @param count 数量 */
    public record Point(OffsetDateTime time, BigDecimal temperature, BigDecimal humidity, long count) { }

    /** 查询最新记录。 @param deviceId 设备编号 @return 最新记录 */
    @GetMapping("/latest")
    public Reading latest(@PathVariable String deviceId) {
        validateDevice(deviceId);
        List<Reading> rows = query(deviceId, Instant.EPOCH, Instant.now().plusSeconds(60), Long.MAX_VALUE, 1);
        if (rows.isEmpty()) { throw new ResponseStatusException(HttpStatus.NOT_FOUND, "No readings"); }
        return rows.get(0);
    }
    /** 查询分页记录。 @return 记录及下一页游标 */
    @GetMapping
    public Map<String, Object> list(@PathVariable String deviceId,
            @RequestParam Instant from, @RequestParam Instant to,
            @RequestParam(defaultValue = "100") int limit,
            @RequestParam(defaultValue = "9223372036854775807") long beforeId) {
        validate(deviceId, from, to);
        if (limit < 1 || limit > 500 || beforeId < 1) { throw new ResponseStatusException(HttpStatus.BAD_REQUEST); }
        List<Reading> rows = query(deviceId, from, to, beforeId, limit);
        return Map.of("items", rows, "nextBeforeId", rows.size() == limit ? rows.get(rows.size() - 1).id() : 0);
    }
    /** 查询指定区间的平均值曲线。 @return 时间桶序列 */
    @GetMapping("/chart")
    public List<Point> chart(@PathVariable String deviceId, @RequestParam Instant from, @RequestParam Instant to,
            @RequestParam(defaultValue = "3600") int bucketSeconds) {
        validate(deviceId, from, to);
        if (bucketSeconds != 60 && bucketSeconds != 3600 && bucketSeconds != 86400) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Invalid bucket size");
        }
        if ((Duration.between(from, to).getSeconds() / bucketSeconds) > 2000) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Too many points");
        }
        return jdbc.query("SELECT FLOOR(TIMESTAMPDIFF(SECOND, '1970-01-01 00:00:00', observed_at)/?) AS bucket, "
                + "AVG(temperature) AS temperature, AVG(humidity) AS humidity, COUNT(*) AS n FROM sensor_reading "
                + "WHERE device_id=? AND observed_at>=? AND observed_at<? GROUP BY bucket ORDER BY bucket",
                (rs, n) -> new Point(CHART_EPOCH.plusSeconds(rs.getLong("bucket") * bucketSeconds)
                        .atZone(BEIJING).toOffsetDateTime(),
                        rs.getBigDecimal("temperature"), rs.getBigDecimal("humidity"), rs.getLong("n")),
                bucketSeconds, deviceId, LocalDateTime.ofInstant(from, BEIJING), LocalDateTime.ofInstant(to, BEIJING));
    }
    private List<Reading> query(String deviceId, Instant from, Instant to, long beforeId, int limit) {
        return jdbc.query("SELECT id,device_id,temperature,humidity,measured_at,received_at FROM sensor_reading "
                + "WHERE device_id=? AND observed_at>=? AND observed_at<? AND id<? ORDER BY id DESC LIMIT ?",
                (rs, n) -> new Reading(rs.getLong("id"), rs.getString("device_id"), rs.getBigDecimal("temperature"),
                        rs.getBigDecimal("humidity"), toBeijing(rs.getObject("measured_at", LocalDateTime.class)),
                        toBeijing(rs.getObject("received_at", LocalDateTime.class))),
                deviceId, LocalDateTime.ofInstant(from, BEIJING), LocalDateTime.ofInstant(to, BEIJING),
                beforeId, limit);
    }
    private OffsetDateTime toBeijing(LocalDateTime time) {
        return time == null ? null : time.atZone(BEIJING).toOffsetDateTime();
    }
    private void validate(String deviceId, Instant from, Instant to) {
        validateDevice(deviceId);
        if (!from.isBefore(to) || Duration.between(from, to).compareTo(Duration.ofDays(366)) > 0) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Invalid time range");
        }
    }
    private void validateDevice(String deviceId) {
        if (!DEVICE.matcher(deviceId).matches()) { throw new ResponseStatusException(HttpStatus.BAD_REQUEST); }
    }
}
