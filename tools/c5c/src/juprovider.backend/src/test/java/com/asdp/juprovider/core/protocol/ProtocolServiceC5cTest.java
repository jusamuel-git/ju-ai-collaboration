package com.asdp.juprovider.core.protocol;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import com.asdp.juprovider.core.action.contract.ActionContract;
import com.asdp.juprovider.core.action.contract.ActionFieldError;
import com.asdp.juprovider.core.action.contract.ActionInput;
import com.asdp.juprovider.core.action.contract.ActionInputValidator;
import com.asdp.juprovider.core.action.dao.ActionCodeDao;
import com.asdp.juprovider.core.action.exception.ActionConflictException;
import com.asdp.juprovider.core.action.exception.ActionValidationException;
import com.asdp.juprovider.core.protocol.action.ProtocolContracts;
import com.asdp.juprovider.core.protocol.dao.ProtocolDao;
import com.asdp.juprovider.core.protocol.service.ProtocolService;

/** C5c Protocol CRUD 저장 검사 (DB 없이 mock DAO) */
class ProtocolServiceC5cTest {

    private static final String LEGACY_PARSE = "패킷길이|STX DLE|ETX|ETX DLE";

    private static final String TEXT_PARSE = "{\"v\":1,\"kind\":\"TEXT\",\"trim\":\"{}\",\"sep\":\"SPACE\",\"count\":3}";

    private final ActionInputValidator validator = new ActionInputValidator(grp -> switch (grp) {
        case "PROT" -> Set.of("PROT0000", "PROT0001", "PROT0002", "PROT0003");
        case "PACT" -> Set.of("PACT0000", "PACT0001", "PACT0002", "PACT0003");
        default -> Set.of("YENO0000", "YENO0001", "YENO0002");
    });

    private ProtocolDao dao;

    private ProtocolService service;

    private static Map<String, Object> m(Object... kv) {
        Map<String, Object> r = new HashMap<>();
        for (int i = 0; i < kv.length; i += 2) {
            r.put((String) kv[i], kv[i + 1]);
        }
        return r;
    }

    private ActionInput in(ActionContract contract, Object... kv) {
        return validator.validate(contract, m(kv));
    }

    @BeforeEach
    void setUp() {
        dao = mock(ProtocolDao.class);
        ActionCodeDao codes = mock(ActionCodeDao.class);
        when(codes.selectActiveCodes("PROL")).thenReturn(List.of("PROL0001", "PROL0002", "PROL0003"));
        service = new ProtocolService(dao, codes);

        when(dao.selectGroupUseYn("GTEC")).thenReturn("YENO0001");
        when(dao.selectProtocolUseYn(eq("GTEC"), anyString())).thenReturn("YENO0001");
        when(dao.selectProtocolUseYn("GTEC", "GTEC9999")).thenReturn(null);
        when(dao.selectGroupInitRoutine("GTEC")).thenReturn("GTEC0301,GTEC0001");
        when(dao.selectProtocolStates("GTEC")).thenReturn(List.of(
                m("ptlCd", "GTEC0000", "ptlType", "PROT0003", "useYn", "YENO0001"),
                m("ptlCd", "GTEC0001", "ptlType", "PROT0003", "useYn", "YENO0001"),
                m("ptlCd", "GTEC0301", "ptlType", "PROT0001", "useYn", "YENO0001"),
                m("ptlCd", "GTEC0400", "ptlType", "PROT0002", "useYn", "YENO0001"),
                m("ptlCd", "GTEC0999", "ptlType", "PROT0001", "useYn", "YENO0002")));
        // GTEC0000: 과거 데이터 (역할 없음, RX 패킷 PARSE_RULE 이 JSON 아님)
        when(dao.selectProtocol(eq("GTEC"), eq("GTEC0000"), anyString())).thenReturn(
                m("ptlGrpCd", "GTEC", "ptlCd", "GTEC0000", "ptlType", "PROT0000", "ptlVal", "S{TEST}[CR][LF]"));
        when(dao.selectPackets("GTEC", "GTEC0000")).thenReturn(List.of(
                m("packetSeq", 1, "direction", "TX", "packetExpr", "S{TEST}[CR][LF]"),
                m("packetSeq", 2, "direction", "RX", "packetExpr", "{OK}[CR][LF]", "parseRule", LEGACY_PARSE)));
        when(dao.selectProtocol(eq("GTEC"), eq("GTEC0400"), anyString())).thenReturn(
                m("ptlGrpCd", "GTEC", "ptlCd", "GTEC0400", "ptlType", "PROT0002", "ptlRoles", "PROL0003"));
        when(dao.selectPackets("GTEC", "GTEC0400")).thenReturn(List.of(
                m("packetSeq", 1, "direction", "RX", "parseRule", TEXT_PARSE)));
        when(dao.selectProtocol(eq("GTEC"), eq("GTEC0001"), anyString())).thenReturn(
                m("ptlGrpCd", "GTEC", "ptlCd", "GTEC0001", "ptlType", "PROT0003", "ptlVal", "S{10,3}[CR][LF]", "ptlRoles", "PROL0001"));
    }

