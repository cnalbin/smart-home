package com.smarthome.monitor;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

/** 管理员认证接口。 */
@RestController
@RequestMapping("/api/auth")
public class AuthController {
    /** 会话服务。 */
    private final AuthService auth;
    /** 创建认证接口。 @param auth 会话服务 */
    public AuthController(AuthService auth) { this.auth = auth; }
    /** 登录参数。 @param username 账号 @param password 密码 */
    public record LoginRequest(@NotBlank @Size(max = 64) String username,
                               @NotBlank @Size(max = 72) String password) {
        /** 隐藏密码。 @return 脱敏描述 */
        @Override public String toString() { return "LoginRequest[password=REDACTED]"; }
    }
    /** 登录。 @param request 登录参数 @return 会话及到期时间 */
    @PostMapping("/login")
    @Operation(summary = "账号密码登录")
    public AuthService.LoginResult login(@Valid @RequestBody LoginRequest request) {
        AuthService.LoginResult result = auth.login(request.username(), request.password());
        if (result == null) { throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Invalid credentials"); }
        return result;
    }
    /** 注销。 @param header 当前会话认证头 */
    @PostMapping("/logout")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    @SecurityRequirement(name = "bearerAuth")
    public void logout(@RequestHeader("Authorization") String header) { auth.logout(header.substring(7)); }
}
