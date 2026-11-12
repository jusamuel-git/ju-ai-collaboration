package com.asdp.juprovider.core.protocol;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assertions.fail;

import java.nio.file.Files;
import java.nio.file.Path;

import org.junit.jupiter.api.Test;

import com.asdp.juprovider.core.protocol.rule.ProtocolRules;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

/** C5c 규칙 검사 — Desktop 과 같은 공통 벡터 + 응답 판정 */
class ProtocolRulesTest {

    /** Desktop 테스트(RuleVectorTests)와 같은 파일 */
    private static final Path VECTORS = Path.of("..", "desktop", "tests", "juprovider.tests.protocol", "TestData", "rule_vectors.json");

    private interface Check {
        void run(String value);
    }

    private static int verify(JsonNode list, String key, Check check) {
        int n = 0;
        for (JsonNode v : list) {
            String value = v.get(key).asText();
            boolean ok = v.get("ok").asBoolean();
            try {
                check.run(value);
                if (!ok) {
                    fail("통과하면 안 됨: " + value);
                }
            } catch (ProtocolRules.RuleException e) {
                if (ok) {
                    fail("통과해야 함: " + value + " → " + e.getMessage());
                }
            }
            n++;
        }
        return n;
    }

    @Test
    void sharedVectorsMatchDesktop() throws Exception {
        assertTrue(Files.exists(VECTORS), VECTORS.toAbsolutePath().toString());
        JsonNode root = new ObjectMapper().readTree(Files.readString(VECTORS));
        int n = verify(root.get("frame"), "rule", ProtocolRules::validateFrameRule)
                + verify(root.get("parse"), "rule", ProtocolRules::validateParseRule)
                + verify(root.get("expression"), "expr", ProtocolRules::validateExpression);
        assertTrue(n >= 40, "벡터 수 " + n);
    }

    /** C5d: 응답 판정 regex — Java 판정이 벡터의 java 값과 같고, 일치 결과는 .NET 과 같아야 한다 */
    @Test
    void expectAndMatchVectors() throws Exception {
        JsonNode root = new ObjectMapper().readTree(Files.readString(VECTORS));
        int n = 0;
        for (JsonNode v : root.get("expect")) {
            String rule = v.get("rule").asText();
            boolean ok;
            try {
                ProtocolRules.validateExpectRule(rule);
                ok = true;
            } catch (ProtocolRules.RuleException e) {
                ok = false;
            }
            assertEquals(v.get("java").asBoolean(), ok, rule);
            // 서버가 허용하는 regex 는 Desktop(.NET)에서도 해석 가능해야 한다 (D3)
            assertFalse(v.get("java").asBoolean() && !v.get("dotnet").asBoolean(), "서버 허용·Desktop 불가: " + rule);
            n++;
        }
        for (JsonNode v : root.get("match")) {
            boolean m = java.util.regex.Pattern.compile(v.get("regex").asText()).matcher(v.get("input").asText()).find();
            boolean expected = v.has("match") ? v.get("match").asBoolean() : v.get("java").asBoolean();
            assertEquals(expected, m, v.get("regex").asText() + " / " + v.get("input").asText());
            n++;
        }
        assertTrue(n >= 20, "벡터 수 " + n);
    }

    /** D3: Java 에서만 되거나 의미가 다른 문법은 저장 거부, 공통 문법은 허용 */
    @Test
    void javaOnlyRegexRejected() {
        for (String bad : new String[] { "a*+", "a?+", "a{1,2}+", "\\Qx\\E", "\\H", "\\V", "\\X", "\\N{LATIN SMALL LETTER A}",
                "\\p{javaLowerCase}", "[ab&&b]", "[a[b]]", "(?u)a", "(?iU:a)" }) {
            assertThrows(ProtocolRules.RuleException.class,
                    () -> ProtocolRules.validateExpectRule("{\"regex\":\"" + bad.replace("\\", "\\\\") + "\"}"), bad);
        }
        for (String ok : new String[] { "^[{][A-Za-z]", "a+?", "a*?b", "(?i)ok", "(?s:.)", "[\\[\\]]", "\\p{L}", "[^}]+", "x{3}", "(?<n>a)\\k<n>" }) {
            assertDoesNotThrow(() -> ProtocolRules.validateExpectRule("{\"regex\":\"" + ok.replace("\\", "\\\\") + "\"}"), ok);
        }
    }

    @Test
    void gtecVerifiedValuesPass() {
        assertDoesNotThrow(() -> ProtocolRules.validateFrameRule("{\"v\":1,\"kind\":\"DELIM\",\"start\":\"{\",\"end\":\"[CR][LF]\",\"maxLen\":512}"));
        assertDoesNotThrow(() -> ProtocolRules.validateParseRule("{\"v\":1,\"kind\":\"TEXT\",\"trim\":\"{}\",\"sep\":\"SPACE\",\"count\":3}"));
        assertDoesNotThrow(() -> ProtocolRules.validateExpectRule("{\"startsWith\":\"{OK\"}"));
        assertDoesNotThrow(() -> ProtocolRules.validateExpectRule("{\"regex\":\"^[{][0-9]{3},[0-9]{3},[0-9]{3},[0-9]{3}[}]$\"}"));
        assertDoesNotThrow(() -> ProtocolRules.validateExpectRule("{\"regex\":\"^\\\\{[A-Za-z]\"}"));
        assertEquals(9, ProtocolRules.expressionLength("S{10,1}[CR][LF]"));
    }

    @Test
    void gtec0000LegacyParseRuleIsNotJson() {
        String legacy = "패킷길이|STX DLE|ETX|ETX DLE";
        assertFalse(ProtocolRules.isJsonRule(legacy));
        assertThrows(ProtocolRules.RuleException.class, () -> ProtocolRules.validateParseRule(legacy));
    }

    @Test
    void expectRuleErrors() {
        for (String bad : new String[] {
                "", "x", "[]", "{}", "{\"startsWith\":\"\"}", "{\"startsWith\":1}", "{\"contains\":\"a\"}",
                "{\"startsWith\":\"a\",\"regex\":\"b\"}", "{\"regex\":\"[\"}" }) {
            assertThrows(ProtocolRules.RuleException.class, () -> ProtocolRules.validateExpectRule(bad), bad);
        }
    }
}
