package com.smarthome.monitor;

import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.time.Instant;
import java.util.Base64;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

/**
 * 使用 MySQL 用户验证登录并管理限时会话，重启后需重新登录。
 *
 * @author 待补充
 */
@Service
public class AuthService {
    /** 登录尝试窗口秒数。 */
    private static final int LOGIN_WINDOW_SECONDS = 60;
    /** 每个时间窗口允许的全局登录次数。 */
    private static final int MAX_LOGIN_ATTEMPTS = 20;
    /** 服务器最多保留的有效会话数。 */
    private static final int MAX_SESSIONS = 1000;
    /** 会话有效期为一天。 */
    private static final int SESSION_SECONDS = 86400;
    /** BCrypt 接受的最大 UTF-8 密码字节数。 */
    private static final int MAX_PASSWORD_BYTES = 72;
    /** 用户账号数据访问器。 */
    private final UserRepository users;
    /** 服务器端会话，包含账号归属和到期时间。 */
    private final Map<String, Session> sessions = new HashMap<>(MAX_SESSIONS);
    /** 登录尝试时间窗口起点。 */
    private Instant window = Instant.EPOCH;
    /** 当前窗口登录次数。 */
    private int attempts;
    /** 密码验证器。 */
    private final BCryptPasswordEncoder encoder = new BCryptPasswordEncoder(12);
    /** 不存在账号也执行 BCrypt，避免直接跳过密码校验。 */
    private final String dummyHash = encoder.encode(UUID.randomUUID().toString());
    /** 安全随机数来源。 */
    private final SecureRandom random = new SecureRandom();

    /**
     * 创建认证服务，不再从配置读取登录账号和密码摘要。
     *
     * @param users 用户账号数据访问器
     */
    public AuthService(UserRepository users) {
        this.users = users;
    }

    /**
     * 从数据库验证账号并创建会话；数据库不可用时不降级到默认账号。
     *
     * @param name 账号
     * @param password 密码
     * @return 会话；账号不存在、禁用或密码错误时返回 null
     */
    public synchronized LoginResult login(String name, String password) {
        Instant now = Instant.now();
        if (window.plusSeconds(LOGIN_WINDOW_SECONDS).isBefore(now)) {
            window = now;
            attempts = 0;
        }
        if (++attempts > MAX_LOGIN_ATTEMPTS) {
            throw new ResponseStatusException(HttpStatus.TOO_MANY_REQUESTS, "Too many login attempts");
        }
        if (name == null || password == null || name.isBlank() || name.length() > 64
                || password.isBlank() || password.getBytes(StandardCharsets.UTF_8).length > MAX_PASSWORD_BYTES) {
            return null;
        }
        UserRepository.UserAccount user = users.getByUsername(name).orElse(null);
        String hash = user == null ? dummyHash : user.passwordHash();
        boolean passwordMatches = encoder.matches(password, hash);
        if (user == null || !Boolean.TRUE.equals(user.enabled()) || !passwordMatches) {
            return null;
        }
        sessions.entrySet().removeIf(entry -> !entry.getValue().expiresAt().isAfter(now));
        if (sessions.size() >= MAX_SESSIONS) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE);
        }
        byte[] bytes = new byte[32];
        random.nextBytes(bytes);
        String token = Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
        Instant expires = now.plusSeconds(SESSION_SECONDS);
        sessions.put(token, new Session(user.id(), expires));
        return new LoginResult(token, expires);
    }

    /**
     * 检查会话时效及账号启用状态。
     *
     * @param token 随机会话令牌
     * @return 是否有效
     */
    public synchronized boolean valid(String token) {
        Session session = sessions.get(token);
        if (session != null && session.expiresAt().isAfter(Instant.now()) && users.isEnabled(session.userId())) {
            return true;
        }
        sessions.remove(token);
        return false;
    }

    /**
     * 注销当前会话。
     *
     * @param token 会话令牌
     */
    public synchronized void logout(String token) {
        sessions.remove(token);
    }

    /**
     * 内部会话归属，不持久化令牌。
     *
     * @param userId 用户主键
     * @param expiresAt 到期时间
     * @author 待补充
     */
    private record Session(Long userId, Instant expiresAt) {
    }

    /**
     * 登录响应，保持 App 现有 JSON 协议。
     *
     * @param accessToken 访问令牌
     * @param expiresAt 到期时间
     * @author 待补充
     */
    public record LoginResult(String accessToken, Instant expiresAt) {
        /**
         * 隐藏会话令牌。
         *
         * @return 脱敏描述
         */
        @Override
        public String toString() {
            return "LoginResult[accessToken=REDACTED]";
        }
    }
}
