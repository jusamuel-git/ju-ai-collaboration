package com.asdp.juprovider.core.protocol.service;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.asdp.juprovider.core.action.contract.ActionFieldError;
import com.asdp.juprovider.core.action.dao.ActionCodeDao;
import com.asdp.juprovider.core.action.contract.ActionInput;
import com.asdp.juprovider.core.action.contract.ListOutput;
import com.asdp.juprovider.core.action.exception.ActionConflictException;
import com.asdp.juprovider.core.action.exception.ActionNotFoundException;
import com.asdp.juprovider.core.action.exception.ActionValidationException;
import com.asdp.juprovider.core.protocol.ProtocolI18nKeys;
import com.asdp.juprovider.core.protocol.dao.ProtocolDao;
import com.asdp.juprovider.core.protocol.rule.ProtocolRules;

/**
 * Protocol Reference Implementation 업무 Service (결정 AC8·AC9, PR-Q1~Q5)
 *
 * - 쓰기 메서드는 Action 실행 트랜잭션(DynamicActionService) 안에서 호출되며, 단독 호출 시에도 @Transactional
 * - 삭제는 논리 삭제(USE_YN=YENO0002)
 * - GRP_CREATE: 그룹 + 기본 프로토콜 {그룹}0000 을 같은 트랜잭션에서 생성 (PR-Q1)
 * - GRP_DELETE: 장치 + 하위 프로토콜의 실험 참조를 전체 선검사 → 하나라도 사용 중이면 409,
 *               아니면 Packet → Protocol → Group 순서로 같은 트랜잭션에서 논리 삭제 (PR-Q3)
 * - C5c 저장 검사(설계 §4): 수집 설정·역할·표현식·FRAME_RULE·PARSE_RULE·EXPECT_RULE·INIT_ROUTINE.
 *   기존 값을 그대로 다시 보낸 경우(같은 순번 패킷의 같은 값 등)는 검사하지 않는다 → GTEC0000 의 과거 비JSON PARSE_RULE 등 기존 데이터 호환.
 *   역할(PTL_ROLES)이 없는 프로토콜(미설정, 과거 데이터)은 역할·유형 연계 검사를 하지 않는다.
 */
@Service
public class ProtocolService {

    public static final String YES = "YENO0001";

    public static final String NO = "YENO0002";

    public static final String DEFAULT_PROTOCOL_SUFFIX = "0000";

    public static final String DEFAULT_PROTOCOL_TYPE = "PROT0000";

    public static final String DEFAULT_PROTOCOL_NAME = "기본 TX/RX";

    public static final String DEFAULT_PROTOCOL_DESC = "그룹 생성 시 자동 생성";

    private static final Set<String> DIRECTIONS = Set.of("TX", "RX");

    /** PTL_TYPE (설계 §2): PROT0000 POLL · 0001 TX_ONLY · 0002 RX_STREAM · 0003 TX_RX */
    public static final String TYPE_RX_STREAM = "PROT0002";

    /** PROL0003 = DATA (migration 08) */
    public static final String ROLE_DATA = "PROL0003";

    public static final int DEFAULT_CMD_GAP_MS = 0;

    public static final int DEFAULT_INIT_DELAY_MS = 500;

    private final ProtocolDao protocolDao;

    private final ActionCodeDao actionCodeDao;

    public ProtocolService(ProtocolDao protocolDao, ActionCodeDao actionCodeDao) {
        this.protocolDao = protocolDao;
        this.actionCodeDao = actionCodeDao;
    }

    // ===== Group =====

    public ListOutput<Map<String, Object>> searchGroups(ActionInput in, String langCd) {
        return ListOutput.of(protocolDao.selectGroups(
                in.getString("keyword"),
                in.getString("useYn"),
                langCd));
    }

    public Map<String, Object> getGroup(ActionInput in, String langCd) {
        String grp = in.getString("ptlGrpCd");
        Map<String, Object> group = protocolDao.selectGroup(grp, langCd);
        if (group == null) {
            throw new ActionNotFoundException("프로토콜 그룹이 없습니다. ptlGrpCd=" + grp);
        }
        return group;
    }

