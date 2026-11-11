package com.asdp.juprovider.core.protocol.rule;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * 규칙 JSON 읽기 전용 최소 파서 (C5c). 의존성 추가 없이 Desktop System.Text.Json 과 같은 엄격 JSON 만 받는다.
 * 결과: Map(LinkedHashMap) · List · String · BigDecimal · Boolean · null
 */
final class MiniJson {

    private final String s;

    private int i;

    private MiniJson(String s) {
        this.s = s;
    }

    static Object parse(String text) {
        MiniJson p = new MiniJson(text);
        p.ws();
        Object v = p.value(0);
        p.ws();
        if (p.i != p.s.length()) {
            throw p.error("JSON 뒤에 남은 문자가 있습니다");
        }
        return v;
    }

    private IllegalArgumentException error(String message) {
        return new IllegalArgumentException(message + " (위치 " + i + ")");
    }

    private void ws() {
        while (i < s.length()) {
            char c = s.charAt(i);
            if (c == ' ' || c == '\t' || c == '\r' || c == '\n') {
                i++;
            } else {
                break;
            }
        }
    }

    private Object value(int depth) {
        if (depth > 32) {
            throw error("JSON 중첩이 너무 깊습니다");
        }
        if (i >= s.length()) {
            throw error("JSON 이 끝났습니다");
        }
        char c = s.charAt(i);
        switch (c) {
            case '{':
                return object(depth);
            case '[':
                return array(depth);
            case '"':
                return string();
            case 't':
                return literal("true", Boolean.TRUE);
            case 'f':
                return literal("false", Boolean.FALSE);
            case 'n':
                return literal("null", null);
            default:
                if (c == '-' || (c >= '0' && c <= '9')) {
                    return number();
                }
                throw error("알 수 없는 JSON 값");
        }
    }

    private Object literal(String word, Object v) {
        if (!s.startsWith(word, i)) {
            throw error("알 수 없는 JSON 값");
        }
        i += word.length();
        return v;
    }

    private Map<String, Object> object(int depth) {
        Map<String, Object> m = new LinkedHashMap<>();
        i++;
        ws();
        if (i < s.length() && s.charAt(i) == '}') {
            i++;
            return m;
        }
        while (true) {
            ws();
            if (i >= s.length() || s.charAt(i) != '"') {
                throw error("객체 키는 문자열이어야 합니다");
            }
            String key = string();
            ws();
            if (i >= s.length() || s.charAt(i) != ':') {
                throw error("':' 가 필요합니다");
            }
            i++;
            ws();
            m.put(key, value(depth + 1));
            ws();
            if (i >= s.length()) {
                throw error("'}' 가 필요합니다");
            }
            char c = s.charAt(i++);
            if (c == '}') {
                return m;
            }
            if (c != ',') {
                throw error("',' 또는 '}' 가 필요합니다");
            }
        }
    }

    private List<Object> array(int depth) {
        List<Object> list = new ArrayList<>();
        i++;
        ws();
        if (i < s.length() && s.charAt(i) == ']') {
            i++;
            return list;
        }
        while (true) {
            ws();
            list.add(value(depth + 1));
            ws();
            if (i >= s.length()) {
                throw error("']' 가 필요합니다");
            }
            char c = s.charAt(i++);
            if (c == ']') {
                return list;
            }
            if (c != ',') {
                throw error("',' 또는 ']' 가 필요합니다");
            }
        }
    }

    private String string() {
        StringBuilder b = new StringBuilder();
        i++;
        while (true) {
            if (i >= s.length()) {
                throw error("문자열이 닫히지 않았습니다");
            }
            char c = s.charAt(i++);
            if (c == '"') {
                return b.toString();
            }
            if (c < 0x20) {
                throw error("문자열에 제어 문자가 있습니다");
            }
            if (c != '\\') {
                b.append(c);
                continue;
            }
            if (i >= s.length()) {
                throw error("잘못된 escape");
            }
            char e = s.charAt(i++);
            switch (e) {
                case '"', '\\', '/' -> b.append(e);
                case 'b' -> b.append('\b');
                case 'f' -> b.append('\f');
                case 'n' -> b.append('\n');
                case 'r' -> b.append('\r');
                case 't' -> b.append('\t');
                case 'u' -> {
                    if (i + 4 > s.length()) {
                        throw error("잘못된 \\u escape");
                    }
                    try {
                        b.append((char) Integer.parseInt(s.substring(i, i + 4), 16));
                    } catch (NumberFormatException ex) {
                        throw error("잘못된 \\u escape");
                    }
                    i += 4;
                }
                default -> throw error("잘못된 escape");
            }
        }
    }

    private BigDecimal number() {
        int start = i;
        if (s.charAt(i) == '-') {
            i++;
        }
        if (i >= s.length()) {
            throw error("잘못된 숫자");
        }
        if (s.charAt(i) == '0') {
            i++;
        } else if (s.charAt(i) >= '1' && s.charAt(i) <= '9') {
            digits();
        } else {
            throw error("잘못된 숫자");
        }
        if (i < s.length() && s.charAt(i) == '.') {
            i++;
            if (digits() == 0) {
                throw error("잘못된 숫자");
            }
        }
        if (i < s.length() && (s.charAt(i) == 'e' || s.charAt(i) == 'E')) {
            i++;
            if (i < s.length() && (s.charAt(i) == '+' || s.charAt(i) == '-')) {
                i++;
            }
            if (digits() == 0) {
                throw error("잘못된 숫자");
            }
        }
        return new BigDecimal(s.substring(start, i));
    }

    private int digits() {
        int n = 0;
        while (i < s.length() && s.charAt(i) >= '0' && s.charAt(i) <= '9') {
            i++;
            n++;
        }
        return n;
    }
}
