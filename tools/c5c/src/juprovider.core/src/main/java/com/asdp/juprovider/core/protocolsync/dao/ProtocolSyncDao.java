package com.asdp.juprovider.core.protocolsync.dao;

import java.util.List;
import java.util.Map;

import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;

/**
 * C4 내려받기 조회 (읽기 전용). 결과 키는 camelCase 별칭.
 * ptlGrpCd / devCd 가 null 이면 전체.
 */
@Mapper
public interface ProtocolSyncDao {

    List<Map<String, Object>> selectSyncGroups(@Param("ptlGrpCd") String ptlGrpCd);

    List<Map<String, Object>> selectSyncProtocols(@Param("ptlGrpCd") String ptlGrpCd);

    List<Map<String, Object>> selectSyncPackets(@Param("ptlGrpCd") String ptlGrpCd);

    List<Map<String, Object>> selectSyncDataTags(@Param("devCd") String devCd);

    /** C5c: 공통코드 COM_CD → COM_VAL (comCd, comVal) */
    List<Map<String, Object>> selectCodeValues(@Param("grpCd") String grpCd);

    /** C5c: 채널 매핑 (devCd 가 null 이면 전체) */
    List<Map<String, Object>> selectSyncDataMap(@Param("devCd") String devCd);
}
