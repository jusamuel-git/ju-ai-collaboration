package com.asdp.juprovider.action;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.mock;

import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

import org.junit.jupiter.api.Test;

import com.asdp.juprovider.core.action.ActionHandler;
import com.asdp.juprovider.core.action.contract.ActionInputValidator;
import com.asdp.juprovider.core.action.contract.ActionOutputNormalizer;
import com.asdp.juprovider.core.action.contract.ListOutput;
import com.asdp.juprovider.core.action.contract.OutputKind;
import com.asdp.juprovider.core.action.exception.ActionValidationException;
import com.asdp.juprovider.core.protocol.ProtocolI18nKeys;
import com.asdp.juprovider.core.protocol.action.*;
import com.asdp.juprovider.core.protocol.service.ProtocolService;

class ProtocolContractTest {

    private final ProtocolService service = mock(ProtocolService.class);

    private final List<ActionHandler> handlers = List.of(
            new ProtocolGroupSearchAction(service), new ProtocolGroupGetAction(service),
            new ProtocolGroupCreateAction(service), new ProtocolGroupUpdateAction(service),
            new ProtocolGroupDeleteAction(service), new ProtocolSearchAction(service),
            new ProtocolGetAction(service), new ProtocolCreateAction(service),
            new ProtocolUpdateAction(service), new ProtocolDeleteAction(service));

    private final ActionInputValidator validator = new ActionInputValidator(
            grp -> "PROT".equals(grp) ? Set.of("PROT0000", "PROT0003") : Set.of("YENO0000", "YENO0001", "YENO0002"));

    @Test
    void allTenHandlersDeclareVersion1Contracts() {
        Set<String> ids = handlers.stream().map(ActionHandler::getHandlerId).collect(Collectors.toSet());
        assertEquals(Set.of(
                "PROTOCOL.GRP_SEARCH", "PROTOCOL.GRP_GET", "PROTOCOL.GRP_CREATE", "PROTOCOL.GRP_UPDATE", "PROTOCOL.GRP_DELETE",
                "PROTOCOL.SEARCH", "PROTOCOL.GET", "PROTOCOL.CREATE", "PROTOCOL.UPDATE", "PROTOCOL.DELETE"), ids);
        for (ActionHandler h : handlers) {
            assertEquals(1, h.contract().contractVersion(), h.getHandlerId());
            assertTrue(!h.contract().output().isEmpty(), h.getHandlerId());
        }
        assertEquals(OutputKind.LIST, ProtocolContracts.GRP_SEARCH.outputKind());
        assertEquals(OutputKind.RECORD, ProtocolContracts.GET.outputKind());
        assertEquals(OutputKind.KEY, ProtocolContracts.GRP_DELETE.outputKind());
    }

    @Test
    void createInputContract() {
        validator.validate(ProtocolContracts.CREATE, Map.of(
                "ptlGrpCd", "SMK", "ptlCd", "SMK0001", "ptlType", "PROT0003", "ptlNm", "n",
                "packets", List.of(Map.of("packetSeq", 1, "direction", "TX"))));
        ActionValidationException e = assertThrows(ActionValidationException.class,
                () -> validator.validate(ProtocolContracts.GRP_CREATE, Map.of("ptlGrpCd", "ABCDEFGHIJKLMNOPQ", "ptlGrpNm", "n")));
        assertEquals("MAX_LENGTH", e.getErrors().get(0).code());
    }

    @Test
    void deterministicI18nKeys() {
        assertEquals("PROTOCOL_GROUP.GTEC.NM", ProtocolI18nKeys.groupName("GTEC"));
        assertEquals("PROTOCOL_GROUP.GTEC.DESC", ProtocolI18nKeys.groupDesc("GTEC"));
        assertEquals("PROTOCOL.GTEC.GTEC0001.NM", ProtocolI18nKeys.protocolName("GTEC", "GTEC0001"));
        assertEquals("PROTOCOL.GTEC.GTEC0001.DESC", ProtocolI18nKeys.protocolDesc("GTEC", "GTEC0001"));
    }