    @Transactional
    public Map<String, Object> createGroup(ActionInput in) {
        String grp = in.getString("ptlGrpCd");

        List<ActionFieldError> errors = new ArrayList<>();
        Integer polling = positive(in, "pollingIntval", 1, errors);
        Integer timeout = positive(in, "timeoutMs", 1, errors);
        Integer retry = positive(in, "retryCnt", 0, errors);
        Integer cmdGap = positive(in, "cmdGapMs", 0, errors);
        Integer initDelay = positive(in, "initDelayMs", 0, errors);
        String frameRule = frameRule(in, errors);
        // 새 그룹에서 초기화 루틴에 쓸 수 있는 프로토콜은 자동 생성되는 기본 프로토콜뿐
        String initRoutine = initRoutine(in, Map.of(grp + DEFAULT_PROTOCOL_SUFFIX, DEFAULT_PROTOCOL_TYPE), errors);
        failIfAny(errors);

        if (protocolDao.selectGroupUseYn(grp) != null) {
            throw new ActionConflictException("이미 있는 프로토콜 그룹입니다. ptlGrpCd=" + grp);
        }

        Map<String, Object> group = new HashMap<>();
        group.put("ptlGrpCd", grp);
        group.put("pollingIntval", polling == null ? 1000 : polling);
        group.put("timeoutMs", timeout == null ? 3000 : timeout);
        group.put("retryCnt", retry == null ? 3 : retry);
        group.put("sortOrd", in.has("sortOrd") ? in.getInteger("sortOrd") : 0);
        group.put("frameRule", frameRule);
        group.put("cmdGapMs", cmdGap == null ? DEFAULT_CMD_GAP_MS : cmdGap);
        group.put("initRoutine", initRoutine);
        group.put("initDelayMs", initDelay == null ? DEFAULT_INIT_DELAY_MS : initDelay);
        protocolDao.insertGroup(group);

        Map<String, Object> detail = new HashMap<>();
        detail.put("ptlGrpCd", grp);
        detail.put("ptlGrpNm", in.getString("ptlGrpNm"));
        detail.put("ptlGrpDesc", in.getString("ptlGrpDesc"));
        detail.put("nmKey", ProtocolI18nKeys.groupName(grp));
        detail.put("descKey", ProtocolI18nKeys.groupDesc(grp));
        protocolDao.insertGroupDetail(detail);
        upsertLang(ProtocolI18nKeys.groupName(grp), in.getString("ptlGrpNm"));
        upsertLang(ProtocolI18nKeys.groupDesc(grp), in.getString("ptlGrpDesc"));

        /*
         * PR-Q1: 기본 프로토콜 {그룹}0000 — 같은 트랜잭션. 실패하면 그룹도 함께 rollback.
         */
        String defaultCd = grp + DEFAULT_PROTOCOL_SUFFIX;
        insertProtocolRows(grp, defaultCd, DEFAULT_PROTOCOL_TYPE, null, null,
                DEFAULT_PROTOCOL_NAME, DEFAULT_PROTOCOL_DESC, Map.of());

        return key(grp, null);
    }

    @Transactional
    public Map<String, Object> updateGroup(ActionInput in) {
        String grp = in.getString("ptlGrpCd");
        if (protocolDao.selectGroupUseYn(grp) == null) {
            throw new ActionNotFoundException("프로토콜 그룹이 없습니다. ptlGrpCd=" + grp);
        }

        List<ActionFieldError> errors = new ArrayList<>();
        Integer polling = positive(in, "pollingIntval", 1, errors);
        Integer timeout = positive(in, "timeoutMs", 1, errors);
        Integer retry = positive(in, "retryCnt", 0, errors);
        String useYn = reactivateOnly(in, errors);
        Integer cmdGap = positive(in, "cmdGapMs", 0, errors);
        Integer initDelay = positive(in, "initDelayMs", 0, errors);
        String frameRule = frameRule(in, errors);
        String initRoutine = initRoutine(in, activeProtocolTypes(grp), errors);
        failIfAny(errors);

        Map<String, Object> group = new HashMap<>();
        group.put("ptlGrpCd", grp);
        group.put("pollingIntval", polling);
        group.put("timeoutMs", timeout);
        group.put("retryCnt", retry);
        group.put("sortOrd", in.has("sortOrd") ? in.getInteger("sortOrd") : null);
        group.put("useYn", useYn);
        group.put("frameRule", frameRule);
        group.put("cmdGapMs", cmdGap);
        group.put("initRoutine", initRoutine);
        group.put("initDelayMs", initDelay);
        protocolDao.updateGroup(group);

        Map<String, Object> detail = new HashMap<>();
        detail.put("ptlGrpCd", grp);
        detail.put("ptlGrpNm", in.getString("ptlGrpNm"));
        detail.put("ptlGrpDesc", in.getString("ptlGrpDesc"));
        protocolDao.updateGroupDetail(detail);
        upsertLang(ProtocolI18nKeys.groupName(grp), in.getString("ptlGrpNm"));
        upsertLang(ProtocolI18nKeys.groupDesc(grp), in.getString("ptlGrpDesc"));

        return key(grp, null);
    }

