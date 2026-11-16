package com.smarthome.monitor;

import java.util.List;
import java.util.Optional;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

/**
 * 从 MySQL 读取应用用户，凭据仅供后端校验。
 *
 * @author 待补充
 */
@Repository
public class UserRepository {
    /** 由连接池管理数据库资源的查询模板。 */
    private final JdbcTemplate jdbc;

    /**
     * 创建用户数据访问器。
     *
     * @param jdbc 数据库查询模板
     */
    public UserRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    /**
     * 使用参数绑定查询唯一账号，不返回密码明文。
     *
     * @param username 登录账号，区分大小写
     * @return 账号及密码摘要，不存在时为空
     */
    public Optional<UserAccount> getByUsername(String username) {
        List<UserAccount> users = jdbc.query(
                "SELECT id, username, password_hash, is_enabled FROM app_user WHERE username = ? LIMIT 1",
                (row, index) -> new UserAccount(row.getLong("id"), row.getString("username"),
                        row.getString("password_hash"), row.getBoolean("is_enabled")), username);
        return users.stream().filter(user -> user.username().equals(username)).findFirst();
    }

    /**
     * 检查会话所属账号是否仍可使用，禁用或删除账号后旧会话失效。
     *
     * @param userId 用户主键
     * @return 用户是否存在且启用
     */
    public boolean isEnabled(Long userId) {
        Long count = jdbc.queryForObject(
                "SELECT COUNT(*) FROM app_user WHERE id = ? AND is_enabled = 1", Long.class, userId);
        return count != null && count == 1L;
    }

    /**
     * 后端内部认证数据，不用于接口返回。
     *
     * @param id 用户主键
     * @param username 登录账号
     * @param passwordHash BCrypt 密码摘要
     * @param enabled 是否启用
     * @author 待补充
     */
    public record UserAccount(Long id, String username, String passwordHash, Boolean enabled) {
        /**
         * 隐藏凭据摘要，避免日志泄露。
         *
         * @return 脱敏描述
         */
        @Override
        public String toString() {
            return "UserAccount[id=" + id + ", passwordHash=REDACTED]";
        }
    }
}
