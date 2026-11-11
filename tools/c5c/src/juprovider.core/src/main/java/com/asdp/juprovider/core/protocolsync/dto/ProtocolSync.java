package com.asdp.juprovider.core.protocolsync.dto;

import java.util.List;

/**
 * ju_protocol + ju_protocol_detail (사용 중인 것만).
 * C5c: roles(INFO/CONTROL/DATA, 미설정이면 빈 목록), action(NONE/START/PAUSE/STOP 또는 null),
 *      expect(응답 판정 JSON 원문 또는 null), idempotent(명시값, 미지정이면 null) 추가.
 */
public record ProtocolSync(
        String ptlCd,
        String ptlType,
        Integer ptlLen,
        String ptlVal,
        String ptlNm,
        String ptlDesc,
        List<String> roles,
        String action,
        String expect,
        Boolean idempotent,
        List<ProtocolPacketSync> packets) {
}
