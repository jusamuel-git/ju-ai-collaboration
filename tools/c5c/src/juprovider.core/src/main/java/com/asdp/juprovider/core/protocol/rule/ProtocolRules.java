package com.asdp.juprovider.core.protocol.rule;

import java.math.BigDecimal;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.regex.Pattern;
import java.util.regex.PatternSyntaxException;

/**
 * 수집 규칙 저장 검사 (C5c, 설계 §4). Desktop 과 같은 규칙:
 * - 표현식: lib.protocol Expression/ProtocolExpression.ToBytes
 * - FRAME_RULE / PARSE_RULE JSON v1: lib.protocol Rules/RuleReader (JSON 부분)
 * - EXPECT_RULE: Sync/CollectionProfile expect ({"startsWith"} 또는 {"regex"})
 * 같은 입력의 판정은 공통 테스트 벡터(desktop/tests/.../TestData/rule_vectors.json)로 양쪽에서 확인한다.
 *
 * 각 메서드는 오류면 {@link RuleException}(사용자에게 보여 줄 문장) 을 던진다.
 */
public final class ProtocolRules {

    /** 규칙 형식 오류 */
    public static final class RuleException extends RuntimeException {

        private static final long serialVersionUID = 1L;

        public RuleException(String message) {
            super(message);
        }
    }

    private static final Map<String, Integer> NAMES = Map.of(
            "NUL", 0x00, "STX", 0x02, "ETX", 0x03, "ACK", 0x06, "TAB", 0x09,
            "LF", 0x0A, "CR", 0x0D, "DLE", 0x10, "NAK", 0x15, "ESC", 0x1B);

    private ProtocolRules() {
    }

    // ===== 표현식 =====

    /** 표현식 → 바이트 수. 문법: [이름] [16진 2자리], 그 외 ASCII 그대로 */
    public static int expressionLength(String expression) {
        String s = expression == null ? "" : expression;
        int n = 0;
        for (int i = 0; i < s.length();) {
            char c = s.charAt(i);
            if (c == '[') {
                int end = s.indexOf(']', i + 1);
                if (end < 0) {
                    throw new RuleException("닫는 ']'가 없습니다. 위치 " + i);
                }
                String token = s.substring(i + 1, end).trim();
                if (!NAMES.containsKey(token.toUpperCase(Locale.ROOT)) && !isHexByte(token)) {
                    throw new RuleException("알 수 없는 바이트 표현입니다: [" + token + "] 위치 " + i);
                }
                n++;
                i = end + 1;
                continue;
            }
            if (c > 0x7F) {
                throw new RuleException("ASCII 범위를 벗어난 문자입니다: '" + c + "' 위치 " + i);
            }
            n++;
            i++;
        }
        return n;
    }

    public static void validateExpression(String expression) {
        expressionLength(expression);
    }

    private static boolean isHexByte(String t) {
        return t.length() == 2 && hex(t.charAt(0)) && hex(t.charAt(1));
    }

    private static boolean hex(char c) {
        return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
    }

    // ===== FRAME_RULE =====

    public static void validateFrameRule(String text) {
        Map<String, Object> r = root(text);
        String kind = kind(r);
        Integer maxLen = integer(r, "maxLen");
        if (maxLen != null && maxLen <= 0) {
            throw new RuleException("maxLen은 1 이상이어야 합니다.");
        }
        checksum(r);
        switch (kind) {
            case "DELIM" -> {
                bytes(str(r, "end") == null ? "[CR][LF]" : str(r, "end"), "end");
                if (str(r, "start") != null) {
                    bytes(str(r, "start"), "start");
                }
            }
            case "STXETX" -> {
                oneByte(str(r, "stx") == null ? "[STX]" : str(r, "stx"), "stx");
                oneByte(str(r, "etx") == null ? "[ETX]" : str(r, "etx"), "etx");
                if (str(r, "escape") != null) {
                    oneByte(str(r, "escape"), "escape");
                }
            }
            case "FIXED" -> {
                Integer len = integer(r, "len");
                if (len == null || len <= 0) {
                    throw new RuleException("FIXED는 len(1 이상)이 필요합니다.");
                }
            }
            case "LENFIELD" -> {
                Integer offset = integer(r, "offset");
                if (offset == null) {
                    throw new RuleException("LENFIELD는 offset이 필요합니다.");
                }
                Integer size = integer(r, "size");
                int sz = size == null ? 1 : size;
                if (offset < 0) {
                    throw new RuleException("offset은 0 이상이어야 합니다.");
                }
                if (sz != 1 && sz != 2 && sz != 4) {
                    throw new RuleException("size는 1, 2, 4 중 하나여야 합니다.");
                }
                String endian = upper(str(r, "endian"), "BE");
                if (!endian.equals("BE") && !endian.equals("LE")) {
                    throw new RuleException("endian은 BE 또는 LE입니다.");
                }
                integer(r, "adjust");
                bool(r, "includesHeader");
            }
            default -> throw new RuleException("알 수 없는 frame kind: " + kind);
        }
    }