    @Transactional
    public Map<String, Object> deleteGroup(ActionInput in) {
        String grp = in.getString("ptlGrpCd");
        if (!YES.equals(protocolDao.selectGroupUseYn(grp))) {
            throw new ActionNotFoundException("사용 중인 프로토콜 그룹이 없습니다. ptlGrpCd=" + grp);
        }

        /*
         * PR-Q3: 전체 선검사 — 장치 참조 + 하위 프로토콜의 실험 참조. 하나라도 있으면 409 (아무것도 바꾸지 않음)
         */
        List<String> devices = protocolDao.selectActiveDevicesByGroup(grp);
        List<String> experiments = protocolDao.selectExperimentRefsByGroup(grp);
        if (!devices.isEmpty() || !experiments.isEmpty()) {
            throw new ActionConflictException(
                    "사용 중인 프로토콜 그룹은 삭제할 수 없습니다. ptlGrpCd=" + grp
                            + (devices.isEmpty() ? "" : ", 장치=" + devices)
                            + (experiments.isEmpty() ? "" : ", 실험(실험ID:프로토콜)=" + experiments));
        }

        /*
         * Packet → Protocol → Group (같은 트랜잭션)
         */
        protocolDao.softDeletePacketsByGroup(grp);
        protocolDao.softDeleteProtocolsByGroup(grp);
        protocolDao.softDeleteGroup(grp);

        return key(grp, null);
    }

    // ===== Protocol =====

    public ListOutput<Map<String, Object>> searchProtocols(ActionInput in, String langCd) {
        return ListOutput.of(protocolDao.selectProtocols(
                in.getString("ptlGrpCd"),
                in.getString("keyword"),
                in.getString("useYn"),
                langCd));
    }

    public Map<String, Object> getProtocol(ActionInput in, String langCd) {
        String grp = in.getString("ptlGrpCd");
        String cd = in.getString("ptlCd");
        Map<String, Object> protocol = protocolDao.selectProtocol(grp, cd, langCd);
        if (protocol == null) {
            throw new ActionNotFoundException("프로토콜이 없습니다. ptlGrpCd=" + grp + ", ptlCd=" + cd);
        }
        Map<String, Object> result = new LinkedHashMap<>(protocol);
        result.put("packets", protocolDao.selectPackets(grp, cd));
        return result;
    }

    @Transactional
    public Map<String, Object> createProtocol(ActionInput in) {
        String grp = in.getString("ptlGrpCd");
        String cd = in.getString("ptlCd");

        List<ActionFieldError> errors = new ArrayList<>();
        Integer len = positive(in, "ptlLen", 0, errors);
        List<Map<String, Object>> packets = packets(in, grp, cd, errors);
        Map<String, Object> collect = protocolCollect(in, errors);
        failIfAny(errors);

        requireActiveGroup(grp);
        if (protocolDao.selectProtocolUseYn(grp, cd) != null) {
            throw new ActionConflictException("이미 있는 프로토콜입니다. ptlGrpCd=" + grp + ", ptlCd=" + cd);
        }

        // 새 프로토콜: 기존 값이 없으므로 보낸 표현식·해석 규칙은 모두 검사
        checkExpressionAndRules(in, null, packets, List.of(), errors);
        checkRoleConsistency(cd, in.getString("ptlType"), (String) collect.get("ptlRoles"), in.getString("ptlVal"),
                packets == null ? List.of() : packets, null, errors);
        failIfAny(errors);

        insertProtocolRows(grp, cd, in.getString("ptlType"), len, in.getString("ptlVal"),
                in.getString("ptlNm"), in.getString("ptlDesc"), collect);
        if (packets != null) {
            packets.forEach(protocolDao::insertPacket);
        }

        return key(grp, cd);
    }

