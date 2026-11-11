package com.asdp.juprovider.core.protocolsync;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.junit.jupiter.api.Test;

import com.asdp.juprovider.core.protocolsync.dao.ProtocolSyncDao;
import com.asdp.juprovider.core.protocolsync.dto.DataChannelMapSync;
import com.asdp.juprovider.core.protocolsync.dto.DataTagSync;
import com.asdp.juprovider.core.protocolsync.dto.ProtocolGroupSync;
import com.asdp.juprovider.core.protocolsync.dto.SyncResult;
import com.asdp.juprovider.core.protocolsync.service.ProtocolSyncService;

/** C4 내려받기 조립·revision (DB 없이 가짜 DAO) */
class ProtocolSyncServiceTest {

    private static Map<String, Object> row(Object... kv) {
        Map<String, Object> m = new HashMap<>();
        for (int i = 0; i < kv.length; i += 2) {
            m.put((String) kv[i], kv[i + 1]);
        }
        return m;
    }

    private static final class FakeDao implements ProtocolSyncDao {
        final List<Map<String, Object>> groups = new ArrayList<>();
        final List<Map<String, Object>> protocols = new ArrayList<>();
        final List<Map<String, Object>> packets = new ArrayList<>();
        final List<Map<String, Object>> tags = new ArrayList<>();
        final List<Map<String, Object>> maps = new ArrayList<>();
        final Map<String, List<Map<String, Object>>> codes = new HashMap<>();
        String lastGroupArg = "unset";
        String lastDevArg = "unset";

        @Override
        public List<Map<String, Object>> selectSyncGroups(String ptlGrpCd) {
            lastGroupArg = ptlGrpCd;
            return groups.stream().filter(r -> ptlGrpCd == null || ptlGrpCd.equals(r.get("ptlGrpCd"))).toList();
        }

        @Override
        public List<Map<String, Object>> selectSyncProtocols(String ptlGrpCd) {
            return protocols.stream().filter(r -> ptlGrpCd == null || ptlGrpCd.equals(r.get("ptlGrpCd"))).toList();
        }

        @Override
        public List<Map<String, Object>> selectSyncPackets(String ptlGrpCd) {
            return packets.stream().filter(r -> ptlGrpCd == null || ptlGrpCd.equals(r.get("ptlGrpCd"))).toList();
        }

        @Override
        public List<Map<String, Object>> selectSyncDataTags(String devCd) {
            lastDevArg = devCd;
            return tags.stream().filter(r -> devCd == null || devCd.equals(r.get("devCd"))).toList();
        }

        @Override
        public List<Map<String, Object>> selectCodeValues(String grpCd) {
            return codes.getOrDefault(grpCd, List.of());
        }

        @Override
        public List<Map<String, Object>> selectSyncDataMap(String devCd) {
            lastDevArg = devCd;
            return maps.stream().filter(r -> devCd == null || devCd.equals(r.get("devCd"))).toList();
        }
    }

    private static FakeDao gtec() {
        FakeDao dao = new FakeDao();
        dao.groups.add(row("ptlGrpCd", "GTEC", "ptlGrpNm", "그린테크", "pollingIntval", 1000, "timeoutMs", 3000, "retryCnt", 3, "sortOrd", 0));
        dao.groups.add(row("ptlGrpCd", "OTHER", "pollingIntval", 500, "timeoutMs", 1000, "retryCnt", 1, "sortOrd", 1));
        dao.protocols.add(row("ptlGrpCd", "GTEC", "ptlCd", "GTEC0000", "ptlType", "PROT0000", "ptlVal", "S{TEST}[CR][LF]", "ptlNm", "장치확인"));
        dao.protocols.add(row("ptlGrpCd", "GTEC", "ptlCd", "GTEC0001", "ptlType", "PROT0000", "ptlVal", "S{10,3}", "ptlLen", 7L));
        dao.packets.add(row("ptlGrpCd", "GTEC", "ptlCd", "GTEC0000", "packetSeq", 1, "direction", "TX", "packetExpr", "S{TEST}[CR][LF]", "dataCount", 0));
        dao.packets.add(row("ptlGrpCd", "GTEC", "ptlCd", "GTEC0000", "packetSeq", 2, "direction", "RX", "packetExpr", "{OK}[CR][LF]", "dataCount", 0));
        dao.tags.add(row("devCd", "SDEV_GTEC01", "datGrCd", "DG_GTEC01", "datCd", "GTEC-DATA-01", "datIdx", 1, "datType", "DATA0001",
                "datUnit", "", "tagId", "CH1", "datNm", "GTEC Analog CH1", "datMin", new BigDecimal("0.0000000000"), "sortOrd", 1));
        dao.tags.add(row("devCd", "VDEV_GTEC01", "datGrCd", "DG_GTECV01", "datCd", "VGTEC-DATA-01", "datIdx", 1, "tagId", "CH1"));
        return dao;
    }

