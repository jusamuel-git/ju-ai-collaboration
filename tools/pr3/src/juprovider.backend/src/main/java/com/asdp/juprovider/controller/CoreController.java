package com.asdp.juprovider.controller;

import com.asdp.juprovider.dto.ApiResponse;
import com.asdp.juprovider.service.CoreQueryService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/core")
public class CoreController {

    private static final String DEFAULT_LANG = "LANG0001";

    private final CoreQueryService coreQueryService;

    public CoreController(CoreQueryService coreQueryService) {
        this.coreQueryService = coreQueryService;
    }

    @GetMapping("/languages")
    public ApiResponse<?> languages() {
        return ApiResponse.ok(coreQueryService.languages());
    }

    @GetMapping("/common/groups")
    public ApiResponse<?> commonGroups(
            @RequestParam(defaultValue = DEFAULT_LANG) String langCd) {
        return ApiResponse.ok(coreQueryService.commonGroups(langCd));
    }

    @GetMapping("/common/codes/{grpCd}")
    public ApiResponse<?> commonCodes(
            @PathVariable String grpCd,
            @RequestParam(defaultValue = DEFAULT_LANG) String langCd) {
        return ApiResponse.ok(coreQueryService.commonCodes(grpCd, langCd));
    }

    @GetMapping("/menus")
    public ApiResponse<?> menus(
            @RequestParam(defaultValue = DEFAULT_LANG) String langCd) {
        return ApiResponse.ok(coreQueryService.menus(langCd));
    }

    @GetMapping("/devices")
    public ApiResponse<?> devices() {
        return ApiResponse.ok(coreQueryService.devices());
    }

    // PR-3 (AC10): /protocol-groups, /protocols/{ptlGrpCd} 제거 → 프로토콜관리 Action(M02010100)으로 대체

    @GetMapping("/data-groups")
    public ApiResponse<?> dataGroups() {
        return ApiResponse.ok(coreQueryService.dataGroups());
    }

    @GetMapping("/data-tags/{datGrCd}")
    public ApiResponse<?> dataTags(@PathVariable String datGrCd) {
        return ApiResponse.ok(coreQueryService.dataTags(datGrCd));
    }

    @GetMapping("/experiments")
    public ApiResponse<?> experiments() {
        return ApiResponse.ok(coreQueryService.experiments());
    }

    @GetMapping("/experiment-runs")
    public ApiResponse<?> experimentRuns(
            @RequestParam(required = false) Long expId) {
        return ApiResponse.ok(coreQueryService.experimentRuns(expId));
    }

    @GetMapping("/runtime")
    public ApiResponse<?> runtimeData(
            @RequestParam(required = false) String clientId) {
        return ApiResponse.ok(coreQueryService.runtimeData(clientId));
    }
}
