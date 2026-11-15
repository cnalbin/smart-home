package com.smarthome.monitor;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;

/** 验证登录和会话注销。 */
class AuthServiceTest {
    @Test void loginAndLogout_validPassword_revokesSession() {
        AuthService auth = new AuthService("root", new BCryptPasswordEncoder().encode("test-password"));
        assertNull(auth.login("root", "wrong"));
        AuthService.LoginResult result = auth.login("root", "test-password");
        assertNotNull(result);
        assertTrue(auth.valid(result.accessToken()));
        auth.logout(result.accessToken());
        assertFalse(auth.valid(result.accessToken()));
    }
}
