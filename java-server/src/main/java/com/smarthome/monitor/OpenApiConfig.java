package com.smarthome.monitor;

import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Info;
import io.swagger.v3.oas.models.Components;
import io.swagger.v3.oas.models.security.SecurityScheme;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/** API 文档和登录令牌授权配置。 */
@Configuration
public class OpenApiConfig {
    /** 构造接口文档。 @return OpenAPI 配置 */
    @Bean public OpenAPI openAPI() {
        return new OpenAPI().info(new Info().title("智能家居服务").version("1.1"))
                .addServersItem(new io.swagger.v3.oas.models.servers.Server().url("/"))
                .components(new Components().addSecuritySchemes("bearerAuth", new SecurityScheme()
                        .type(SecurityScheme.Type.HTTP).scheme("bearer")));
    }
}
