package com.smarthome.monitor;

import java.io.IOException;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/** 校验业务接口登录会话，文档及登录接口可直接访问。 */
@Component
public class ApiTokenFilter extends OncePerRequestFilter {
    /** 会话验证器。 */
    private final AuthService auth;
    /** 创建校验器。 @param auth 会话服务 */
    public ApiTokenFilter(AuthService auth) { this.auth = auth; }
    /** 验证业务接口登录状态。 */
    @Override protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response,
            FilterChain chain) throws ServletException, IOException {
        String path = request.getServletPath();
        if (!path.startsWith("/api/") || (path.equals("/api/auth/login") && request.getMethod().equals("POST"))) {
            chain.doFilter(request, response);
            return;
        }
        String header = request.getHeader("Authorization");
        if (header == null || !header.startsWith("Bearer ") || !auth.valid(header.substring(7))) {
            response.setStatus(401);
            response.setContentType("application/json;charset=UTF-8");
            response.getWriter().write("{\"message\":\"Login required\"}");
            return;
        }
        chain.doFilter(request, response);
    }
}
