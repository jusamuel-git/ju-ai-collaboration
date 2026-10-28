package com.asdp.juprovider.security;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;


import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;

/** SEC-S1b: 403 응답 문구 (Client / 비밀번호 미변경 사용자 / 일반 사용자) */
class JsonSecurityErrorHandlerTest {

    @AfterEach
    void clear() {
        SecurityContextHolder.clearContext();
    }

    private String forbiddenBodyFor(String... authorities) throws Exception {
        SecurityContextHolder.getContext().setAuthentication(new UsernamePasswordAuthenticationToken(
                "p", null, java.util.Arrays.stream(authorities).map(SimpleGrantedAuthority::new).toList()));
        MockHttpServletResponse response = new MockHttpServletResponse();
        new JsonSecurityErrorHandler().handle(new MockHttpServletRequest(), response, new AccessDeniedException("x"));
        assertEquals(403, response.getStatus());
        return response.getContentAsString(java.nio.charset.StandardCharsets.UTF_8);
    }

    @Test
    void clientGetsPlainForbidden() throws Exception {
        String body = forbiddenBodyFor(ClientKeyAuthenticationFilter.CLIENT_AUTHORITY);
        assertTrue(body.contains("권한이 없습니다."), body);
        assertTrue(body.contains("\"code\":\"FORBIDDEN\""), body);
    }

    @Test
    void userWithoutPasswordOkKeepsPasswordMessage() throws Exception {
        String body = forbiddenBodyFor("ROLE_USER");
        assertTrue(body.contains("비밀번호를 먼저 변경해야 합니다."), body);
    }

    @Test
    void userWithPasswordOkGetsPlainForbidden() throws Exception {
        String body = forbiddenBodyFor(UserTokenAuthenticationConverter.AUTHORITY_PASSWORD_OK);
        assertTrue(body.contains("권한이 없습니다."), body);
    }
}