    private static void checksum(Map<String, Object> r) {
        Object c = r.get("checksum");
        if (c == null) {
            return;
        }
        if (!(c instanceof Map<?, ?>)) {
            throw new RuleException("checksum은 객체여야 합니다.");
        }
        @SuppressWarnings("unchecked")
        Map<String, Object> m = (Map<String, Object>) c;
        String type = upper(str(m, "type"), "NONE");
        if (!Set.of("NONE", "SUM8", "XOR8", "CRC16_MODBUS").contains(type)) {
            throw new RuleException("알 수 없는 checksum type: " + type);
        }
        Integer from = integer(m, "from");
        int f = from == null ? 0 : from;
        if (f < 0) {
            throw new RuleException("checksum.from은 0 이상이어야 합니다.");
        }
        Integer to = integer(m, "to");
        int t = to == null ? 0 : to;
        if (t > 0 && t < f) {
            throw new RuleException("checksum.to는 from 이상이어야 합니다 (양수일 때).");
        }
    }

    // ===== PARSE_RULE =====

    public static boolean isJsonRule(String text) {
        return text != null && text.trim().startsWith("{");
    }

    /** PARSE_RULE JSON v1 (TEXT · INFO · BINARY) */
    public static void validateParseRule(String text) {
        if (!isJsonRule(text)) {
            throw new RuleException("해석 규칙은 JSON v1이어야 합니다 (예: {\"v\":1,\"kind\":\"TEXT\",...}).");
        }
        Map<String, Object> r = root(text);
        String kind = kind(r);
        String trim = str(r, "trim");
        if (trim != null && trim.length() != 2) {
            throw new RuleException("trim은 앞·뒤 2글자입니다 (예: \"{}\").");
        }
        switch (kind) {
            case "TEXT" -> {
                Integer count = integer(r, "count");
                if (count != null && count < 0) {
                    throw new RuleException("count는 0 이상이어야 합니다.");
                }
                sep(str(r, "sep"));
                String map = upper(str(r, "map"), "CHANNELS");
                if (!map.equals("CHANNELS") && !map.equals("SAMPLES")) {
                    throw new RuleException("알 수 없는 map: " + map);
                }
            }
            case "INFO" -> {
                List<String> fields = strArray(r, "fields");
                if (fields.isEmpty()) {
                    throw new RuleException("INFO는 fields가 필요합니다.");
                }
                sep(str(r, "sep") == null ? "COMMA" : str(r, "sep"));
            }
            case "BINARY" -> binaryFields(r);
            default -> throw new RuleException("알 수 없는 parse kind: " + kind);
        }
    }

    private static void binaryFields(Map<String, Object> r) {
        Object arr = r.get("fields");
        if (!(arr instanceof List<?> list) || list.isEmpty()) {
            throw new RuleException("BINARY는 fields 배열이 필요합니다.");
        }
        Set<String> keys = new HashSet<>();
        Set<String> types = Set.of("U8", "I8", "U16", "I16", "U32", "I32", "F32", "F64");
        for (Object o : list) {
            if (!(o instanceof Map<?, ?>)) {
                throw new RuleException("BINARY 필드에 key가 필요합니다.");
            }
            @SuppressWarnings("unchecked")
            Map<String, Object> f = (Map<String, Object>) o;
            String key = str(f, "key");
            if (key == null) {
                throw new RuleException("BINARY 필드에 key가 필요합니다.");
            }
            if (!keys.add(key)) {
                throw new RuleException("BINARY 필드 key 중복: " + key);
            }
            Integer offset = integer(f, "offset");
            if (offset == null) {
                throw new RuleException(key + ": offset이 필요합니다.");
            }
            if (offset < 0) {
                throw new RuleException(key + ": offset은 0 이상이어야 합니다.");
            }
            String type = str(f, "type");
            if (type == null) {
                throw new RuleException(key + ": type이 필요합니다.");
            }
            if (!types.contains(type.toUpperCase(Locale.ROOT))) {
                throw new RuleException(key + ": 알 수 없는 type " + type.toUpperCase(Locale.ROOT));
            }
            String endian = upper(str(f, "endian"), "LE");
            if (!endian.equals("BE") && !endian.equals("LE")) {
                throw new RuleException(key + ": endian은 BE 또는 LE입니다.");
            }
            number(f, "scale");
            number(f, "valueOffset");
        }
    }

    // ===== EXPECT_RULE =====

