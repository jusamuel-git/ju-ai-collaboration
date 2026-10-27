package com.asdp.juprovider.controller;

import java.util.List;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.asdp.juprovider.core.device.dto.DeviceSyncDto;
import com.asdp.juprovider.core.device.service.DeviceSyncService;

@RestController
@RequestMapping("/api/core/sync/devices")
public class DeviceSyncController {

    private final DeviceSyncService deviceSyncService;

    public DeviceSyncController(
        DeviceSyncService deviceSyncService
    ) {
        this.deviceSyncService = deviceSyncService;
    }

    /**
     * Client Device 전체 동기화 조회.
     *
     * 사용 중인 Device만 반환한다.
     */
    @GetMapping
    public ResponseEntity<List<DeviceSyncDto>> getDevices() {

        return ResponseEntity.ok(
            deviceSyncService.getDevices()
        );
    }

    /**
     * 특정 Device 동기화 조회.
     *
     * 비활성 Device도 조회할 수 있다.
     */
    @GetMapping("/{devCd}")
    public ResponseEntity<DeviceSyncDto> getDevice(
        @PathVariable String devCd
    ) {

        DeviceSyncDto device =
            deviceSyncService.getDevice(devCd);

        if (device == null) {
            return ResponseEntity.notFound().build();
        }

        return ResponseEntity.ok(device);
    }

    /*
     * SEC-S1: Client -> Server Device 저장(PUT) 경로는 제거했다.
     * 공통 Device 정의는 서버가 소유하며 관리자 Action으로만 수정한다.
     * Client 체인은 GET만 허용한다 (SecurityConfig).
     */
}
