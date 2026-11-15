package com.smarthome.monitor;

import java.security.SecureRandom;
import java.time.Instant;
import java.util.Base64;
import java.util.HashMap;
import java.util.Map;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.stereotype.Service;

/** 管理单管理员登录及有期限的会话，重启后需重新登录。 */
@Service
public class AuthService {
    /** 配置的管理员名称。 */
    private final String username;
    /** BCrypt 密码摘要。 */
    private final String passwordHash;
    /** 服务器端会话到期时间。 */
    private final Map<String, Instant> sessions = new HashMap<>();
    /** 登录尝试时间窗口起点。 */
    private Instant window = Instant.EPOCH;
    /** 当前窗口登录次数。 */
    private int attempts;
    /** 密码验证器。 */
    private final BCryptPasswordEncoder encoder = new BCryptPasswordEncoder();
    /** 安全随机数来源。 */
    private final SecureRandom random = new SecureRandom();

    /** 创建认证服务。 @param username 管理员名称 @param passwordHash 密码摘要 */
    public AuthService(@Value("${app.username}") String username,
            @Value("${app.password-hash}") String passwordHash) {
        this.username = username;
        this.passwordHash = passwordHash;
    }

    /** 验证账号并创建会话。 @param name 账号 @param password 密码 @return 会话，失败返回 null */
    public synchronized LoginResult login(String name, String password) {
        Instant now = Instant.now();
        if (window.plusSeconds(60).isBefore(now)) { window = now; attempts = 0; }
        if (++attempts > 20) { throw new org.springframework.web.server.ResponseStatusException(
                org.springframework.http.HttpStatus.TOO_MANY_REQUESTS, "Too many login attempts"); }
        if (!username.equals(name) || !encoder.matches(password, passwordHash)) { return null; }
        sessions.entrySet().removeIf(e -> !e.getValue().isAfter(now));
        if (sessions.size() >= 1000) { throw new org.springframework.web.server.ResponseStatusException(
                org.springframework.http.HttpStatus.SERVICE_UNAVAILABLE); }
        byte[] bytes = new byte[32];
        random.nextBytes(bytes);
        String token = Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
        Instant expires = now.plusSeconds(86400);
        sessions.put(token, expires);
        return new LoginResult(token, expires);
    }

    /** 检查会话。 @param token 随机会话令牌 @return 是否有效 */
    public synchronized boolean valid(String token) {
        Instant expires = sessions.get(token);
        if (expires != null && expires.isAfter(Instant.now())) { return true; }
        sessions.remove(token);
        return false;
    }

    /** 注销当前会话。 @param token 会话令牌 */
    public synchronized void logout(String token) { sessions.remove(token); }

    /** 登录结果。 @param accessToken 访问令牌 @param expiresAt 到期时间 */
    public record LoginResult(String accessToken, Instant expiresAt) {
        /** 隐藏会话令牌。 @return 脱敏描述 */
        @Override public String toString() { return "LoginResult[accessToken=REDACTED]"; }
    }
}