    private static ActionFieldError error(Runnable r) {
        ActionValidationException e = assertThrows(ActionValidationException.class, r::run);
        return e.getErrors().get(0);
    }

    // ----- GTEC0000 과거 데이터 호환 -----

    @Test
    void legacyProtocolNameOnlyUpdatePasses() {
        service.updateProtocol(in(ProtocolContracts.UPDATE, "ptlGrpCd", "GTEC", "ptlCd", "GTEC0000", "ptlNm", "장치확인"));
        verify(dao).updateProtocol(any());
    }

    @Test
    void legacyParseRuleResentUnchangedPasses() {
        service.updateProtocol(in(ProtocolContracts.UPDATE, "ptlGrpCd", "GTEC", "ptlCd", "GTEC0000",
                "ptlVal", "S{TEST}[CR][LF]",
                "packets", List.of(
                        m("packetSeq", 1, "direction", "TX", "packetExpr", "S{TEST}[CR][LF]"),
                        m("packetSeq", 2, "direction", "RX", "packetExpr", "{OK}[CR][LF]", "parseRule", LEGACY_PARSE))));
        verify(dao).deletePackets("GTEC", "GTEC0000");
    }

    @Test
    void changedNonJsonParseRuleRejected() {
        ActionFieldError e = error(() -> service.updateProtocol(in(ProtocolContracts.UPDATE, "ptlGrpCd", "GTEC", "ptlCd", "GTEC0000",
                "packets", List.of(m("packetSeq", 2, "direction", "RX", "parseRule", "패킷길이|STX")))));
        assertEquals("packets[0].parseRule", e.field());
        verify(dao, never()).updateProtocol(any());
    }

    @Test
    void legacyParseRuleMovedToOtherSeqIsChecked() {
        ActionFieldError e = error(() -> service.updateProtocol(in(ProtocolContracts.UPDATE, "ptlGrpCd", "GTEC", "ptlCd", "GTEC0000",
                "packets", List.of(m("packetSeq", 3, "direction", "RX", "parseRule", LEGACY_PARSE)))));
        assertEquals("packets[0].parseRule", e.field());
    }

    // ----- 역할 · 유형 -----

    @Test
    void rolesMustBeProlCodes() {
        ActionFieldError e = error(() -> service.updateProtocol(in(ProtocolContracts.UPDATE, "ptlGrpCd", "GTEC", "ptlCd", "GTEC0001",
                "ptlRoles", "PROL0001,INFO")));
        assertEquals("ptlRoles", e.field());
        assertEquals(ActionFieldError.INVALID_CODE, e.code());
        assertEquals(ActionFieldError.DUPLICATE, error(() -> service.updateProtocol(in(ProtocolContracts.UPDATE,
                "ptlGrpCd", "GTEC", "ptlCd", "GTEC0001", "ptlRoles", "PROL0001,PROL0001"))).code());
    }

