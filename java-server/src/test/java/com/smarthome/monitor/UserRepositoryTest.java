package com.smarthome.monitor;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.embedded.EmbeddedDatabase;
import org.springframework.jdbc.datasource.embedded.EmbeddedDatabaseBuilder;
import org.springframework.jdbc.datasource.embedded.EmbeddedDatabaseType;

/**
 * 使用独立内存数据库验证 SQL 绑定及账号状态查询，不连接 NAS。
 *
 * @author 待补充
 */
class UserRepositoryTest {
    /** 每个测试独立的临时数据库。 */
    private EmbeddedDatabase database;
    /** 待验证的用户数据访问器。 */
    private UserRepository users;
    /** 测试账号密码摘要占位，仅用于数据访问测试。 */
    private static final String TEST_HASH = "test-hash-not-for-login";

    /** 创建覆盖查询所需字段的测试表，与生产建表方言分离。 */
    @BeforeEach
    void setUp() {
        database = new EmbeddedDatabaseBuilder().generateUniqueName(true).setType(EmbeddedDatabaseType.H2).build();
        JdbcTemplate jdbc = new JdbcTemplate(database);
        jdbc.execute("CREATE TABLE app_user (id BIGINT PRIMARY KEY, username VARCHAR(64) UNIQUE, "
                + "password_hash VARCHAR(60), is_enabled TINYINT)");
        jdbc.update("INSERT INTO app_user VALUES (?, ?, ?, ?)", 1L, "root", TEST_HASH, 1);
        jdbc.update("INSERT INTO app_user VALUES (?, ?, ?, ?)", 2L, "disabled", TEST_HASH, 0);
        users = new UserRepository(jdbc);
    }

    /** 关闭每个测试使用的数据库。 */
    @AfterEach
    void tearDown() {
        if (database != null) {
            database.shutdown();
        }
    }

    /** 查询可用账号并确保描述中不含密码摘要。 */
    @Test
    void getByUsername_existingUser_returnsRedactedAccount() {
        UserRepository.UserAccount account = users.getByUsername("root").orElseThrow();
        assertTrue(account.enabled());
        assertFalse(account.toString().contains(TEST_HASH));
        assertTrue(users.getByUsername("ROOT").isEmpty());
    }

    /** SQL 注入及未知用户名不能得到已有账号。 */
    @Test
    void getByUsername_injectionOrMissing_returnsEmpty() {
        assertTrue(users.getByUsername("' OR 1=1 --").isEmpty());
        assertTrue(users.getByUsername("missing").isEmpty());
    }

    /** 仅存在且启用的账号具有有效状态。 */
    @Test
    void isEnabled_enabledDisabledAndMissing_checksStatus() {
        assertTrue(users.isEnabled(1L));
        assertFalse(users.isEnabled(2L));
        assertFalse(users.isEnabled(3L));
    }
}