    @Test
    void groupsNestProtocolsAndPacketsInOrder() {
        SyncResult<ProtocolGroupSync> r = new ProtocolSyncService(gtec()).getProtocolGroups(null);

        assertEquals(2, r.items().size());
        ProtocolGroupSync g = r.items().get(0);
        assertEquals("GTEC", g.ptlGrpCd());
        assertEquals(3000, g.timeoutMs());
        assertEquals(2, g.protocols().size());
        assertEquals("GTEC0000", g.protocols().get(0).ptlCd());
        assertEquals(2, g.protocols().get(0).packets().size());
        assertEquals("TX", g.protocols().get(0).packets().get(0).direction());
        assertEquals(7, g.protocols().get(1).ptlLen());
        assertTrue(g.protocols().get(1).packets().isEmpty());
        assertTrue(r.items().get(1).protocols().isEmpty());
        assertTrue(r.removed().isEmpty());
        assertEquals(64, r.revision().length());
    }

    @Test
    void singleGroupFilterAndUnknownGroupIsEmpty() {
        FakeDao dao = gtec();
        ProtocolSyncService service = new ProtocolSyncService(dao);

        assertEquals(1, service.getProtocolGroups("GTEC").items().size());
        assertEquals("GTEC", dao.lastGroupArg);
        assertTrue(service.getProtocolGroups("NONE").items().isEmpty());
    }

    @Test
    void revisionIsStableAndChangesWithContent() {
        FakeDao dao = gtec();
        ProtocolSyncService service = new ProtocolSyncService(dao);
        String first = service.getProtocolGroups(null).revision();

        assertEquals(first, service.getProtocolGroups(null).revision());
        dao.groups.get(0).put("timeoutMs", 2000);
        assertNotEquals(first, service.getProtocolGroups(null).revision());
    }

    @Test
    void dataTagsByDevice() {
        FakeDao dao = gtec();
        SyncResult<DataTagSync> r = new ProtocolSyncService(dao).getDataTags("SDEV_GTEC01");

        assertEquals("SDEV_GTEC01", dao.lastDevArg);
        assertEquals(1, r.items().size());
        DataTagSync t = r.items().get(0);
        assertEquals("CH1", t.tagId());
        assertEquals(1, t.datIdx());
        assertEquals(0, BigDecimal.ZERO.compareTo(t.datMin()));
        assertNull(t.datMax());
        assertEquals(2, new ProtocolSyncService(dao).getDataTags(null).items().size());
    }

    @Test
    void upperCaseAliasesFromDriverAreRead() {
        FakeDao dao = new FakeDao();
        dao.groups.add(row("PTLGRPCD", "GTEC", "TIMEOUTMS", 1500));
        ProtocolGroupSync g = new ProtocolSyncService(dao).getProtocolGroups(null).items().get(0);
        assertEquals("GTEC", g.ptlGrpCd());
        assertEquals(1500, g.timeoutMs());
        assertEquals(3, g.retryCnt());
    }