    @Transactional
    public Map<String, Object> updateProtocol(ActionInput in) {
        String grp = in.getString("ptlGrpCd");
        String cd = in.getString("ptlCd");

        List<ActionFieldError> errors = new ArrayList<>();
        Integer len = positive(in, "ptlLen", 0, errors);
        String useYn = reactivateOnly(in, errors);
        List<Map<String, Object>> packets = packets(in, grp, cd, errors);
        Map<String, Object> collect = protocolCollect(in, errors);
        failIfAny(errors);

        if (protocolDao.selectProtocolUseYn(grp, cd) == null) {
            throw new ActionNotFoundException("프로토콜이 없습니다. ptlGrpCd=" + grp + ", ptlCd=" + cd);
        }
        requireActiveGroup(grp);

        /*
         * C5c 검사: 바뀐 값만 형식 검사(기존 값 그대로면 통과), 역할이 있으면 저장 후 상태로 연계 검사
         */
        Map<String, Object> existing = protocolDao.selectProtocol(grp, cd, ProtocolI18nKeys.BASE_LANG);
        List<Map<String, Object>> existingPackets = nullSafe(protocolDao.selectPackets(grp, cd));
        checkExpressionAndRules(in, existing, packets, existingPackets, errors);
        checkRoleConsistency(cd,
                firstNonNull(in.getString("ptlType"), str(existing, "ptlType")),
                firstNonNull((String) collect.get("ptlRoles"), str(existing, "ptlRoles")),
                firstNonNull(in.getString("ptlVal"), str(existing, "ptlVal")),
                packets != null ? packets : existingPackets,
                protocolDao.selectGroupInitRoutine(grp),
                errors);
        failIfAny(errors);

        Map<String, Object> protocol = new HashMap<>(collect);
        protocol.put("ptlGrpCd", grp);
        protocol.put("ptlCd", cd);
        protocol.put("ptlType", in.getString("ptlType"));
        protocol.put("ptlLen", len);
        protocol.put("ptlVal", in.getString("ptlVal"));
        protocol.put("useYn", useYn);
        protocolDao.updateProtocol(protocol);

        Map<String, Object> detail = new HashMap<>();
        detail.put("ptlGrpCd", grp);
        detail.put("ptlCd", cd);
        detail.put("ptlNm", in.getString("ptlNm"));
        detail.put("ptlDesc", in.getString("ptlDesc"));
        protocolDao.updateProtocolDetail(detail);
        upsertLang(ProtocolI18nKeys.protocolName(grp, cd), in.getString("ptlNm"));
        upsertLang(ProtocolI18nKeys.protocolDesc(grp, cd), in.getString("ptlDesc"));

        /*
         * packets를 보내면 전체 교체 (보내지 않으면 유지)
         */
        if (packets != null) {
            protocolDao.deletePackets(grp, cd);
            packets.forEach(protocolDao::insertPacket);
        }

        return key(grp, cd);
    }

