package com.asdp.juprovider.security;

import java.io.IOException;
import java.nio.charset.StandardCharsets;

import org.springframework.http.MediaType;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.AuthenticationException;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.web.AuthenticationEntryPoint;
import org.springframework.security.web.access.AccessDeniedHandler;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

/**
 * 인증 실패(401)·권한 없음(403)을 ApiResponse 형식 JSON으로 응답한다.
 */
public class JsonSecurityErrorHandler implements AuthenticationEntryPoint, AccessDeniedHandler {

    @Override
    public void commence(
            HttpServletRequest request,
            HttpServletResponse response,
            AuthenticationException authException) throws IOException {
        write(response, HttpServletResponse.SC_UNAUTHORIZED, "UNAUTHORIZED", "인증이 필요합니다.");
    }

    @Override
    public void handle(
            HttpServletRequest request,
            HttpServletResponse response,
            AccessDeniedException accessDeniedException) throws IOException {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        // Desktop Client 인증(CLIENT 권한)에는 PASSWORD_OK가 원래 없다 → 비밀번호 문구 대상 아님 (SEC-S1b)
        boolean client = authentication != null
                && authentication.getAuthorities().stream()
                        .anyMatch(a -> ClientKeyAuthenticationFilter.CLIENT_AUTHORITY.equals(a.getAuthority()));
        boolean passwordChangeRequired = authentication != null
                && !client
                && authentication.getAuthorities().stream()
                        .noneMatch(a -> UserTokenAuthenticationConverter.AUTHORITY_PASSWORD_OK
                                .equals(a.getAuthority()));
        write(response, HttpServletResponse.SC_FORBIDDEN, "FORBIDDEN",
                passwordChangeRequired ? "비밀번호를 먼저 변경해야 합니다." : "권한이 없습니다.");
    }

    private static void write(HttpServletResponse response, int status, String code, String message)
            throws IOException {
        response.setStatus(status);
        response.setCharacterEncoding(StandardCharsets.UTF_8.name());
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        response.getWriter().write(
                "{\"success\":false,\"data\":null,\"message\":\"" + message
                        + "\",\"code\":\"" + code + "\"}");
    }
}
