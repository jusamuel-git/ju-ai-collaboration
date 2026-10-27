package com.asdp.juprovider.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.annotation.Order;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;

import com.asdp.juprovider.core.client.service.ClientService;
import com.asdp.juprovider.security.ClientKeyAuthenticationFilter;
import com.asdp.juprovider.security.JsonSecurityErrorHandler;
import com.asdp.juprovider.security.UserTokenAuthenticationConverter;
import com.asdp.juprovider.service.AuthService;

/**
 * 인증 구조 (JU-1A + JU-1B)
 *
 * 1) Client 체인 : /api/core/sync/**, /api/client/** → Desktop Client Key (X-JU-Client-Id / X-JU-Client-Key)
 *    /api/core/sync/** 는 GET만 허용 (SEC-S1, 그 외 메서드 403)
 * 2) API 체인  : /api/**            → 사용자 JWT
 *      - 공개: POST /api/auth/login, /api/health
 *      - 로그인만: /api/auth/me, /api/auth/password (최초 비밀번호 변경 전에도 허용)
 *      - /api/admin/**: 어드민(AUTH_TYPE AUTH0001) + 비밀번호 변경 완료
 *      - 그 외(/api/core/**, /api/action/** 등): 로그인 + 비밀번호 변경 완료(PW_OK). 아니면 403
 *      - Menu Action 실행 권한(AUTH_ATTR 비트)은 Core PermissionService에서 검사
 * 3) 웹 체인   : 그 밖의 경로 (Vue 정적 파일) 공개
 */
@Configuration
public class SecurityConfig {

    /** 어드민 (ju_auth.AUTH_TYPE = AUTH0001). 비밀번호 변경 완료 후에만 부여된다 */
    public static final String ROLE_ADMIN = "ROLE_AUTH0001";

    private final JsonSecurityErrorHandler errorHandler = new JsonSecurityErrorHandler();

    @Bean
    @Order(1)
    public SecurityFilterChain clientSecurityFilterChain(
            HttpSecurity http,
            ClientService clientService) throws Exception {
        http
            .securityMatcher("/api/core/sync/**", "/api/client/**")
            .csrf(csrf -> csrf.disable())
            .cors(Customizer.withDefaults())
            .sessionManagement(session ->
                    session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .addFilterBefore(
                    new ClientKeyAuthenticationFilter(clientService),
                    UsernamePasswordAuthenticationFilter.class)
            .authorizeHttpRequests(auth -> auth
                    // SEC-S1: Client는 서버 공통 정의를 조회만 한다. 동기화 경로의 쓰기 메서드는 차단(403).
                    .requestMatchers(HttpMethod.GET, "/api/core/sync/**")
                        .hasAuthority(ClientKeyAuthenticationFilter.CLIENT_AUTHORITY)
                    .requestMatchers("/api/core/sync/**").denyAll()
                    .anyRequest().hasAuthority(ClientKeyAuthenticationFilter.CLIENT_AUTHORITY))
            .exceptionHandling(ex -> ex
                    .authenticationEntryPoint(errorHandler)
                    .accessDeniedHandler(errorHandler));
        return http.build();
    }

    @Bean
    @Order(2)
    public SecurityFilterChain apiSecurityFilterChain(
            HttpSecurity http,
            AuthService authService) throws Exception {
        UserTokenAuthenticationConverter userTokenAuthenticationConverter =
                new UserTokenAuthenticationConverter(authService);
        http
            .securityMatcher("/api/**")
            .csrf(csrf -> csrf.disable())
            .cors(Customizer.withDefaults())
            .sessionManagement(session ->
                    session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .authorizeHttpRequests(auth -> auth
                    .requestMatchers(HttpMethod.POST, "/api/auth/login").permitAll()
                    .requestMatchers("/api/health").permitAll()
                    .requestMatchers("/api/auth/me", "/api/auth/password")
                            .hasAuthority(UserTokenAuthenticationConverter.AUTHORITY_USER)
                    .requestMatchers("/api/admin/**").hasAuthority(ROLE_ADMIN)
                    .anyRequest()
                            .hasAuthority(UserTokenAuthenticationConverter.AUTHORITY_PASSWORD_OK))
            .oauth2ResourceServer(oauth2 -> oauth2
                    .jwt(jwt -> jwt.jwtAuthenticationConverter(userTokenAuthenticationConverter))
                    .authenticationEntryPoint(errorHandler)
                    .accessDeniedHandler(errorHandler))
            .exceptionHandling(ex -> ex
                    .authenticationEntryPoint(errorHandler)
                    .accessDeniedHandler(errorHandler));
        return http.build();
    }

    @Bean
    @Order(3)
    public SecurityFilterChain webSecurityFilterChain(HttpSecurity http) throws Exception {
        http
            .csrf(csrf -> csrf.disable())
            .authorizeHttpRequests(auth -> auth.anyRequest().permitAll());
        return http.build();
    }

    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }
}
