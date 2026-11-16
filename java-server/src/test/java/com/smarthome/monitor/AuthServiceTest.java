package com.smarthome.monitor;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.springframework.dao.DataAccessResourceFailureException;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;

/**
 * 验证数据库凭据、禁用账号和会话注销。
 *
 * @author 待补充
 */
class AuthServiceTest {
    /** 使用正确密码登录成功，注销后令牌失效。 */
    @Test
    void loginAndLogout_validPassword_revokesSession() {
        UserRepository users = mock(UserRepository.class);
        when(users.getByUsername("root")).thenReturn(Optional.of(account(true)));
        when(users.isEnabled(1L)).thenReturn(true);
        AuthService auth = new AuthService(users);
        assertNull(auth.login("root", "wrong"));
        AuthService.LoginResult result = auth.login("root", "test-password");
        assertNotNull(result);
        assertTrue(auth.valid(result.accessToken()));
        auth.logout(result.accessToken());
        assertFalse(auth.valid(result.accessToken()));
    }

    /** 不存在账号不能使用任何默认凭据登录。 */
    @Test
    void login_unknownUser_rejects() {
        UserRepository users = mock(UserRepository.class);
        when(users.getByUsername("unknown")).thenReturn(Optional.empty());
        assertNull(new AuthService(users).login("unknown", "test-password"));
    }

    /** 禁用账号即使密码正确也不能创建会话。 */
    @Test
    void login_disabledUser_rejects() {
        UserRepository users = mock(UserRepository.class);
        when(users.getByUsername("root")).thenReturn(Optional.of(account(false)));
        assertNull(new AuthService(users).login("root", "test-password"));
    }

    /** 禁用用户后已登录会话也失效。 */
    @Test
    void valid_disabledAfterLogin_revokesSession() {
        UserRepository users = mock(UserRepository.class);
        when(users.getByUsername("root")).thenReturn(Optional.of(account(true)));
        when(users.isEnabled(1L)).thenReturn(false);
        AuthService auth = new AuthService(users);
        AuthService.LoginResult result = auth.login("root", "test-password");
        assertNotNull(result);
        assertFalse(auth.valid(result.accessToken()));
    }

    /** 数据库不可用时拒绝认证，禁止绕过数据库。 */
    @Test
    void login_databaseUnavailable_doesNotFallback() {
        UserRepository users = mock(UserRepository.class);
        when(users.getByUsername("root")).thenThrow(new DataAccessResourceFailureException("Unavailable"));
        AuthService auth = new AuthService(users);
        assertThrows(DataAccessResourceFailureException.class, () -> auth.login("root", "test-password"));
    }

    /** 多字节密码按 BCrypt 字节限制拒绝，而非截断或抛出校验异常。 */
    @Test
    void login_passwordOverByteLimit_rejects() {
        assertNull(new AuthService(mock(UserRepository.class)).login("root", "密".repeat(25)));
    }

    /**
     * 构造测试账号，不依赖线上凭据。
     *
     * @param enabled 是否启用
     * @return 测试账号
     */
    private UserRepository.UserAccount account(boolean enabled) {
        return new UserRepository.UserAccount(1L, "root",
                new BCryptPasswordEncoder(4).encode("test-password"), enabled);
    }
}