    @Transactional
    public Map<String, Object> deleteProtocol(ActionInput in) {
        String grp = in.getString("ptlGrpCd");
        String cd = in.getString("ptlCd");
        if (!YES.equals(protocolDao.selectProtocolUseYn(grp, cd))) {
            throw new ActionNotFoundException("사용 중인 프로토콜이 없습니다. ptlGrpCd=" + grp + ", ptlCd=" + cd);
        }

        List<String> experiments = protocolDao.selectExperimentRefsByProtocol(cd);
        if (!experiments.isEmpty()) {
            throw new ActionConflictException(
                    "실험에서 사용 중인 프로토콜은 삭제할 수 없습니다. ptlCd=" + cd
                            + ", 실험(실험ID:프로토콜)=" + experiments);
        }
        if (routineItems(protocolDao.selectGroupInitRoutine(grp)).contains(cd)) {
            throw new ActionConflictException(
                    "그룹 초기화 루틴(INIT_ROUTINE)에서 사용 중인 프로토콜은 삭제할 수 없습니다. ptlGrpCd=" + grp + ", ptlCd=" + cd);
        }

        protocolDao.softDeletePackets(grp, cd);
        protocolDao.softDeleteProtocol(grp, cd);

        return key(grp, cd);
    }

    // ===== 내부 =====

    private void insertProtocolRows(
            String grp,
            String cd,
            String type,
            Integer len,
            String val,
            String name,
            String desc,
            Map<String, Object> collect) {
        Map<String, Object> protocol = new HashMap<>(collect);
        protocol.put("ptlGrpCd", grp);
        protocol.put("ptlCd", cd);
        protocol.put("ptlType", type);
        protocol.put("ptlLen", len);
        protocol.put("ptlVal", val);
        protocolDao.insertProtocol(protocol);

        Map<String, Object> detail = new HashMap<>();
        detail.put("ptlGrpCd", grp);
        detail.put("ptlCd", cd);
        detail.put("ptlNm", name);
        detail.put("ptlDesc", desc);
        detail.put("nmKey", ProtocolI18nKeys.protocolName(grp, cd));
        detail.put("descKey", ProtocolI18nKeys.protocolDesc(grp, cd));
        protocolDao.insertProtocolDetail(detail);
        upsertLang(ProtocolI18nKeys.protocolName(grp, cd), name);
        upsertLang(ProtocolI18nKeys.protocolDesc(grp, cd), desc);
    }

    private void requireActiveGroup(String grp) {
        String useYn = protocolDao.selectGroupUseYn(grp);
        if (useYn == null) {
            throw new ActionNotFoundException("프로토콜 그룹이 없습니다. ptlGrpCd=" + grp);
        }
        if (!YES.equals(useYn)) {
            throw new ActionConflictException("삭제된 프로토콜 그룹입니다. ptlGrpCd=" + grp);
        }
    }

    /** LANG0001 값만 저장 (결정 AC9). 값이 없으면 건드리지 않는다. */
    private void upsertLang(String key, String value) {
        if (value != null) {
            protocolDao.upsertMultiLang(ProtocolI18nKeys.BASE_LANG, key, value);
        }
    }

    private static Integer positive(ActionInput in, String name, int min, List<ActionFieldError> errors) {
        if (!in.has(name)) {
            return null;
        }
        Long value = in.getLong(name);
        if (value < min || value > Integer.MAX_VALUE) {
            errors.add(new ActionFieldError(name, ActionFieldError.INVALID_VALUE, min + " 이상이어야 합니다."));
            return null;
        }
        return value.intValue();
    }

    /** 수정 Action의 useYn은 재사용(YENO0001)만 허용. 삭제는 DELETE Action으로만 (선검사 우회 방지) */
    private static String reactivateOnly(ActionInput in, List<ActionFieldError> errors) {
        if (!in.has("useYn")) {
            return null;
        }
        String useYn = in.getString("useYn");
        if (!YES.equals(useYn)) {
            errors.add(new ActionFieldError("useYn", ActionFieldError.INVALID_VALUE,
                    "수정에서는 재사용(YENO0001)만 지정할 수 있습니다. 삭제는 삭제 Action을 사용하세요."));
            return null;
        }
        return useYn;
    }

