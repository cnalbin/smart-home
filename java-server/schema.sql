-- 仅创建当前使用的应用用户表；不在脚本中保存默认账号密码。
-- 初始化账号由部署步骤生成 BCrypt 摘要后插入，重复部署不得覆盖现有密码。
CREATE TABLE IF NOT EXISTS app_user (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '用户主键',
    username VARCHAR(64) COLLATE utf8mb4_bin NOT NULL COMMENT '登录账号，区分大小写',
    password_hash CHAR(60) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT 'BCrypt密码摘要',
    is_enabled TINYINT UNSIGNED NOT NULL DEFAULT 1 COMMENT '是否启用：1是，0否',
    gmt_create DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间，北京时间',
    gmt_modified DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
        ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '修改时间，北京时间',
    PRIMARY KEY (id),
    UNIQUE KEY uk_username (username(64)),
    CONSTRAINT chk_app_user_is_enabled CHECK (is_enabled IN (0, 1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin COMMENT='智能家居应用用户';
