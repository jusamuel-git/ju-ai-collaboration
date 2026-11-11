package com.asdp.juprovider.core.protocolsync.service;

import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.springframework.stereotype.Service;

import com.asdp.juprovider.core.protocolsync.dao.ProtocolSyncDao;
import com.asdp.juprovider.core.protocolsync.dto.DataChannelMapSync;
import com.asdp.juprovider.core.protocolsync.dto.DataTagSync;
import com.asdp.juprovider.core.protocolsync.dto.ProtocolGroupSync;
import com.asdp.juprovider.core.protocolsync.dto.ProtocolPacketSync;
import com.asdp.juprovider.core.protocolsync.dto.ProtocolSync;
import com.asdp.juprovider.core.protocolsync.dto.SyncResult;

/**
 * C4 프로토콜·데이터 태그 내려받기 (읽기 전용, DB 변경 없음).
 *
 * 그룹 → 프로토콜 → 패킷을 조회 순서(정렬된 SQL) 그대로 묶는다.
 * revision 은 결과 내용의 SHA-256 이라 같은 데이터면 항상 같다.
 * C5c: 그룹 수집 설정·프로토콜 역할 필드 추가(필드 추가만 → revision 값은 C4 와 다름), 채널 매핑(data-map) 추가.
 */
@Service
public class ProtocolSyncService {

    private final ProtocolSyncDao dao;

    public ProtocolSyncService(ProtocolSyncDao dao) {
        this.dao = dao;
    }

    /** ptlGrpCd 가 null 이면 사용 중인 전체 그룹 */
    public SyncResult<ProtocolGroupSync> getProtocolGroups(String ptlGrpCd) {

        Map<String, List<ProtocolPacketSync>> packets = new LinkedHashMap<>();
        for (Map<String, Object> r : nullSafe(dao.selectSyncPackets(ptlGrpCd))) {
            String key = str(r, "ptlGrpCd") + "\u0000" + str(r, "ptlCd");
            packets.computeIfAbsent(key, k -> new ArrayList<>()).add(new ProtocolPacketSync(
                    integer(r, "packetSeq", 0),
                    str(r, "packetType"),
                    str(r, "direction"),
                    str(r, "packetExpr"),
                    str(r, "responsePtlCd"),
                    str(r, "parseRule"),
                    integer(r, "dataCount", 0),
                    str(r, "dataType"),
                    str(r, "dataPosition")));
        }

        Map<String, String> roleNames = codeValues("PROL");
        Map<String, String> actionNames = codeValues("PACT");

        Map<String, List<ProtocolSync>> protocols = new LinkedHashMap<>();
        for (Map<String, Object> r : nullSafe(dao.selectSyncProtocols(ptlGrpCd))) {
            String grp = str(r, "ptlGrpCd");
            String ptl = str(r, "ptlCd");
            protocols.computeIfAbsent(grp, k -> new ArrayList<>()).add(new ProtocolSync(
                    ptl,
                    str(r, "ptlType"),
                    nullableInteger(r, "ptlLen"),
                    str(r, "ptlVal"),
                    str(r, "ptlNm"),
                    str(r, "ptlDesc"),
                    names(split(str(r, "ptlRoles")), roleNames),
                    name(str(r, "ptlAction"), actionNames),
                    str(r, "expectRule"),
                    yesNo(str(r, "idempotentYn")),
                    List.copyOf(packets.getOrDefault(grp + "\u0000" + ptl, List.of()))));
        }

        List<ProtocolGroupSync> groups = new ArrayList<>();
        for (Map<String, Object> r : nullSafe(dao.selectSyncGroups(ptlGrpCd))) {
            String grp = str(r, "ptlGrpCd");
            groups.add(new ProtocolGroupSync(
                    grp,
                    str(r, "ptlGrpNm"),
                    integer(r, "pollingIntval", 1000),
                    integer(r, "timeoutMs", 3000),
                    integer(r, "retryCnt", 3),
                    integer(r, "sortOrd", 0),
                    str(r, "frameRule"),
                    integer(r, "cmdGapMs", 0),
                    split(str(r, "initRoutine")),
                    integer(r, "initDelayMs", 500),
                    List.copyOf(protocols.getOrDefault(grp, List.of()))));
        }

        return result(groups);
    }

