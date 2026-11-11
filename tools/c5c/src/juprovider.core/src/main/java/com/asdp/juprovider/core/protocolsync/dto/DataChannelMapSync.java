package com.asdp.juprovider.core.protocolsync.dto;

/**
 * C5c 채널 매핑 내려받기 (ju_data_channel_map, 사용 중인 매핑·태그·데이터 그룹만).
 * 값 환산: value × scale + offset. ptlCd 가 null 이면 모든 프로토콜에 적용.
 */
public record DataChannelMapSync(
        String devCd,
        String channelKey,
        String ptlCd,
        String datGrCd,
        String datCd,
        int datIdx,
        double scale,
        double offset,
        int sortOrd) {
}