    @Test
    void rolesStoredSortedWithCollectFields() {
        service.updateProtocol(in(ProtocolContracts.UPDATE, "ptlGrpCd", "GTEC", "ptlCd", "GTEC0001",
                "ptlRoles", "PROL0002, PROL0001", "ptlAction", "PACT0000", "expectRule", " {\"regex\":\"^[{][A-Za-z]\"} ",
                "idempotentYn", "YENO0002"));
        verify(dao).updateProtocol(argThat(p -> "PROL0001,PROL0002".equals(p.get("ptlRoles"))
                && "PACT0000".equals(p.get("ptlAction"))
                && "{\"regex\":\"^[{][A-Za-z]\"}".equals(p.get("expectRule"))
                && "YENO0002".equals(p.get("idempotentYn"))));
    }

    @Test
    void idempotentMustBeYesOrNo() {
        assertEquals("idempotentYn", error(() -> service.updateProtocol(in(ProtocolContracts.UPDATE,
                "ptlGrpCd", "GTEC", "ptlCd", "GTEC0001", "idempotentYn", "YENO0000"))).field());
    }

    @Test
    void expectRuleChecked() {
        assertEquals("expectRule", error(() -> service.updateProtocol(in(ProtocolContracts.UPDATE,
                "ptlGrpCd", "GTEC", "ptlCd", "GTEC0001", "expectRule", "{\"regex\":\"[\"}"))).field());
    }

    @Test
    void rxStreamNeedsDataRoleAndJsonParseRule() {
        assertEquals("ptlRoles", error(() -> service.createProtocol(in(ProtocolContracts.CREATE,
                "ptlGrpCd", "GTEC", "ptlCd", "GTEC9999", "ptlType", "PROT0002", "ptlNm", "n", "ptlRoles", "PROL0001",
                "packets", List.of(m("packetSeq", 1, "direction", "RX", "parseRule", TEXT_PARSE))))).field());
        assertEquals("packets", error(() -> service.createProtocol(in(ProtocolContracts.CREATE,
                "ptlGrpCd", "GTEC", "ptlCd", "GTEC9999", "ptlType", "PROT0002", "ptlNm", "n", "ptlRoles", "PROL0003"))).field());
        service.createProtocol(in(ProtocolContracts.CREATE,
                "ptlGrpCd", "GTEC", "ptlCd", "GTEC9999", "ptlType", "PROT0002", "ptlNm", "n", "ptlRoles", "PROL0003",
                "packets", List.of(m("packetSeq", 1, "direction", "RX", "parseRule", TEXT_PARSE))));
        verify(dao).insertProtocol(argThat(p -> "PROL0003".equals(p.get("ptlRoles"))));
    }

    @Test
    void rxStreamUpdateUsesExistingPacketsWhenNotSent() {
        service.updateProtocol(in(ProtocolContracts.UPDATE, "ptlGrpCd", "GTEC", "ptlCd", "GTEC0400", "ptlNm", "저속"));
        verify(dao).updateProtocol(any());
    }

    @Test
    void sendProtocolWithRolesNeedsTxExpression() {
        assertEquals("ptlVal", error(() -> service.createProtocol(in(ProtocolContracts.CREATE,
                "ptlGrpCd", "GTEC", "ptlCd", "GTEC9999", "ptlType", "PROT0001", "ptlNm", "n", "ptlRoles", "PROL0002"))).field());
        // 역할 없음(v1 호출) → 연계 검사 없음
        service.createProtocol(in(ProtocolContracts.CREATE,
                "ptlGrpCd", "GTEC", "ptlCd", "GTEC9999", "ptlType", "PROT0001", "ptlNm", "n"));
    }

    @Test
    void routineProtocolCannotBecomeRxStream() {
        assertEquals("ptlType", error(() -> service.updateProtocol(in(ProtocolContracts.UPDATE,
                "ptlGrpCd", "GTEC", "ptlCd", "GTEC0001", "ptlType", "PROT0002", "ptlRoles", "PROL0003",
                "packets", List.of(m("packetSeq", 1, "direction", "RX", "parseRule", TEXT_PARSE))))).field());
    }