    private static List<Map<String, Object>> packets(
            ActionInput in,
            String grp,
            String cd,
            List<ActionFieldError> errors) {
        List<ActionInput> items = in.getObjectList("packets");
        if (items == null) {
            return null;
        }
        List<Map<String, Object>> rows = new ArrayList<>();
        Set<Long> seqs = new HashSet<>();
        for (int i = 0; i < items.size(); i++) {
            ActionInput p = items.get(i);
            String prefix = "packets[" + i + "].";
            Long seq = p.getLong("packetSeq");
            if (seq < 1 || seq > Integer.MAX_VALUE) {
                errors.add(new ActionFieldError(prefix + "packetSeq", ActionFieldError.INVALID_VALUE, "1 이상이어야 합니다."));
            } else if (!seqs.add(seq)) {
                errors.add(new ActionFieldError(prefix + "packetSeq", ActionFieldError.DUPLICATE, "패킷 순번이 중복됩니다."));
            }
            if (!DIRECTIONS.contains(p.getString("direction"))) {
                errors.add(new ActionFieldError(prefix + "direction", ActionFieldError.INVALID_VALUE, "TX 또는 RX만 허용됩니다."));
            }
            Long count = p.has("dataCount") ? p.getLong("dataCount") : 0L;
            if (count < 0 || count > Integer.MAX_VALUE) {
                errors.add(new ActionFieldError(prefix + "dataCount", ActionFieldError.INVALID_VALUE, "0 이상이어야 합니다."));
            }

            Map<String, Object> row = new HashMap<>();
            row.put("ptlGrpCd", grp);
            row.put("ptlCd", cd);
            row.put("packetSeq", seq);
            row.put("packetType", p.getString("packetType"));
            row.put("direction", p.getString("direction"));
            row.put("packetExpr", p.getString("packetExpr"));
            row.put("responsePtlCd", p.getString("responsePtlCd"));
            row.put("parseRule", p.getString("parseRule"));
            row.put("dataCount", count);
            row.put("dataType", p.getString("dataType"));
            row.put("dataPosition", p.getString("dataPosition"));
            rows.add(row);
        }
        return rows;
    }

    // ===== C5c 저장 검사 =====

    private static String frameRule(ActionInput in, List<ActionFieldError> errors) {
        if (!in.has("frameRule")) {
            return null;
        }
        String text = in.getString("frameRule").trim();
        try {
            ProtocolRules.validateFrameRule(text);
        } catch (ProtocolRules.RuleException e) {
            errors.add(new ActionFieldError("frameRule", ActionFieldError.INVALID_VALUE, e.getMessage()));
            return null;
        }
        return text;
    }

    /** 사용 중인 프로토콜 ptlCd → ptlType */
    private Map<String, String> activeProtocolTypes(String grp) {
        Map<String, String> types = new HashMap<>();
        for (Map<String, Object> r : nullSafe(protocolDao.selectProtocolStates(grp))) {
            if (YES.equals(str(r, "useYn"))) {
                types.put(str(r, "ptlCd"), str(r, "ptlType"));
            }
        }
        return types;
    }

    /** INIT_ROUTINE: 같은 그룹의 사용 중 PTL_CD 쉼표 목록, RX_STREAM 불가. 저장 형식 = 공백 없는 쉼표 목록 */
    private static String initRoutine(ActionInput in, Map<String, String> activeTypes, List<ActionFieldError> errors) {
        if (!in.has("initRoutine")) {
            return null;
        }
        List<String> items = new ArrayList<>();
        for (String raw : in.getString("initRoutine").split(",", -1)) {
            String cd = raw.trim();
            if (cd.isEmpty()) {
                errors.add(new ActionFieldError("initRoutine", ActionFieldError.INVALID_VALUE,
                        "빈 항목이 있습니다. PTL_CD 쉼표 목록이어야 합니다."));
                return null;
            }
            String type = activeTypes.get(cd);
            if (type == null) {
                errors.add(new ActionFieldError("initRoutine", ActionFieldError.INVALID_VALUE,
                        "같은 그룹의 사용 중인 프로토콜이 아닙니다: " + cd));
                return null;
            }
            if (TYPE_RX_STREAM.equals(type)) {
                errors.add(new ActionFieldError("initRoutine", ActionFieldError.INVALID_VALUE,
                        "수신 전용(RX_STREAM) 프로토콜은 초기화 루틴에 넣을 수 없습니다: " + cd));
                return null;
            }
            items.add(cd);
        }
        return String.join(",", items);
    }

