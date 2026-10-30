package com.asdp.juprovider;

import org.mybatis.spring.annotation.MapperScan;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.builder.SpringApplicationBuilder;
import org.springframework.boot.web.servlet.support.SpringBootServletInitializer;

@SpringBootApplication
@MapperScan({
    "com.asdp.juprovider.dao",
    "com.asdp.juprovider.core.menu.dao",
    "com.asdp.juprovider.core.device.dao",
    "com.asdp.juprovider.core.systemcode.dao",
    "com.asdp.juprovider.core.language.dao",
    "com.asdp.juprovider.core.security.dao",
    "com.asdp.juprovider.core.client.dao",
    "com.asdp.juprovider.core.action.dao",
    "com.asdp.juprovider.core.protocol.dao",
    "com.asdp.juprovider.core.protocolsync.dao"
})
public class JuProviderApplication extends SpringBootServletInitializer {

    public static void main(String[] args) {
        SpringApplication.run(JuProviderApplication.class, args);
    }

    @Override
    protected SpringApplicationBuilder configure(SpringApplicationBuilder application) {
        return application.sources(JuProviderApplication.class);
    }
}
