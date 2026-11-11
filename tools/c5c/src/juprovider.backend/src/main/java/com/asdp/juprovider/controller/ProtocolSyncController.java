package com.asdp.juprovider.controller;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.asdp.juprovider.core.protocolsync.dto.DataChannelMapSync;
import com.asdp.juprovider.core.protocolsync.dto.DataTagSync;
import com.asdp.juprovider.core.protocolsync.dto.ProtocolGroupSync;
import com.asdp.juprovider.core.protocolsync.dto.SyncResult;
import com.asdp.juprovider.core.protocolsync.service.ProtocolSyncService;

/**
 * C4 프로토콜·데이터 태그 내려받기 (Client 체인: X-JU-Client-Id / X-JU-Client-Key, GET 만).
 *
 * 응답: { revision, items, removed }
 * C5c: GET /data-map 채널 매핑 추가 (같은 Client 체인·GET 만).
 */
@RestController
@RequestMapping("/api/core/sync")
public class ProtocolSyncController {

    private final ProtocolSyncService protocolSyncService;

    public ProtocolSyncController(ProtocolSyncService protocolSyncService) {
        this.protocolSyncService = protocolSyncService;
    }

    /** 사용 중인 전체 프로토콜 그룹 (프로토콜·패킷 포함) */
    @GetMapping("/protocols")
    public ResponseEntity<SyncResult<ProtocolGroupSync>> getProtocolGroups() {
        return ResponseEntity.ok(protocolSyncService.getProtocolGroups(null));
    }

    /** 프로토콜 그룹 1개. 없거나 미사용이면 404 */
    @GetMapping("/protocols/{ptlGrpCd}")
    public ResponseEntity<SyncResult<ProtocolGroupSync>> getProtocolGroup(@PathVariable String ptlGrpCd) {
        SyncResult<ProtocolGroupSync> result = protocolSyncService.getProtocolGroups(ptlGrpCd);
        if (result.items().isEmpty()) {
            return ResponseEntity.notFound().build();
        }
        return ResponseEntity.ok(result);
    }

    /** 장치의 데이터 태그 (devCd 없으면 전체) */
    @GetMapping("/data-tags")
    public ResponseEntity<SyncResult<DataTagSync>> getDataTags(
            @RequestParam(name = "devCd", required = false) String devCd) {
        String dev = devCd == null || devCd.isBlank() ? null : devCd.trim();
        return ResponseEntity.ok(protocolSyncService.getDataTags(dev));
    }

    /** C5c 장치 채널 → 논리 Data 매핑 (devCd 없으면 전체). 매핑이 없는 장치는 빈 목록 */
    @GetMapping("/data-map")
    public ResponseEntity<SyncResult<DataChannelMapSync>> getDataMap(
            @RequestParam(name = "devCd", required = false) String devCd) {
        String dev = devCd == null || devCd.isBlank() ? null : devCd.trim();
        return ResponseEntity.ok(protocolSyncService.getDataMap(dev));
    }
}