    /** C5c: 그룹 수집 설정·프로토콜 역할 필드, 미설정 기본값 */
    @Test
    void collectSettingsAndRoles() {
        FakeDao dao = gtec();
        dao.codes.put("PROL", List.of(row("comCd", "PROL0001", "comVal", "INFO"), row("comCd", "PROL0003", "comVal", "DATA")));
        dao.codes.put("PACT", List.of(row("comCd", "PACT0003", "comVal", "STOP")));
        dao.groups.get(0).putAll(row("frameRule", "{\"v\":1,\"kind\":\"DELIM\"}", "cmdGapMs", 200,
                "initRoutine", "GTEC0001,GTEC0000", "initDelayMs", 500));
        dao.protocols.get(0).putAll(row("ptlRoles", "PROL0001,PROL0003", "ptlAction", "PACT0003",
                "expectRule", "{\"startsWith\":\"{OK\"}", "idempotentYn", "YENO0001"));
        dao.protocols.get(1).put("idempotentYn", "YENO0002");

        List<ProtocolGroupSync> items = new ProtocolSyncService(dao).getProtocolGroups(null).items();
        ProtocolGroupSync g = items.get(0);
        assertEquals("{\"v\":1,\"kind\":\"DELIM\"}", g.frameRule());
        assertEquals(200, g.cmdGapMs());
        assertEquals(List.of("GTEC0001", "GTEC0000"), g.initRoutine());
        assertEquals(500, g.initDelayMs());
        assertEquals(List.of("INFO", "DATA"), g.protocols().get(0).roles());
        assertEquals("STOP", g.protocols().get(0).action());
        assertEquals("{\"startsWith\":\"{OK\"}", g.protocols().get(0).expect());
        assertEquals(Boolean.TRUE, g.protocols().get(0).idempotent());
        assertEquals(Boolean.FALSE, g.protocols().get(1).idempotent());
        assertTrue(g.protocols().get(1).roles().isEmpty());
        assertNull(g.protocols().get(1).action());

        ProtocolGroupSync other = items.get(1);
        assertNull(other.frameRule());
        assertEquals(0, other.cmdGapMs());
        assertTrue(other.initRoutine().isEmpty());
        assertEquals(500, other.initDelayMs());
    }

    /** C5c: 채널 매핑 내려받기 */
    @Test
    void dataMap() {
        FakeDao dao = gtec();
        dao.maps.add(row("devCd", "SDEV_GTEC01", "channelKey", "1", "datGrCd", "DG_GTEC01", "datCd", "GTEC-DATA-01",
                "datIdx", 1, "scale", 1.0d, "offsetVal", 0.0d, "sortOrd", 1));
        dao.maps.add(row("devCd", "SDEV_GTEC01", "channelKey", "2", "ptlCd", "GTEC0400", "datGrCd", "DG_GTEC01",
                "datCd", "GTEC-DATA-02", "datIdx", 2, "scale", 10.0d, "offsetVal", -0.5d, "sortOrd", 2));
        dao.maps.add(row("devCd", "OTHER", "channelKey", "1", "datGrCd", "G", "datCd", "D", "datIdx", 1));

        ProtocolSyncService service = new ProtocolSyncService(dao);
        SyncResult<DataChannelMapSync> r = service.getDataMap("SDEV_GTEC01");
        assertEquals("SDEV_GTEC01", dao.lastDevArg);
        assertEquals(2, r.items().size());
        DataChannelMapSync m = r.items().get(1);
        assertEquals("2", m.channelKey());
        assertEquals("GTEC0400", m.ptlCd());
        assertEquals(10.0, m.scale());
        assertEquals(-0.5, m.offset());
        assertNull(r.items().get(0).ptlCd());
        assertEquals(64, r.revision().length());
        assertEquals(r.revision(), service.getDataMap("SDEV_GTEC01").revision());
        assertEquals(3, service.getDataMap(null).items().size());
        DataChannelMapSync d = service.getDataMap("OTHER").items().get(0);
        assertEquals(1.0, d.scale());
        assertEquals(0.0, d.offset());
        assertTrue(service.getDataMap("NONE").items().isEmpty());
    }
}
