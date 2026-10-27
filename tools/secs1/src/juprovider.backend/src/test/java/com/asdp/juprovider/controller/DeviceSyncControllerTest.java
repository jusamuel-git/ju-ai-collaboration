package com.asdp.juprovider.controller;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.lang.reflect.Method;
import java.util.Arrays;
import java.util.List;

import org.junit.jupiter.api.Test;
import org.springframework.core.annotation.AnnotatedElementUtils;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;

/** SEC-S1: Client 동기화 컨트롤러는 조회(GET)만 제공한다. */
class DeviceSyncControllerTest {

    @Test
    void exposesOnlyGetMappings() {
        List<Method> mapped = Arrays.stream(DeviceSyncController.class.getDeclaredMethods())
                .filter(m -> AnnotatedElementUtils.hasAnnotation(m, RequestMapping.class))
                .toList();

        assertEquals(2, mapped.size(), "GET 전체 / GET 단건만 존재해야 한다");
        for (Method m : mapped) {
            assertTrue(m.isAnnotationPresent(GetMapping.class),
                    m.getName() + " 는 GET 이외 매핑을 가지면 안 된다");
        }
    }
}