    /** devCd 가 null 이면 사용 중인 전체 장치 */
    public SyncResult<DataTagSync> getDataTags(String devCd) {

        List<DataTagSync> tags = new ArrayList<>();
        for (Map<String, Object> r : nullSafe(dao.selectSyncDataTags(devCd))) {
            tags.add(new DataTagSync(
                    str(r, "devCd"),
                    str(r, "datGrCd"),
                    str(r, "datCd"),
                    integer(r, "datIdx", 0),
                    str(r, "datType"),
                    str(r, "datUnit"),
                    str(r, "tagId"),
                    str(r, "datNm"),
                    decimal(r, "datMin"),
                    decimal(r, "datMax"),
                    integer(r, "sortOrd", 0)));
        }
        return result(tags);
    }

    /** C5c 채널 매핑 (devCd 가 null 이면 전체). 행이 없는 장치는 Desktop 이 TAG_ID=CH<n> 임시 변환을 쓴다 */
    public SyncResult<DataChannelMapSync> getDataMap(String devCd) {

        List<DataChannelMapSync> maps = new ArrayList<>();
        for (Map<String, Object> r : nullSafe(dao.selectSyncDataMap(devCd))) {
            maps.add(new DataChannelMapSync(
                    str(r, "devCd"),
                    str(r, "channelKey"),
                    str(r, "ptlCd"),
                    str(r, "datGrCd"),
                    str(r, "datCd"),
                    integer(r, "datIdx", 0),
                    dbl(r, "scale", 1),
                    dbl(r, "offsetVal", 0),
                    integer(r, "sortOrd", 0)));
        }
        return result(maps);
    }

    private Map<String, String> codeValues(String grpCd) {
        Map<String, String> m = new LinkedHashMap<>();
        for (Map<String, Object> r : nullSafe(dao.selectCodeValues(grpCd))) {
            m.put(str(r, "comCd"), str(r, "comVal"));
        }
        return m;
    }

    /** 쉼표 목록 → 순서 유지 목록 (null·빈 값이면 빈 목록) */
    static List<String> split(String text) {
        List<String> list = new ArrayList<>();
        if (text != null) {
            for (String s : text.split(",")) {
                if (!s.trim().isEmpty()) {
                    list.add(s.trim());
                }
            }
        }
        return List.copyOf(list);
    }

    /** 코드 → COM_VAL. 코드표에 없으면 코드 그대로 */
    private static String name(String code, Map<String, String> names) {
        return code == null ? null : names.getOrDefault(code, code);
    }

    private static List<String> names(List<String> codes, Map<String, String> names) {
        return codes.stream().map(c -> name(c, names)).toList();
    }

    private static Boolean yesNo(String yn) {
        if ("YENO0001".equals(yn)) {
            return Boolean.TRUE;
        }
        if ("YENO0002".equals(yn)) {
            return Boolean.FALSE;
        }
        return null;
    }

    private static double dbl(Map<String, Object> r, String key, double fallback) {
        Object v = value(r, key);
        if (v == null) {
            return fallback;
        }
        if (v instanceof Number n) {
            return n.doubleValue();
        }
        return Double.parseDouble(v.toString().trim());
    }

    static <T> SyncResult<T> result(List<T> items) {
        List<T> copy = List.copyOf(items);
        return new SyncResult<>(revisionOf(copy), copy, List.of());
    }

    /** record toString 은 필드 순서·값이 같으면 같다 → 내용 해시 */
    static String revisionOf(List<?> items) {
        try {
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            byte[] hash = md.digest(items.toString().getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(hash);
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 사용 불가", e);
        }
    }

    private static List<Map<String, Object>> nullSafe(List<Map<String, Object>> rows) {
        return rows == null ? List.of() : rows;
    }

    private static Object value(Map<String, Object> r, String key) {
        if (r.containsKey(key)) {
            return r.get(key);
        }
        // DB 드라이버가 별칭 대소문자를 바꾼 경우 대비
        for (Map.Entry<String, Object> e : r.entrySet()) {
            if (e.getKey() != null && e.getKey().equalsIgnoreCase(key)) {
                return e.getValue();
            }
        }
        return null;
    }

    private static String str(Map<String, Object> r, String key) {
        Object v = value(r, key);
        return v == null ? null : v.toString();
    }

    private static Integer nullableInteger(Map<String, Object> r, String key) {
        Object v = value(r, key);
        if (v == null) {
            return null;
        }
        if (v instanceof Number n) {
            return n.intValue();
        }
        return Integer.valueOf(v.toString().trim());
    }

    private static int integer(Map<String, Object> r, String key, int fallback) {
        Integer v = nullableInteger(r, key);
        return v == null ? fallback : v;
    }

    private static BigDecimal decimal(Map<String, Object> r, String key) {
        Object v = value(r, key);
        if (v == null) {
            return null;
        }
        if (v instanceof BigDecimal d) {
            return d;
        }
        return new BigDecimal(v.toString().trim());
    }
}
