package com.asdp.juprovider.core.protocol.dao;

import java.util.List;
import java.util.Map;

import org.apache.ibatis.annotations.Param;

/**
 * Protocol Reference Implementation DAO (ProtocolMapper.xml)
 */
public interface ProtocolDao {

    List<Map<String, Object>> selectGroups(
            @Param("keyword") String keyword,
            @Param("useYn") String useYn,
            @Param("langCd") String langCd);

    Map<String, Object> selectGroup(
            @Param("ptlGrpCd") String ptlGrpCd,
            @Param("langCd") String langCd);

    String selectGroupUseYn(@Param("ptlGrpCd") String ptlGrpCd);

    int insertGroup(Map<String, Object> group);

    int insertGroupDetail(Map<String, Object> detail);

    int updateGroup(Map<String, Object> group);

    int updateGroupDetail(Map<String, Object> detail);

    List<String> selectActiveDevicesByGroup(@Param("ptlGrpCd") String ptlGrpCd);

    List<String> selectExperimentRefsByGroup(@Param("ptlGrpCd") String ptlGrpCd);

    List<String> selectExperimentRefsByProtocol(@Param("ptlCd") String ptlCd);

    int softDeletePacketsByGroup(@Param("ptlGrpCd") String ptlGrpCd);

    int softDeleteProtocolsByGroup(@Param("ptlGrpCd") String ptlGrpCd);

    int softDeleteGroup(@Param("ptlGrpCd") String ptlGrpCd);

    List<Map<String, Object>> selectProtocols(
            @Param("ptlGrpCd") String ptlGrpCd,
            @Param("keyword") String keyword,
            @Param("useYn") String useYn,
            @Param("langCd") String langCd);

    Map<String, Object> selectProtocol(
            @Param("ptlGrpCd") String ptlGrpCd,
            @Param("ptlCd") String ptlCd,
            @Param("langCd") String langCd);

    List<Map<String, Object>> selectPackets(
            @Param("ptlGrpCd") String ptlGrpCd,
            @Param("ptlCd") String ptlCd);

    /** C5c: 그룹 INIT_ROUTINE (그룹이 없으면 null) */
    String selectGroupInitRoutine(@Param("ptlGrpCd") String ptlGrpCd);

    /** C5c: 그룹의 모든 프로토콜 ptlCd · ptlType · useYn */
    List<Map<String, Object>> selectProtocolStates(@Param("ptlGrpCd") String ptlGrpCd);

    String selectProtocolUseYn(
            @Param("ptlGrpCd") String ptlGrpCd,
            @Param("ptlCd") String ptlCd);

    int insertProtocol(Map<String, Object> protocol);

    int insertProtocolDetail(Map<String, Object> detail);

    int updateProtocol(Map<String, Object> protocol);

    int updateProtocolDetail(Map<String, Object> detail);

    int deletePackets(
            @Param("ptlGrpCd") String ptlGrpCd,
            @Param("ptlCd") String ptlCd);

    int insertPacket(Map<String, Object> packet);

    int softDeletePackets(
            @Param("ptlGrpCd") String ptlGrpCd,
            @Param("ptlCd") String ptlCd);

    int softDeleteProtocol(
            @Param("ptlGrpCd") String ptlGrpCd,
            @Param("ptlCd") String ptlCd);

    int upsertMultiLang(
            @Param("langCd") String langCd,
            @Param("resKey") String resKey,
            @Param("resVal") String resVal);
}