    @Test
    @SuppressWarnings("unchecked")
    void outputIsNormalizedToDeclaredFieldsInOrder() {
        java.util.Map<String, Object> raw = new java.util.HashMap<>();
        raw.put("ptlCd", "GTEC0001");
        raw.put("ptlGrpCd", "GTEC");
        raw.put("internal", "x");
        raw.put("packets", List.of(new java.util.HashMap<>(Map.of("direction", "TX", "packetSeq", 1, "secret", 1))));
        Map<String, Object> out = (Map<String, Object>) ActionOutputNormalizer.normalize(ProtocolContracts.GET, raw);
        assertEquals(List.of("ptlGrpCd", "ptlCd", "ptlType", "ptlTypeNm", "ptlLen", "ptlNm", "ptlDesc", "useYn",
                "ptlVal", "ptlNmKey", "ptlDescKey", "ptlRoles", "ptlAction", "expectRule", "idempotentYn", "packets"),
                List.copyOf(out.keySet()));
        assertTrue(out.containsKey("ptlLen") && out.get("ptlLen") == null);
        Map<String, Object> packet = (Map<String, Object>) ((List<?>) out.get("packets")).get(0);
        assertTrue(!packet.containsKey("secret") && packet.containsKey("dataPosition"));

        ListOutput<?> list = (ListOutput<?>) ActionOutputNormalizer.normalize(
                ProtocolContracts.GRP_SEARCH, ListOutput.of(List.of(Map.of("ptlGrpCd", "A"))));
        assertEquals(1, list.total());
        assertEquals(9, ((Map<?, ?>) list.items().get(0)).size());
    }

    /** C5c: 수집 설정·역할은 선택 입력 (기존 v1 호출 그대로 통과), 상세 출력에 추가 */
    @Test
    void c5cOptionalCollectFields() {
        ActionInputValidator v = new ActionInputValidator(grp -> switch (grp) {
            case "PROT" -> Set.of("PROT0000", "PROT0002");
            case "PACT" -> Set.of("PACT0000", "PACT0003");
            default -> Set.of("YENO0000", "YENO0001", "YENO0002");
        });
        v.validate(ProtocolContracts.GRP_CREATE, Map.of("ptlGrpCd", "SMK", "ptlGrpNm", "n"));
        v.validate(ProtocolContracts.GRP_CREATE, Map.of("ptlGrpCd", "SMK", "ptlGrpNm", "n",
                "frameRule", "{\"v\":1,\"kind\":\"DELIM\"}", "cmdGapMs", 200, "initRoutine", "SMK0000", "initDelayMs", 500));
        v.validate(ProtocolContracts.GRP_UPDATE, Map.of("ptlGrpCd", "SMK", "cmdGapMs", 0));
        v.validate(ProtocolContracts.UPDATE, Map.of("ptlGrpCd", "SMK", "ptlCd", "SMK0001",
                "ptlRoles", "PROL0001", "ptlAction", "PACT0003", "expectRule", "{\"startsWith\":\"{\"}", "idempotentYn", "YENO0001"));
        ActionValidationException e = assertThrows(ActionValidationException.class,
                () -> v.validate(ProtocolContracts.UPDATE, Map.of("ptlGrpCd", "SMK", "ptlCd", "SMK0001", "ptlAction", "PACT9999")));
        assertEquals("INVALID_CODE", e.getErrors().get(0).code());

        @SuppressWarnings("unchecked")
        Map<String, Object> group = (Map<String, Object>) ActionOutputNormalizer.normalize(ProtocolContracts.GRP_GET,
                new java.util.HashMap<>(Map.of("ptlGrpCd", "GTEC", "cmdGapMs", 200)));
        assertTrue(group.containsKey("frameRule") && group.containsKey("initRoutine") && group.containsKey("initDelayMs"));
        assertEquals(200, ((Number) group.get("cmdGapMs")).intValue());
    }
}
