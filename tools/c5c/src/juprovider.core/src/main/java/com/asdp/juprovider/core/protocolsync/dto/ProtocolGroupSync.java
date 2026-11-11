package com.asdp.juprovider.core.protocolsync.dto;

import java.util.List;

/**
 * ju_protocol_group + ju_protocol_group_detail (사용 중인 것만).
 * C5c: frameRule(JSON v1 원문), cmdGapMs, initRoutine(PTL_CD 순서 목록), initDelayMs 추가.
 */
public record ProtocolGroupSync(
        String ptlGrpCd,
        String ptlGrpNm,
        int pollingIntval,
        int timeoutMs,
        int retryCnt,
        int sortOrd,
        String frameRule,
        int cmdGapMs,
        List<String> initRoutine,
        int initDelayMs,
        List<ProtocolSync> protocols) {
}