    private static List<String> routineItems(String routine) {
        List<String> items = new ArrayList<>();
        if (routine != null) {
            for (String s : routine.split(",")) {
                if (!s.trim().isEmpty()) {
                    items.add(s.trim());
                }
            }
        }
        return items;
    }

    /** ptlRoles(PROL 코드 쉼표 목록, 1개 이상·중복 불가, 정렬 저장)·ptlAction·expectRule·idempotentYn */
    private Map<String, Object> protocolCollect(ActionInput in, List<ActionFieldError> errors) {
        Map<String, Object> m = new HashMap<>();
        if (in.has("ptlRoles")) {
            Set<String> valid = new HashSet<>(nullSafeStrings(actionCodeDao.selectActiveCodes("PROL")));
            java.util.TreeSet<String> roles = new java.util.TreeSet<>();
            boolean ok = true;
            for (String raw : in.getString("ptlRoles").split(",", -1)) {
                String code = raw.trim();
                if (!valid.contains(code)) {
                    errors.add(new ActionFieldError("ptlRoles", ActionFieldError.INVALID_CODE,
                            "역할은 PROL 공통코드 쉼표 목록입니다: '" + code + "'"));
                    ok = false;
                    break;
                }
                if (!roles.add(code)) {
                    errors.add(new ActionFieldError("ptlRoles", ActionFieldError.DUPLICATE, "역할이 중복됩니다: " + code));
                    ok = false;
                    break;
                }
            }
            if (ok) {
                m.put("ptlRoles", String.join(",", roles));
            }
        }
        if (in.has("ptlAction")) {
            m.put("ptlAction", in.getString("ptlAction"));
        }
        if (in.has("expectRule")) {
            String text = in.getString("expectRule").trim();
            try {
                ProtocolRules.validateExpectRule(text);
                m.put("expectRule", text);
            } catch (ProtocolRules.RuleException e) {
                errors.add(new ActionFieldError("expectRule", ActionFieldError.INVALID_VALUE, e.getMessage()));
            }
        }
        if (in.has("idempotentYn")) {
            String yn = in.getString("idempotentYn");
            if (!YES.equals(yn) && !NO.equals(yn)) {
                errors.add(new ActionFieldError("idempotentYn", ActionFieldError.INVALID_VALUE,
                        "YENO0001(예) 또는 YENO0002(아니오)만 허용됩니다."));
            } else {
                m.put("idempotentYn", yn);
            }
        }
        return m;
    }

    /**
     * 표현식(ptlVal, 패킷 packetExpr) 문법과 RX 해석 규칙(parseRule = JSON v1) 검사.
     * 기존 값과 같은 값(ptlVal, 같은 순번 패킷의 같은 값)은 검사하지 않는다 → 과거 데이터 호환.
     */
    private static void checkExpressionAndRules(
            ActionInput in,
            Map<String, Object> existing,
            List<Map<String, Object>> packets,
            List<Map<String, Object>> existingPackets,
            List<ActionFieldError> errors) {
        if (in.has("ptlVal") && !in.getString("ptlVal").equals(str(existing, "ptlVal"))) {
            expression(in.getString("ptlVal"), "ptlVal", errors);
        }
        if (packets == null) {
            return;
        }
        Map<Long, Map<String, Object>> old = new HashMap<>();
        for (Map<String, Object> p : existingPackets) {
            Object seq = p.get("packetSeq");
            if (seq instanceof Number n) {
                old.put(n.longValue(), p);
            }
        }
        for (int i = 0; i < packets.size(); i++) {
            Map<String, Object> p = packets.get(i);
            Map<String, Object> before = p.get("packetSeq") instanceof Number n ? old.get(n.longValue()) : null;
            String expr = (String) p.get("packetExpr");
            if (expr != null && !expr.equals(str(before, "packetExpr"))) {
                expression(expr, "packets[" + i + "].packetExpr", errors);
            }
            String rule = (String) p.get("parseRule");
            if (rule != null && !rule.equals(str(before, "parseRule"))) {
                try {
                    ProtocolRules.validateParseRule(rule);
                } catch (ProtocolRules.RuleException e) {
                    errors.add(new ActionFieldError("packets[" + i + "].parseRule", ActionFieldError.INVALID_VALUE, e.getMessage()));
                }
            }
        }
    }