    @Test
    void expressionSyntaxChecked() {
        ActionFieldError e = error(() -> service.updateProtocol(in(ProtocolContracts.UPDATE,
                "ptlGrpCd", "GTEC", "ptlCd", "GTEC0001", "ptlVal", "S{10,3}[XYZ]")));
        assertEquals("ptlVal", e.field());
        assertTrue(e.message().contains("[XYZ]"));
        assertEquals("packets[0].packetExpr", error(() -> service.updateProtocol(in(ProtocolContracts.UPDATE,
                "ptlGrpCd", "GTEC", "ptlCd", "GTEC0001",
                "packets", List.of(m("packetSeq", 1, "direction", "TX", "packetExpr", "[CR")))))
                .field());
    }

    // ----- 그룹 -----

    @Test
    void groupFrameRuleAndRoutineChecked() {
        assertEquals("frameRule", error(() -> service.updateGroup(in(ProtocolContracts.GRP_UPDATE,
                "ptlGrpCd", "GTEC", "frameRule", "{\"v\":1,\"kind\":\"SLIP\"}"))).field());
        assertTrue(error(() -> service.updateGroup(in(ProtocolContracts.GRP_UPDATE,
                "ptlGrpCd", "GTEC", "initRoutine", "GTEC0301,GTEC0400"))).message().contains("RX_STREAM"));
        assertTrue(error(() -> service.updateGroup(in(ProtocolContracts.GRP_UPDATE,
                "ptlGrpCd", "GTEC", "initRoutine", "GTEC0301,GTEC0999"))).message().contains("GTEC0999"));
        assertEquals("initRoutine", error(() -> service.updateGroup(in(ProtocolContracts.GRP_UPDATE,
                "ptlGrpCd", "GTEC", "initRoutine", "GTEC0301,,GTEC0001"))).field());
        assertEquals("cmdGapMs", error(() -> service.updateGroup(in(ProtocolContracts.GRP_UPDATE,
                "ptlGrpCd", "GTEC", "cmdGapMs", -1))).field());

        service.updateGroup(in(ProtocolContracts.GRP_UPDATE, "ptlGrpCd", "GTEC",
                "frameRule", "{\"v\":1,\"kind\":\"DELIM\",\"start\":\"{\",\"end\":\"[CR][LF]\",\"maxLen\":512}",
                "cmdGapMs", 200, "initRoutine", " GTEC0301 , GTEC0001 ", "initDelayMs", 500));
        verify(dao).updateGroup(argThat(g -> "GTEC0301,GTEC0001".equals(g.get("initRoutine"))
                && Integer.valueOf(200).equals(g.get("cmdGapMs"))));
    }

    @Test
    void groupCreateDefaults() {
        when(dao.selectGroupUseYn("NEW")).thenReturn(null);
        service.createGroup(in(ProtocolContracts.GRP_CREATE, "ptlGrpCd", "NEW", "ptlGrpNm", "새 그룹"));
        verify(dao).insertGroup(argThat(g -> Integer.valueOf(0).equals(g.get("cmdGapMs"))
                && Integer.valueOf(500).equals(g.get("initDelayMs")) && g.get("frameRule") == null));
        // 새 그룹의 초기화 루틴은 기본 프로토콜만
        assertEquals("initRoutine", error(() -> service.createGroup(in(ProtocolContracts.GRP_CREATE,
                "ptlGrpCd", "NEW", "ptlGrpNm", "n", "initRoutine", "GTEC0001"))).field());
        when(dao.selectGroupUseYn("NEW2")).thenReturn(null);
        service.createGroup(in(ProtocolContracts.GRP_CREATE, "ptlGrpCd", "NEW2", "ptlGrpNm", "n", "initRoutine", "NEW20000"));
    }

    @Test
    void deleteProtocolInRoutineConflicts() {
        assertThrows(ActionConflictException.class, () -> service.deleteProtocol(in(ProtocolContracts.DELETE,
                "ptlGrpCd", "GTEC", "ptlCd", "GTEC0301")));
        verify(dao, never()).softDeleteProtocol(anyString(), anyString());
        service.deleteProtocol(in(ProtocolContracts.DELETE, "ptlGrpCd", "GTEC", "ptlCd", "GTEC0400"));
        verify(dao).softDeleteProtocol("GTEC", "GTEC0400");
    }
}