    /** {"startsWith":"..."} 또는 {"regex":"..."} — 키 1개, 빈 값 불가, regex 컴파일 가능 */
    public static void validateExpectRule(String text) {
        Object o;
        try {
            o = MiniJson.parse(text == null ? "" : text.trim());
        } catch (IllegalArgumentException e) {
            throw new RuleException("응답 판정 JSON 형식 오류: " + e.getMessage());
        }
        if (!(o instanceof Map<?, ?> m) || m.size() != 1) {
            throw new RuleException("응답 판정은 키 1개 객체입니다: {\"startsWith\":\"..\"} 또는 {\"regex\":\"..\"}");
        }
        Map.Entry<?, ?> e = m.entrySet().iterator().next();
        String key = String.valueOf(e.getKey());
        if (!key.equals("startsWith") && !key.equals("regex")) {
            throw new RuleException("응답 판정 키는 startsWith 또는 regex 입니다: " + key);
        }
        if (!(e.getValue() instanceof String v) || v.isEmpty()) {
            throw new RuleException(key + ": 빈 값이 아닌 문자열이어야 합니다.");
        }
        if (key.equals("regex")) {
            try {
                Pattern.compile(v);
            } catch (PatternSyntaxException ex) {
                throw new RuleException("regex 오류: " + ex.getDescription());
            }
        }
    }

    // ===== 공통 =====

    private static Map<String, Object> root(String text) {
        Object o;
        try {
            o = MiniJson.parse(text == null ? "" : text.trim());
        } catch (IllegalArgumentException e) {
            throw new RuleException("규칙 JSON 형식 오류: " + e.getMessage());
        }
        if (!(o instanceof Map<?, ?>)) {
            throw new RuleException("규칙은 JSON 객체여야 합니다.");
        }
        @SuppressWarnings("unchecked")
        Map<String, Object> r = (Map<String, Object>) o;
        Object v = r.get("v");
        int ver = v instanceof BigDecimal d && isInt(d) ? d.intValueExact() : 0;
        if (ver != 1) {
            throw new RuleException("지원하지 않는 규칙 버전입니다: v=" + ver);
        }
        return r;
    }

    private static String kind(Map<String, Object> r) {
        String k = str(r, "kind");
        if (k == null) {
            throw new RuleException("kind가 필요합니다.");
        }
        return k.toUpperCase(Locale.ROOT);
    }

    private static void sep(String text) {
        String s = upper(text, "SPACE");
        if (!s.equals("SPACE") && !s.equals("COMMA") && !s.equals("TAB")) {
            throw new RuleException("알 수 없는 sep: " + s);
        }
    }

    private static void bytes(String expr, String name) {
        int n;
        try {
            n = expressionLength(expr);
        } catch (RuleException e) {
            throw new RuleException(name + ": " + e.getMessage());
        }
        if (n < 1) {
            throw new RuleException(name + ": 1바이트 이상이어야 합니다.");
        }
    }

    private static void oneByte(String expr, String name) {
        bytes(expr, name);
        if (expressionLength(expr) != 1) {
            throw new RuleException(name + ": 1바이트여야 합니다.");
        }
    }

    /** Desktop Str(): 문자열이 아니면 없는 것으로 본다 */
    private static String str(Map<String, Object> m, String name) {
        return m.get(name) instanceof String s ? s : null;
    }

    private static String upper(String v, String fallback) {
        return (v == null ? fallback : v).toUpperCase(Locale.ROOT);
    }

    /** Desktop Int(): 없음·null 이면 null, 정수(int 범위, 소수·지수 표기 없음)가 아니면 오류 */
    private static Integer integer(Map<String, Object> m, String name) {
        if (!m.containsKey(name) || m.get(name) == null) {
            return null;
        }
        if (m.get(name) instanceof BigDecimal d && isInt(d)) {
            return d.intValueExact();
        }
        throw new RuleException(name + ": 정수여야 합니다.");
    }

    private static boolean isInt(BigDecimal d) {
        return d.scale() == 0 && d.compareTo(BigDecimal.valueOf(Integer.MIN_VALUE)) >= 0
                && d.compareTo(BigDecimal.valueOf(Integer.MAX_VALUE)) <= 0;
    }

    private static void number(Map<String, Object> m, String name) {
        if (m.containsKey(name) && m.get(name) != null && !(m.get(name) instanceof BigDecimal)) {
            throw new RuleException(name + ": 숫자여야 합니다.");
        }
    }

    private static void bool(Map<String, Object> m, String name) {
        if (m.containsKey(name) && m.get(name) != null && !(m.get(name) instanceof Boolean)) {
            throw new RuleException(name + ": true/false여야 합니다.");
        }
    }

    private static List<String> strArray(Map<String, Object> m, String name) {
        if (!(m.get(name) instanceof List<?> list)) {
            return List.of();
        }
        Set<String> seen = new HashSet<>();
        for (Object x : list) {
            if (!(x instanceof String s) || s.isEmpty()) {
                throw new RuleException(name + ": 빈 값이 아닌 문자열 배열이어야 합니다.");
            }
            if (!seen.add(s)) {
                throw new RuleException(name + ": 중복 항목");
            }
        }
        @SuppressWarnings("unchecked")
        List<String> r = (List<String>) list;
        return r;
    }
}