    private static void expression(String value, String field, List<ActionFieldError> errors) {
        try {
            ProtocolRules.validateExpression(value);
        } catch (ProtocolRules.RuleException e) {
            errors.add(new ActionFieldError(field, ActionFieldError.INVALID_VALUE, "표현식 오류: " + e.getMessage()));
        }
    }

    /**
     * 역할이 설정된 프로토콜의 저장 후 상태 검사 (역할 없음 = 미설정 → 검사 안 함):
     * - RX_STREAM: DATA 역할 + 사용할 수 있는 RX 패킷 PARSE_RULE(JSON v1) 필수, 그룹 초기화 루틴에 있으면 불가
     * - 그 외(POLL·TX_ONLY·TX_RX): 송신 표현식(PTL_VAL 또는 TX 패킷 PACKET_EXPR) 필수
     */
    private static void checkRoleConsistency(
            String cd,
            String type,
            String roles,
            String ptlVal,
            List<Map<String, Object>> packets,
            String groupInitRoutine,
            List<ActionFieldError> errors) {
        if (roles == null || roles.isBlank() || type == null) {
            return;
        }
        if (TYPE_RX_STREAM.equals(type)) {
            if (!routineItems(roles).contains(ROLE_DATA)) {
                errors.add(new ActionFieldError("ptlRoles", ActionFieldError.INVALID_VALUE,
                        "수신 전용(RX_STREAM) 프로토콜은 DATA 역할(" + ROLE_DATA + ")이 필요합니다."));
            }
            boolean parse = false;
            for (Map<String, Object> p : packets) {
                String rule = str(p, "parseRule");
                if ("RX".equals(str(p, "direction")) && ProtocolRules.isJsonRule(rule)) {
                    try {
                        ProtocolRules.validateParseRule(rule);
                        parse = true;
                        break;
                    } catch (ProtocolRules.RuleException e) {
                        // 다음 RX 패킷 확인
                    }
                }
            }
            if (!parse) {
                errors.add(new ActionFieldError("packets", ActionFieldError.REQUIRED,
                        "수신 전용(RX_STREAM) 프로토콜은 해석 규칙(JSON v1)이 있는 RX 패킷이 필요합니다."));
            }
            if (routineItems(groupInitRoutine).contains(cd)) {
                errors.add(new ActionFieldError("ptlType", ActionFieldError.INVALID_VALUE,
                        "그룹 초기화 루틴에 있는 프로토콜은 수신 전용(RX_STREAM)으로 바꿀 수 없습니다."));
            }
            return;
        }
        boolean tx = ptlVal != null && !ptlVal.isBlank();
        for (Map<String, Object> p : packets) {
            String expr = str(p, "packetExpr");
            if ("TX".equals(str(p, "direction")) && expr != null && !expr.isBlank()) {
                tx = true;
            }
        }
        if (!tx) {
            errors.add(new ActionFieldError("ptlVal", ActionFieldError.REQUIRED,
                    "송신 프로토콜은 송신 표현식(ptlVal 또는 TX 패킷 packetExpr)이 필요합니다."));
        }
    }

    private static String str(Map<String, Object> m, String key) {
        if (m == null) {
            return null;
        }
        Object v = m.get(key);
        return v == null ? null : v.toString();
    }

    private static String firstNonNull(String a, String b) {
        return a != null ? a : b;
    }

    private static List<Map<String, Object>> nullSafe(List<Map<String, Object>> rows) {
        return rows == null ? List.of() : rows;
    }

    private static List<String> nullSafeStrings(List<String> rows) {
        return rows == null ? List.of() : rows;
    }

    private static void failIfAny(List<ActionFieldError> errors) {
        if (!errors.isEmpty()) {
            throw new ActionValidationException(errors);
        }
    }

    private static Map<String, Object> key(String grp, String cd) {
        Map<String, Object> key = new LinkedHashMap<>();
        key.put("ptlGrpCd", grp);
        if (cd != null) {
            key.put("ptlCd", cd);
        }
        return key;
    }
}
